//! Tantivy 全文搜索引擎
//!
//! ## 借鉴的开源项目
//! - **Tantivy** ([https://github.com/quickwit-oss/tantivy](https://github.com/quickwit-oss/tantivy)): Rust 实现的全文搜索引擎
//! - **Lucene** ([https://lucene.apache.org/](https://lucene.apache.org/)): Tantivy 借鉴了 Lucene 的倒排索引设计
//!
//! ## 实现说明
//! Tantivy 提供比 SQLite FTS5 更高的检索性能，适合大规模笔记检索。
//! 与 tantivy 兼容的查询语法包括布尔查询、短语查询、通配符等。

use devnote_observe::info;
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};
use std::sync::{Arc, Mutex};
use std::path::Path;
use anyhow::{Context, Result};

use tantivy::schema::{
    IndexRecordOption, FAST, STORED, STRING, TEXT, Value, Schema, INDEXED,
};
use tantivy::{
    DocAddress, Index, IndexSettings, IndexWriter, ReloadPolicy, TantivyDocument,
    DateTime as TantivyDateTime,
};
use tantivy::directory::MmapDirectory;
use tantivy::collector::TopDocs;
use tantivy::query::{BooleanQuery, Occur, QueryParser, TermQuery};

/// Tantivy 搜索结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TantivySearchResult {
    pub note_id: String,
    pub title: String,
    pub content_snippet: String,
    pub score: f32,
}

/// Tantivy 搜索引擎配置
#[derive(Debug, Clone)]
pub struct TantivyConfig {
    /// 索引存储路径
    pub index_path: String,
    /// 索引 Writer 内存预算（字节），默认 50MB
    pub writer_memory_bytes: usize,
}

impl Default for TantivyConfig {
    fn default() -> Self {
        Self {
            index_path: String::from("./tantivy_index"),
            writer_memory_bytes: 50_000_000, // 50MB
        }
    }
}

/// Tantivy 全文搜索引擎
///
/// ## 借鉴的开源项目
/// - **Tantivy** ([官方仓库](https://github.com/quickwit-oss/tantivy)):
///   借鉴其 Schema 定义、IndexWriter 批量写入、QueryParser 查询解析机制
/// - **Lucene** ([官网](https://lucene.apache.org/)):
///   借鉴其倒排索引（Inverted Index）设计思想，Tantivy 本身就是受 Lucene 启发而构建
///
/// ## 架构说明
/// - Schema 定义了 note_id(STRING)、title(TEXT)、content(TEXT) 三个核心字段
/// - title 字段使用默认分词器，content 字段使用简易分词器
/// - 使用 Arc<Mutex<>> 包装 Index 和 IndexWriter 实现线程安全访问
pub struct TantivySearchEngine {
    index: Arc<Mutex<Index>>,
    schema: Schema,
    writer: Arc<Mutex<IndexWriter>>,
    config: TantivyConfig,
}

impl TantivySearchEngine {
    /// 创建新的 Tantivy 搜索引擎实例
    ///
    /// 如果索引目录不存在则创建，并初始化 Schema
    pub fn new(config: TantivyConfig) -> Result<Self> {
        let schema = Self::build_schema();
        let index = Self::open_or_create_index(&config.index_path, &schema)?;
        let writer = index
            .writer(config.writer_memory_bytes)
            .context("Failed to create index writer")?;

        let config_path = config.index_path.clone();
        let engine = Self {
            index: Arc::new(Mutex::new(index)),
            schema,
            writer: Arc::new(Mutex::new(writer)),
            config,
        };

        info!("TantivySearchEngine initialized at {}", config_path);
        Ok(engine)
    }

    /// 构建 Tantivy Schema
    ///
    /// 借鉴 Lucene 的字段设计：
    /// - note_id: STRING 类型，用于精确匹配
    /// - title: TEXT 类型，全文索引 + 存储原始值
    /// - content: TEXT 类型，全文索引 + 存储原始值
    /// - folder_id: STRING 类型，用于分类过滤
    /// - tags: 多值 STRING 类型，用于标签过滤
    /// - updated_at: FAST 类型，用于日期范围过滤
    fn build_schema() -> Schema {
        let mut builder = tantivy::schema::Schema::builder();

        // note_id: 字符串字段，精确匹配
        builder.add_text_field("note_id", STRING | STORED);
        // title: 文本字段，全文检索
        builder.add_text_field("title", TEXT | STORED);
        // content: 文本字段，全文检索
        builder.add_text_field("content", TEXT | STORED);
        // folder_id: 字符串字段，分类过滤
        builder.add_text_field("folder_id", STRING | STORED);
        // tags: 多值字符串字段
        builder.add_text_field("tags", STRING | STORED);
        // updated_at: 快速字段，范围过滤
        builder.add_date_field(
            "updated_at",
            tantivy::schema::DateOptions::from(INDEXED)
                .set_stored()
                .set_fast(),
        );

        builder.build()
    }

