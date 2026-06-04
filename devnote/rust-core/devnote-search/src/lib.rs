//! 全文检索引擎 —— 基于 FTS5 实现笔记内容全文检索
//! 借鉴思源笔记的全文检索方案，支持引号语法和布尔查询
//!
//! 借鉴思源笔记的全文检索方案
//! 来源: https://github.com/siyuan-note/siyuan
//! 借鉴内容: SQLite FTS5 虚拟表索引、snippet 高亮标记、filter 前缀语法解析（tag:/folder:）

use devnote_observe::{info, instrument, warn};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};
use std::sync::Mutex;
use rusqlite::params;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Highlight {
    pub start: usize,
    pub end: usize,
    pub text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    pub note_id: Uuid,
    pub title: String,
    pub snippet: String,
    pub highlights: Vec<Highlight>,
    pub score: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DateRange {
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchFilter {
    pub folder_id: Option<Uuid>,
    pub tags: Vec<String>,
    pub date_range: Option<DateRange>,
}

pub trait SearchEngine: Send + Sync {
    fn index_note(&mut self, note_id: &Uuid, title: &str, content: &str) -> anyhow::Result<()>;
    fn remove_note(&mut self, note_id: &Uuid) -> anyhow::Result<()>;
    fn search(&self, query: &str, limit: usize, offset: usize) -> anyhow::Result<Vec<SearchResult>>;
    fn search_with_filter(&self, query: &str, filter: &SearchFilter, limit: usize, offset: usize) -> anyhow::Result<Vec<SearchResult>>;
    fn rebuild_index(&mut self) -> anyhow::Result<()>;
}

const FTS_SCHEMA: &str = r#"
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
    note_id,
    title,
    content,
    folder_id,
    tags,
    updated_at,
    content='notes_search_content',
    content_rowid='rowid'
);

CREATE TABLE IF NOT EXISTS notes_search_content(
    rowid INTEGER PRIMARY KEY,
    note_id TEXT NOT NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL DEFAULT '',
    folder_id TEXT NOT NULL DEFAULT '',
    tags TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL DEFAULT ''
);

CREATE TRIGGER IF NOT EXISTS notes_search_ai AFTER INSERT ON notes_search_content BEGIN
    INSERT INTO notes_fts(rowid, note_id, title, content, folder_id, tags, updated_at)
    VALUES (new.rowid, new.note_id, new.title, new.content, new.folder_id, new.tags, new.updated_at);
END;

CREATE TRIGGER IF NOT EXISTS notes_search_ad AFTER DELETE ON notes_search_content BEGIN
    INSERT INTO notes_fts(notes_fts, rowid, note_id, title, content, folder_id, tags, updated_at)
    VALUES ('delete', old.rowid, old.note_id, old.title, old.content, old.folder_id, old.tags, old.updated_at);
END;

CREATE TRIGGER IF NOT EXISTS notes_search_au AFTER UPDATE ON notes_search_content BEGIN
    INSERT INTO notes_fts(notes_fts, rowid, note_id, title, content, folder_id, tags, updated_at)
    VALUES ('delete', old.rowid, old.note_id, old.title, old.content, old.folder_id, old.tags, old.updated_at);
    INSERT INTO notes_fts(rowid, note_id, title, content, folder_id, tags, updated_at)
    VALUES (new.rowid, new.note_id, new.title, new.content, new.folder_id, new.tags, new.updated_at);
END;

CREATE INDEX IF NOT EXISTS idx_search_content_note_id ON notes_search_content(note_id);
"#;

fn parse_filter(input: &str) -> (Vec<(String, String)>, String) {
    let mut filters = Vec::new();
    let mut text_parts: Vec<String> = Vec::new();
    let chars: Vec<char> = input.chars().collect();
    let mut i = 0;

    while i < chars.len() {
        if i + 1 < chars.len() && chars[i + 1] == ':' {
            // Found a filter key
            let key_start = i;
            i += 2; // skip key and colon

            let value = if i < chars.len() && (chars[i] == '"' || chars[i] == '\'') {
                // Quoted value
                let quote = chars[i];
                i += 1;
                let value_start = i;
                while i < chars.len() && chars[i] != quote {
                    i += 1;
                }
                let value: String = chars[value_start..i].iter().collect();
                if i < chars.len() {
                    i += 1; // skip closing quote
                }
                value
            } else {
                // Unquoted value - read until space
                let value_start = i;
                while i < chars.len() && chars[i] != ' ' {
                    i += 1;
                }
                chars[value_start..i].iter().collect()
            };

            let key: String = chars[key_start..key_start+1].iter().collect();
            filters.push((key.to_lowercase(), value));
        } else {
            // Text search part
            let start = i;
            while i < chars.len() && chars[i] != ' ' && (i + 1 >= chars.len() || chars[i + 1] != ':') {
                i += 1;
            }
            if i > start {
                text_parts.push(chars[start..i].iter().collect());
            }
        }

        // Skip whitespace
        while i < chars.len() && chars[i] == ' ' {
            i += 1;
        }
    }

    (filters, text_parts.join(" "))
}

#[derive(Debug)]
pub struct SqliteSearchEngine {
    conn: Mutex<rusqlite::Connection>,
}

impl SqliteSearchEngine {
    pub fn init(db_path: &str) -> anyhow::Result<Self> {
        let conn = rusqlite::Connection::open(db_path)?;
        conn.execute_batch("PRAGMA journal_mode=WAL;")?;
        let engine = Self {
            conn: Mutex::new(conn),
        };
        engine.init_schema()?;
        Ok(engine)
    }

    pub fn in_memory() -> anyhow::Result<Self> {
        let conn = rusqlite::Connection::open_in_memory()?;
        let engine = Self {
            conn: Mutex::new(conn),
        };
        engine.init_schema()?;
        Ok(engine)
    }

    fn init_schema(&self) -> anyhow::Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute_batch(FTS_SCHEMA)?;
        Ok(())
    }

    pub fn index_note_with_meta(
        &self,
        note_id: &Uuid,
        title: &str,
        content: &str,
        folder_id: &Uuid,
        tags: &[String],
        updated_at: &DateTime<Utc>,
    ) -> anyhow::Result<()> {
        let conn = self.conn.lock().unwrap();
        let note_id_str = note_id.to_string();
        let folder_id_str = folder_id.to_string();
        let tags_str = tags.join(",");
        let updated_at_str = updated_at.to_rfc3339();

        conn.execute(
            "DELETE FROM notes_search_content WHERE note_id = ?1",
            params![note_id_str],
        )?;

        conn.execute(
            "INSERT INTO notes_search_content (note_id, title, content, folder_id, tags, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![note_id_str, title, content, folder_id_str, tags_str, updated_at_str],
        )?;

        Ok(())
    }

    fn parse_highlights(snippet: &str) -> Vec<Highlight> {
        let mut highlights = Vec::new();
        let mut search_pos = 0;
        let marker_open = "\x01";
        let marker_close = "\x02";

        while let Some(open_start) = snippet[search_pos..].find(marker_open) {
            let abs_open = search_pos + open_start;
            if let Some(close_start) = snippet[abs_open + marker_open.len()..].find(marker_close) {
                let abs_close = abs_open + marker_open.len() + close_start;
                let text = snippet[abs_open + marker_open.len()..abs_close].to_string();
                let clean_start = abs_open - open_start;
                highlights.push(Highlight {
                    start: clean_start,
                    end: clean_start + text.len(),
                    text,
                });
                search_pos = abs_close + marker_close.len();
            } else {
                break;
            }
        }

        highlights
    }

    fn strip_snippet_markers(snippet: &str) -> String {
        snippet
            .replace("\x01", "")
            .replace("\x02", "")
    }

    fn row_to_search_result(row: &rusqlite::Row) -> rusqlite::Result<SearchResult> {
        let note_id_str: String = row.get(0)?;
        let title: String = row.get(1)?;
        let snippet_raw: String = row.get(2)?;
        let score: f64 = row.get(3)?;

        let highlights = Self::parse_highlights(&snippet_raw);
        let snippet = Self::strip_snippet_markers(&snippet_raw);

        Ok(SearchResult {
            note_id: Uuid::parse_str(&note_id_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            title,
            snippet,
            highlights,
            score,
        })
    }
}

impl SearchEngine for SqliteSearchEngine {
    fn index_note(&mut self, note_id: &Uuid, title: &str, content: &str) -> anyhow::Result<()> {
        let conn = self.conn.lock().unwrap();
        let note_id_str = note_id.to_string();

        conn.execute(
            "DELETE FROM notes_search_content WHERE note_id = ?1",
            params![note_id_str],
        )?;

        conn.execute(
            "INSERT INTO notes_search_content (note_id, title, content, folder_id, tags, updated_at) VALUES (?1, ?2, ?3, '', '', '')",
            params![note_id_str, title, content],
        )?;

        Ok(())
    }

    fn remove_note(&mut self, note_id: &Uuid) -> anyhow::Result<()> {
        let conn = self.conn.lock().unwrap();
        let note_id_str = note_id.to_string();
        conn.execute(
            "DELETE FROM notes_search_content WHERE note_id = ?1",
            params![note_id_str],
        )?;
        Ok(())
    }

    #[instrument]
    fn search(&self, query: &str, limit: usize, offset: usize) -> anyhow::Result<Vec<SearchResult>> {
        let conn = self.conn.lock().unwrap();
        let fts_query = format!("{{title content}} : {}", query);
        let sql = format!(
            "SELECT c.note_id, c.title, snippet(notes_fts, 1, '\\x01', '\\x02', '...', 32) as snippet, rank as score \
             FROM notes_fts f \
             JOIN notes_search_content c ON f.rowid = c.rowid \
             WHERE notes_fts MATCH ?1 \
             ORDER BY rank \
             LIMIT ?2 OFFSET ?3"
        );

        let mut stmt = conn.prepare(&sql)?;
        let results = stmt
            .query_map(params![fts_query, limit as i64, offset as i64], Self::row_to_search_result)?
            .collect::<Result<Vec<_>, _>>()?;

        info!(
            "search query='{}' results={} limit={} offset={}",
            query,
            results.len(),
            limit,
            offset
        );

        Ok(results)
    }

    #[instrument]
    fn search_with_filter(&self, query: &str, filter: &SearchFilter, limit: usize, offset: usize) -> anyhow::Result<Vec<SearchResult>> {
        let conn = self.conn.lock().unwrap();
        let fts_query = format!("{{title content}} : {}", query);

        let mut where_clauses = Vec::new();
        let mut param_values: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();
        let mut param_idx = 2;

        if let Some(folder_id) = &filter.folder_id {
            where_clauses.push(format!("c.folder_id = ?{}", param_idx));
            param_values.push(Box::new(folder_id.to_string()));
            param_idx += 1;
        }

        for tag in &filter.tags {
            where_clauses.push(format!("c.tags LIKE ?{}", param_idx));
            param_values.push(Box::new(format!("%{}%", tag)));
            param_idx += 1;
        }

        if let Some(date_range) = &filter.date_range {
            where_clauses.push(format!("c.updated_at >= ?{}", param_idx));
            param_values.push(Box::new(date_range.start.to_rfc3339()));
            param_idx += 1;
            where_clauses.push(format!("c.updated_at <= ?{}", param_idx));
            param_values.push(Box::new(date_range.end.to_rfc3339()));
            param_idx += 1;
        }

        let where_sql = if where_clauses.is_empty() {
            String::new()
        } else {
            format!("AND {}", where_clauses.join(" AND "))
        };

        let sql = format!(
            "SELECT c.note_id, c.title, snippet(notes_fts, 1, '\\x01', '\\x02', '...', 32) as snippet, rank as score \
             FROM notes_fts f \
             JOIN notes_search_content c ON f.rowid = c.rowid \
             WHERE notes_fts MATCH ?1 {} \
             ORDER BY rank \
             LIMIT ?{} OFFSET ?{}",
            where_sql, param_idx, param_idx + 1
        );

        let mut stmt = conn.prepare(&sql)?;

        let mut params_vec: Vec<Box<dyn rusqlite::types::ToSql>> = vec![
            Box::new(fts_query),
        ];
        params_vec.extend(param_values);
        params_vec.push(Box::new(limit as i64));
        params_vec.push(Box::new(offset as i64));

        let params_refs: Vec<&dyn rusqlite::types::ToSql> = params_vec.iter().map(|p| p.as_ref()).collect();

        let results = stmt
            .query_map(params_refs.as_slice(), Self::row_to_search_result)?
            .collect::<Result<Vec<_>, _>>()?;

        info!(
            "search_with_filter query='{}' results={} limit={} offset={}",
            query,
            results.len(),
            limit,
            offset
        );

        Ok(results)
    }

    fn rebuild_index(&mut self) -> anyhow::Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute_batch("INSERT INTO notes_fts(notes_fts) VALUES ('rebuild');")?;
        Ok(())
    }
}

impl SqliteSearchEngine {
    /// Search using a query string that may contain filter prefixes like `tag:"work project"`.
    /// The query is parsed with `parse_filter` to extract structured filters and free-text terms.
    pub fn search_parsed(&self, query: &str, limit: usize, offset: usize) -> anyhow::Result<Vec<SearchResult>> {
        let (filters, text) = parse_filter(query);

        let mut filter = SearchFilter {
            folder_id: None,
            tags: Vec::new(),
            date_range: None,
        };

        for (key, value) in &filters {
            match key.as_str() {
                "t" | "tag" => filter.tags.push(value.clone()),
                "f" | "folder" => {
                    if let Ok(uid) = Uuid::parse_str(value) {
                        filter.folder_id = Some(uid);
                    }
                }
                _ => {}
            }
        }

        self.search_with_filter(&text, &filter, limit, offset)
    }
}