    /// 打开已有索引或创建新索引
    fn open_or_create_index(index_path: &str, schema: &Schema) -> Result<Index> {
        let path = Path::new(index_path);

        // 确保目录存在
        if !path.exists() {
            std::fs::create_dir_all(path).context("Failed to create index directory")?;
        }

        let dir = MmapDirectory::open(path).context("Failed to open mmap directory")?;

        // 尝试打开已有索引，失败则创建新索引
        match Index::open(dir.clone()) {
            Ok(index) => {
                info!("Opened existing tantivy index at {}", index_path);
                Ok(index)
            }
            Err(_) => {
                let index = Index::create(dir, schema.clone(), IndexSettings::default())
                    .context("Failed to create tantivy index")?;
                info!("Created new tantivy index at {}", index_path);
                Ok(index)
            }
        }
    }

    /// 索引笔记（借鉴 Tantivy 的文档写入机制）
    pub fn index_note(
        &self,
        note_id: &Uuid,
        title: &str,
        content: &str,
        folder_id: &Uuid,
        tags: &[String],
        updated_at: &DateTime<Utc>,
    ) -> Result<()> {
        let mut writer = self.writer.lock().unwrap();

        let note_id_field = self.schema.get_field("note_id").unwrap();
        let title_field = self.schema.get_field("title").unwrap();
        let content_field = self.schema.get_field("content").unwrap();
        let folder_id_field = self.schema.get_field("folder_id").unwrap();
        let tags_field = self.schema.get_field("tags").unwrap();
        let updated_at_field = self.schema.get_field("updated_at").unwrap();

        // 先删除旧文档（如果存在）
        let delete_term = tantivy::Term::from_field_text(
            note_id_field,
            &note_id.to_string(),
        );
        writer.delete_term(delete_term);

        // 添加新文档（借鉴 Tantivy 的 TantivyDocument 机制）
        let mut doc = TantivyDocument::default();
        doc.add_text(note_id_field, note_id.to_string());
        doc.add_text(title_field, title);
        doc.add_text(content_field, content);
        doc.add_text(folder_id_field, folder_id.to_string());
        for tag in tags {
            doc.add_text(tags_field, tag.as_str());
        }
        doc.add_date(updated_at_field, TantivyDateTime::from_timestamp_secs(updated_at.timestamp()));

        writer.add_document(doc)?;
        writer.commit()?;

        info!("Indexed note {} with title '{}'", note_id, title);
        Ok(())
    }

    /// 索引笔记（简单版本，不包含元数据）
    pub fn index_note_simple(&self, note_id: &Uuid, title: &str, content: &str) -> Result<()> {
        let now = Utc::now();
        let folder_id = Uuid::nil();
        self.index_note(note_id, title, content, &folder_id, &[], &now)
    }

    /// 删除笔记索引
    pub fn remove_note(&self, note_id: &Uuid) -> Result<()> {
        let mut writer = self.writer.lock().unwrap();

        let note_id_field = self.schema.get_field("note_id").unwrap();
        let delete_term = tantivy::Term::from_field_text(
            note_id_field,
            &note_id.to_string(),
        );
        writer.delete_term(delete_term);
        writer.commit()?;

        info!("Removed note {} from index", note_id);
        Ok(())
    }

    /// 执行全文搜索
    ///
    /// 借鉴 Tantivy 的 QueryParser 机制：
    /// - 支持多字段搜索：title 和 content 同时进行
    /// - 支持布尔查询：+term1 term2（必须包含 term1，可选包含 term2）
    /// - 支持短语查询："exact phrase"
    /// - 支持通配符：term*
    pub fn search(&self, query: &str, limit: usize) -> Result<Vec<TantivySearchResult>> {
        if query.trim().is_empty() {
            return Ok(Vec::new());
        }

        let index = self.index.lock().unwrap();
        let reader = index
            .reader_builder()
            .reload_policy(ReloadPolicy::Manual)
            .try_into()?;
        let searcher = reader.searcher();

        let title_field = self.schema.get_field("title").unwrap();
        let content_field = self.schema.get_field("content").unwrap();

        // 使用 QueryParser 解析查询（借鉴 Tantivy 的默认解析器）
        let query_parser = QueryParser::for_index(
            &index,
            vec![title_field, content_field],
        );
        let parsed_query = query_parser.parse_query(query)?;

        // 使用 TopDocs 获取最高分的前 N 个结果（借鉴 Lucene 的 TopDocsCollector）
        let top_docs = TopDocs::with_limit(limit);
        let results = searcher.search(&parsed_query, &top_docs)?;

        let note_id_field = self.schema.get_field("note_id").unwrap();
        let title_field = self.schema.get_field("title").unwrap();
        let content_field = self.schema.get_field("content").unwrap();

        let mut search_results = Vec::new();
        for (_score, doc_address) in results {
            let doc: TantivyDocument = searcher.doc(doc_address)?;

            let note_id = doc
                .get_first(note_id_field)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            let title = doc
                .get_first(title_field)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            // 生成内容摘要（取前 200 字符）
            let content = doc
                .get_first(content_field)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let snippet = if content.len() > 200 {
                format!("{}...", &content[..200])
            } else {
                content
            };

            search_results.push(TantivySearchResult {
                note_id,
                title,
                content_snippet: snippet,
                score: _score,
            });
        }

        info!("Tantivy search for '{}' returned {} results", query, search_results.len());
        Ok(search_results)
    }

    /// 带过滤条件的搜索
    ///
    /// 借鉴 Tantivy 的 BooleanQuery 机制：
    /// 将全文查询与过滤条件组合为 MUST 和 FILTER 子句
    pub fn search_with_filter(
        &self,
        query: &str,
        folder_id: Option<&Uuid>,
        tags: &[String],
        limit: usize,
    ) -> Result<Vec<TantivySearchResult>> {
        if query.trim().is_empty() && folder_id.is_none() && tags.is_empty() {
            return Ok(Vec::new());
        }

        let index = self.index.lock().unwrap();
        let reader = index
            .reader_builder()
            .reload_policy(ReloadPolicy::Manual)
            .try_into()?;
        let searcher = reader.searcher();

        let mut subqueries: Vec<(Occur, Box<dyn tantivy::query::Query>)> = Vec::new();

        // 全文查询子句
        if !query.trim().is_empty() {
            let title_field = self.schema.get_field("title").unwrap();
            let content_field = self.schema.get_field("content").unwrap();
            let query_parser = QueryParser::for_index(
                &index,
                vec![title_field, content_field],
            );
            let parsed_query = query_parser.parse_query(query)?;
            subqueries.push((Occur::Must, parsed_query));
        }

        // 文件夹过滤（借鉴 Tantivy 的 TermQuery 精确匹配）
        if let Some(fid) = folder_id {
            let folder_id_field = self.schema.get_field("folder_id").unwrap();
            let term_query = TermQuery::new(
                tantivy::Term::from_field_text(folder_id_field, &fid.to_string()),
                IndexRecordOption::Basic,
            );
            subqueries.push((Occur::Must, Box::new(term_query)));
        }

        // 标签过滤
        for tag in tags {
            let tags_field = self.schema.get_field("tags").unwrap();
            let term_query = TermQuery::new(
                tantivy::Term::from_field_text(tags_field, tag),
                IndexRecordOption::Basic,
            );
            subqueries.push((Occur::Must, Box::new(term_query)));
        }

        let boolean_query = BooleanQuery::new(subqueries);
        let top_docs = TopDocs::with_limit(limit);
        let results = searcher.search(&boolean_query, &top_docs)?;

        let note_id_field = self.schema.get_field("note_id").unwrap();
        let title_field = self.schema.get_field("title").unwrap();
        let content_field = self.schema.get_field("content").unwrap();

        let mut search_results = Vec::new();
        for (_score, doc_address) in results {
            let doc: TantivyDocument = searcher.doc(doc_address)?;

            let note_id = doc
                .get_first(note_id_field)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            let title = doc
                .get_first(title_field)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            let content = doc
                .get_first(content_field)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let snippet = if content.len() > 200 {
                format!("{}...", &content[..200])
            } else {
                content
            };

            search_results.push(TantivySearchResult {
                note_id,
                title,
                content_snippet: snippet,
                score: _score,
            });
        }

        Ok(search_results)
    }

    /// 重建索引
    ///
    /// 删除现有索引并重新创建（借鉴 Tantivy 的索引重建机制）
    pub fn rebuild_index(&self) -> Result<()> {
        // 清空索引目录
        let path = Path::new(&self.config.index_path);
        if path.exists() {
            std::fs::remove_dir_all(path).context("Failed to remove old index")?;
        }
        std::fs::create_dir_all(path).context("Failed to recreate index directory")?;

        let new_index = Self::open_or_create_index(&self.config.index_path, &self.schema)?;
        let new_writer = new_index
            .writer(self.config.writer_memory_bytes)
            .context("Failed to create new index writer")?;

        // 替换现有的 index 和 writer
        {
            let mut index_guard = self.index.lock().unwrap();
            *index_guard = new_index;
        }
        {
            let mut writer_guard = self.writer.lock().unwrap();
            *writer_guard = new_writer;
        }

        info!("Rebuilt tantivy index at {}", self.config.index_path);
        Ok(())
    }

    /// 获取索引中的文档数量
    pub fn num_docs(&self) -> Result<u64> {
        let index = self.index.lock().unwrap();
        let reader = index
            .reader_builder()
            .reload_policy(ReloadPolicy::Manual)
            .try_into()?;
        let searcher = reader.searcher();
        Ok(searcher.num_docs())
    }
}
