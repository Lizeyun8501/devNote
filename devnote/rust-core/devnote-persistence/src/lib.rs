//! 本地持久化层 —— 基于 SQLite (rusqlite) 的结构化数据存储
//! 借鉴思源笔记的 SQLite 表结构设计和 Joplin 的文件系统存储模式
//!
//! 借鉴思源笔记的 SQLite 表结构设计
//! 来源: https://github.com/siyuan-note/siyuan
//! 借鉴内容: notes/folders/tags/blocks 核心表结构、WAL 模式、渐进式 Schema 迁移方案
//!
//! 借鉴 Joplin 的文件系统存储模式
//! 来源: https://github.com/laurent22/joplin
//! 借鉴内容: 附件文件加密存储、SHA-256 完整性校验、EncryptedFileStorage 文件加密层

use devnote_core::models::{Attachment, Folder, Note, Tag, Permission, ResourceACL, Workspace, WorkspaceMember};
use devnote_core::{Block, BlockType};
use devnote_observe::{instrument, warn};
use devnote_core::traits::NoteRepository;
use devnote_crypto::{CryptoEngine, DefaultCryptoEngine, CryptoConfig};
use serde::{Serialize, Deserialize};
use std::sync::Mutex;
use thiserror::Error;
use uuid::Uuid;
use anyhow::Result;
use chrono::Utc;
use rusqlite::params;
use sha2::{Sha256, Digest};
use std::path::PathBuf;
use std::fs;
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};

#[derive(Debug, Error)]
pub enum PersistenceError {
    #[error("database error: {0}")]
    DatabaseError(String),
    #[error("not found: {0}")]
    NotFound(String),
    #[error("constraint violation: {0}")]
    ConstraintViolation(String),
    #[error("serialization error: {0}")]
    SerializationError(String),
    #[error("deserialization error: {0}")]
    DeserializationError(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEntry {
    pub id: String,
    pub user_id: String,
    pub action: String,
    pub resource_type: String,
    pub resource_id: String,
    pub timestamp: i64,
    pub metadata: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeatureFlag {
    pub key: String,
    pub enabled: bool,
    pub description: String,
    pub updated_at: i64,
}

const _DB_VERSION: i32 = 5;

const SCHEMA_V1: &str = r#"
CREATE TABLE IF NOT EXISTS notes (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL DEFAULT '',
    folder_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS folders (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tags (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS note_tags (
    note_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    PRIMARY KEY (note_id, tag_id),
    FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS attachments (
    id TEXT PRIMARY KEY,
    note_id TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    mime_type TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS blocks (
    id TEXT PRIMARY KEY,
    note_id TEXT NOT NULL,
    block_type TEXT NOT NULL,
    content TEXT NOT NULL DEFAULT '',
    position INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS ipfs_metadata (
    id TEXT PRIMARY KEY,
    note_id TEXT NOT NULL,
    attachment_id TEXT,
    cid TEXT NOT NULL,
    content_type TEXT NOT NULL DEFAULT '',
    size_bytes INTEGER NOT NULL DEFAULT 0,
    pinned INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE,
    FOREIGN KEY (attachment_id) REFERENCES attachments(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY
);
"#;

const SCHEMA_V2: &str = r#"
CREATE TABLE IF NOT EXISTS resource_acls (
    id TEXT PRIMARY KEY,
    resource_id TEXT NOT NULL,
    resource_type TEXT NOT NULL,
    user_id TEXT NOT NULL,
    permission TEXT NOT NULL,
    granted_by TEXT NOT NULL,
    granted_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_resource_acls_resource ON resource_acls(resource_id, resource_type);
CREATE INDEX IF NOT EXISTS idx_resource_acls_user ON resource_acls(user_id);

CREATE TABLE IF NOT EXISTS workspaces (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    owner_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_workspaces_owner ON workspaces(owner_id);

CREATE TABLE IF NOT EXISTS workspace_members (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    role TEXT NOT NULL,
    joined_at TEXT NOT NULL,
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_workspace_members_workspace ON workspace_members(workspace_id);
CREATE INDEX IF NOT EXISTS idx_workspace_members_user ON workspace_members(user_id);
"#;

const SCHEMA_V3: &str = r#"
CREATE TABLE IF NOT EXISTS audit_log (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    action TEXT NOT NULL,
    resource_type TEXT NOT NULL,
    resource_id TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    metadata TEXT
);

CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_resource ON audit_log(resource_type, resource_id);
CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_log(timestamp);
"#;

const SCHEMA_V4: &str = r#"
CREATE TABLE IF NOT EXISTS feature_flags (
    key TEXT PRIMARY KEY,
    enabled INTEGER NOT NULL DEFAULT 0,
    description TEXT NOT NULL DEFAULT '',
    updated_at INTEGER NOT NULL
);
"#;

// P1 修复 (P1-6): 跨端数据模型对齐
// 为 notes 添加 is_pinned/is_encrypted 列（与 Rust Note 模型对齐）
// 为 folders 添加 sort_order 列（与 Rust Folder 模型对齐）
// 为 tags 添加 color 列（与 Rust Tag 模型对齐）
// 注意: notes.blocks/tags 不添加列，因为它们由 blocks/note_tags 关联表管理
const SCHEMA_V5: &str = r#"
ALTER TABLE notes ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;
ALTER TABLE notes ADD COLUMN is_encrypted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE folders ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0;
ALTER TABLE tags ADD COLUMN color TEXT;
"#;

pub struct SqliteNoteRepository {
    conn: Mutex<rusqlite::Connection>,
}

impl std::fmt::Debug for SqliteNoteRepository {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SqliteNoteRepository").finish()
    }
}

impl SqliteNoteRepository {
    pub fn init(db_path: &str) -> Result<Self> {
        let conn = rusqlite::Connection::open(db_path)?;
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")?;
        let repo = Self {
            conn: Mutex::new(conn),
        };
        repo.run_migrations()?;
        Ok(repo)
    }

    pub fn new(conn: rusqlite::Connection) -> Result<Self> {
        let repo = Self {
            conn: Mutex::new(conn),
        };
        repo.run_migrations()?;
        Ok(repo)
    }

    pub fn in_memory() -> Result<Self> {
        let conn = rusqlite::Connection::open_in_memory()?;
        conn.execute_batch("PRAGMA foreign_keys=ON;")?;
        let repo = Self {
            conn: Mutex::new(conn),
        };
        repo.run_migrations()?;
        Ok(repo)
    }

    fn run_migrations(&self) -> Result<()> {
        let mut conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let current_version: i32 = conn
            .query_row(
                "SELECT version FROM schema_version ORDER BY version DESC LIMIT 1",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        // P1 修复 (P1-7): 每个迁移版本块用事务包裹，确保 schema 变更与版本记录原子提交。
        // 若 execute_batch 成功但版本记录失败（或反之），事务回滚避免数据库处于
        // 部分迁移的不一致状态。特别是 V5 的 ALTER TABLE ADD COLUMN 非幂等，
        // 重复执行会报 "duplicate column name"，事务保护可避免此问题。
        let migrations: [(i32, &str); 5] = [
            (1, SCHEMA_V1),
            (2, SCHEMA_V2),
            (3, SCHEMA_V3),
            (4, SCHEMA_V4),
            (5, SCHEMA_V5),
        ];

        for (version, schema_sql) in &migrations {
            if current_version < *version {
                let tx = conn.transaction()?;
                tx.execute_batch(schema_sql)?;
                tx.execute(
                    "INSERT OR REPLACE INTO schema_version (version) VALUES (?1)",
                    params![*version],
                )?;
                tx.commit()?;
            }
        }

        Ok(())
    }

    fn row_to_note(row: &rusqlite::Row) -> rusqlite::Result<Note> {
        let id_str: String = row.get(0)?;
        let title: String = row.get(1)?;
        let content: String = row.get(2)?;
        let folder_id_str: String = row.get(3)?;
        let created_at_str: String = row.get(4)?;
        let updated_at_str: String = row.get(5)?;
        // P1 修复 (P1-6): 读取 is_pinned/is_encrypted 列
        let is_pinned: bool = row.get::<_, i64>(6).map(|v| v != 0).unwrap_or(false);
        let is_encrypted: bool = row.get::<_, i64>(7).map(|v| v != 0).unwrap_or(false);

        let blocks = match serde_json::from_str::<Vec<Block>>(&content) {
            Ok(blocks) => blocks,
            Err(_) => {
                // 兼容旧数据/纯文本 content：当 content 不是合法的 JSON blocks 数组时
                // （例如 Dart 端 NoteModel 写入的纯文本），将其包装为单个 paragraph block，
                // 避免 unwrap_or_default() 静默丢弃笔记内容。
                let note_id = Uuid::parse_str(&id_str)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?;
                vec![Block {
                    id: Uuid::new_v4(),
                    note_id,
                    block_type: BlockType::Paragraph,
                    content: content.clone(),
                    position: 0,
                    children: Vec::new(),
                    created_at: Utc::now(),
                    updated_at: Utc::now(),
                }]
            }
        };

        Ok(Note {
            id: Uuid::parse_str(&id_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            title,
            content: content.clone(),
            folder_id: Uuid::parse_str(&folder_id_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            blocks,
            tags: Vec::new(),
            is_pinned,
            is_encrypted,
            created_at: chrono::DateTime::parse_from_rfc3339(&created_at_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?
                .to_utc(),
            updated_at: chrono::DateTime::parse_from_rfc3339(&updated_at_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?
                .to_utc(),
        })
    }

    fn row_to_folder(row: &rusqlite::Row) -> rusqlite::Result<Folder> {
        let id_str: String = row.get(0)?;
        let name: String = row.get(1)?;
        let parent_id_str: Option<String> = row.get(2)?;
        let created_at_str: String = row.get(3)?;
        let updated_at_str: String = row.get(4)?;
        // P1 修复 (P1-6): 读取 sort_order 列
        let sort_order: i32 = row.get::<_, i64>(5).map(|v| v as i32).unwrap_or(0);

        Ok(Folder {
            id: Uuid::parse_str(&id_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            name,
            parent_id: parent_id_str
                .map(|p| Uuid::parse_str(&p))
                .transpose()
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            sort_order,
            created_at: chrono::DateTime::parse_from_rfc3339(&created_at_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?
                .to_utc(),
            updated_at: chrono::DateTime::parse_from_rfc3339(&updated_at_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?
                .to_utc(),
        })
    }

    fn row_to_tag(row: &rusqlite::Row) -> rusqlite::Result<Tag> {
        let id_str: String = row.get(0)?;
        let name: String = row.get(1)?;
        let created_at_str: String = row.get(2)?;
        // P1 修复 (P1-6): 读取 color 列（可能不存在于旧数据，用 unwrap_or 兜底）
        let color: Option<String> = row.get(3).unwrap_or(None);

        Ok(Tag {
            id: Uuid::parse_str(&id_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            name,
            color,
            created_at: chrono::DateTime::parse_from_rfc3339(&created_at_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?
                .to_utc(),
        })
    }

    fn row_to_attachment(row: &rusqlite::Row) -> rusqlite::Result<Attachment> {
        let id_str: String = row.get(0)?;
        let note_id_str: String = row.get(1)?;
        let filename: String = row.get(2)?;
        let storage_path: String = row.get(3)?;
        let size_bytes: i64 = row.get(4)?;
        let mime_type: String = row.get(5)?;
        let created_at_str: String = row.get(6)?;

        Ok(Attachment {
            id: Uuid::parse_str(&id_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            note_id: Uuid::parse_str(&note_id_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            filename,
            mime_type,
            size_bytes: size_bytes as u64,
            storage_path,
            created_at: chrono::DateTime::parse_from_rfc3339(&created_at_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?
                .to_utc(),
        })
    }

    fn fetch_note_by_id(&self, id: &Uuid) -> Result<Option<Note>> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id_str = id.to_string();
        let mut stmt = conn.prepare(
            // P1 修复 (P1-6): 读取 is_pinned/is_encrypted 列
            "SELECT id, title, content, folder_id, created_at, updated_at, is_pinned, is_encrypted FROM notes WHERE id = ?1",
        )?;

        let result = stmt.query_row(params![id_str], Self::row_to_note);

        match result {
            Ok(mut note) => {
                let tags = Self::fetch_tags_for_note_internal(&conn, id)?;
                note.tags = tags;
                Ok(Some(note))
            }
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    fn fetch_tags_for_note_internal(conn: &rusqlite::Connection, note_id: &Uuid) -> Result<Vec<Uuid>> {
        let note_id_str = note_id.to_string();
        let mut stmt = conn.prepare("SELECT tag_id FROM note_tags WHERE note_id = ?1")?;
        let tags: Vec<Uuid> = stmt
            .query_map(params![note_id_str], |row| {
                let tag_id_str: String = row.get(0)?;
                Uuid::parse_str(&tag_id_str)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(tags)
    }

    fn fetch_notes_by_folder(&self, folder_id: Option<&Uuid>) -> Result<Vec<Note>> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let notes = match folder_id {
            Some(fid) => {
                let fid_str = fid.to_string();
                let mut stmt = conn.prepare(
                    // P1 修复 (P1-6): 读取 is_pinned/is_encrypted 列
                    "SELECT id, title, content, folder_id, created_at, updated_at, is_pinned, is_encrypted FROM notes WHERE folder_id = ?1 ORDER BY updated_at DESC",
                )?;
                let result = stmt.query_map(params![fid_str], Self::row_to_note)?
                    .collect::<Result<Vec<_>, _>>()?;
                result
            }
            None => {
                let mut stmt = conn.prepare(
                    // P1 修复 (P1-6): 读取 is_pinned/is_encrypted 列
                    "SELECT id, title, content, folder_id, created_at, updated_at, is_pinned, is_encrypted FROM notes ORDER BY updated_at DESC",
                )?;
                let result = stmt.query_map([], Self::row_to_note)?
                    .collect::<Result<Vec<_>, _>>()?;
                result
            }
        };
        Ok(notes)
    }

    fn fetch_folders_by_parent(&self, parent_id: Option<&Uuid>) -> Result<Vec<Folder>> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let folders = match parent_id {
            Some(pid) => {
                let pid_str = pid.to_string();
                let mut stmt = conn.prepare(
                    // P1 修复 (P1-6): 读取 sort_order 列，按 sort_order, name 排序
                    "SELECT id, name, parent_id, created_at, updated_at, sort_order FROM folders WHERE parent_id = ?1 ORDER BY sort_order, name",
                )?;
                let result = stmt.query_map(params![pid_str], Self::row_to_folder)?
                    .collect::<Result<Vec<_>, _>>()?;
                result
            }
            None => {
                let mut stmt = conn.prepare(
                    // P1 修复 (P1-6): 读取 sort_order 列，按 sort_order, name 排序
                    "SELECT id, name, parent_id, created_at, updated_at, sort_order FROM folders WHERE parent_id IS NULL ORDER BY sort_order, name",
                )?;
                let result = stmt.query_map([], Self::row_to_folder)?
                    .collect::<Result<Vec<_>, _>>()?;
                result
            }
        };
        Ok(folders)
    }

    fn remove_note_by_id(&self, id: &Uuid) -> Result<()> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id_str = id.to_string();
        conn.execute("DELETE FROM notes WHERE id = ?1", params![id_str])?;
        Ok(())
    }

    fn link_tag_to_note(&self, note_id: &Uuid, tag_id: &Uuid) -> Result<()> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let note_id_str = note_id.to_string();
        let tag_id_str = tag_id.to_string();
        conn.execute(
            "INSERT INTO note_tags (note_id, tag_id) VALUES (?1, ?2)",
            params![note_id_str, tag_id_str],
        )?;
        Ok(())
    }

    fn unlink_tag_from_note(&self, note_id: &Uuid, tag_id: &Uuid) -> Result<()> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let note_id_str = note_id.to_string();
        let tag_id_str = tag_id.to_string();
        conn.execute(
            "DELETE FROM note_tags WHERE note_id = ?1 AND tag_id = ?2",
            params![note_id_str, tag_id_str],
        )?;
        Ok(())
    }

    #[instrument]
    pub fn create_note(&self, title: &str, content: &str, folder_id: &Uuid) -> Result<Note> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id = Uuid::new_v4();
        let now = Utc::now();
        let id_str = id.to_string();
        let folder_id_str = folder_id.to_string();
        let now_str = now.to_rfc3339();

        conn.execute(
            // P1 修复 (P1-6): 写入 is_pinned/is_encrypted 列（新建笔记默认 false）
            "INSERT INTO notes (id, title, content, folder_id, is_pinned, is_encrypted, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, 0, 0, ?5, ?6)",
            params![id_str, title, content, folder_id_str, now_str, now_str],
        )?;

        Ok(Note {
            id,
            title: title.to_string(),
            content: content.to_string(),
            folder_id: *folder_id,
            blocks: Vec::new(),
            tags: Vec::new(),
            is_pinned: false,
            is_encrypted: false,
            created_at: now,
            updated_at: now,
        })
    }

    pub fn get_note(&self, id: &Uuid) -> Result<Option<Note>> {
        self.fetch_note_by_id(id)
    }

    #[instrument]
    pub fn update_note(&self, id: &Uuid, title: &str, content: &str) -> Result<Note> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id_str = id.to_string();
        let now = Utc::now();
        let now_str = now.to_rfc3339();

        conn.execute(
            "UPDATE notes SET title = ?1, content = ?2, updated_at = ?3 WHERE id = ?4",
            params![title, content, now_str, id_str],
        )?;

        drop(conn);
        self.fetch_note_by_id(id)?
            .ok_or_else(|| PersistenceError::NotFound(id_str).into())
    }

    #[instrument]
    pub fn delete_note(&self, id: &Uuid) -> Result<()> {
        self.remove_note_by_id(id)
    }

    pub fn list_notes(&self, folder_id: &Uuid) -> Result<Vec<Note>> {
        self.fetch_notes_by_folder(Some(folder_id))
    }

    #[instrument]
    pub fn create_folder(&self, name: &str, parent_id: Option<&Uuid>) -> Result<Folder> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id = Uuid::new_v4();
        let now = Utc::now();
        let id_str = id.to_string();
        let parent_id_str = parent_id.map(|p| p.to_string());
        let now_str = now.to_rfc3339();

        conn.execute(
            // P1 修复 (P1-6): 写入 sort_order 列（新建文件夹默认 0）
            "INSERT INTO folders (id, name, parent_id, sort_order, created_at, updated_at) VALUES (?1, ?2, ?3, 0, ?4, ?5)",
            params![id_str, name, parent_id_str, now_str, now_str],
        )?;

        Ok(Folder {
            id,
            name: name.to_string(),
            parent_id: parent_id.copied(),
            sort_order: 0,
            created_at: now,
            updated_at: now,
        })
    }

    pub fn list_folders(&self, parent_id: Option<&Uuid>) -> Result<Vec<Folder>> {
        self.fetch_folders_by_parent(parent_id)
    }

    #[instrument]
    pub fn create_tag(&self, name: &str) -> Result<Tag> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id = Uuid::new_v4();
        let now = Utc::now();
        let id_str = id.to_string();
        let now_str = now.to_rfc3339();

        conn.execute(
            // P1 修复 (P1-6): 写入 color 列（新建标签默认 NULL）
            "INSERT INTO tags (id, name, color, created_at) VALUES (?1, ?2, NULL, ?3)",
            params![id_str, name, now_str],
        )?;

        Ok(Tag {
            id,
            name: name.to_string(),
            color: None,
            created_at: now,
        })
    }

    pub fn add_tag_to_note(&self, note_id: &Uuid, tag_id: &Uuid) -> Result<()> {
        self.link_tag_to_note(note_id, tag_id)
    }

    // ---- Audit Log CRUD ----

    pub fn log_audit(&self, entry: AuditEntry) -> Result<(), PersistenceError> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        conn.execute(
            "INSERT INTO audit_log (id, user_id, action, resource_type, resource_id, timestamp, metadata) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![entry.id, entry.user_id, entry.action, entry.resource_type, entry.resource_id, entry.timestamp, entry.metadata],
        ).map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        Ok(())
    }

    pub fn get_audit_log(&self, user_id: &str, limit: usize, offset: usize) -> Result<Vec<AuditEntry>, PersistenceError> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let mut stmt = conn.prepare(
            "SELECT id, user_id, action, resource_type, resource_id, timestamp, metadata FROM audit_log WHERE user_id = ?1 ORDER BY timestamp DESC LIMIT ?2 OFFSET ?3",
        ).map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let entries = stmt.query_map(params![user_id, limit as i64, offset as i64], |row| {
            Ok(AuditEntry {
                id: row.get(0)?,
                user_id: row.get(1)?,
                action: row.get(2)?,
                resource_type: row.get(3)?,
                resource_id: row.get(4)?,
                timestamp: row.get(5)?,
                metadata: row.get(6)?,
            })
        }).map_err(|e| PersistenceError::DatabaseError(e.to_string()))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        Ok(entries)
    }

    pub fn get_resource_audit(&self, resource_type: &str, resource_id: &str) -> Result<Vec<AuditEntry>, PersistenceError> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let mut stmt = conn.prepare(
            "SELECT id, user_id, action, resource_type, resource_id, timestamp, metadata FROM audit_log WHERE resource_type = ?1 AND resource_id = ?2 ORDER BY timestamp DESC",
        ).map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let entries = stmt.query_map(params![resource_type, resource_id], |row| {
            Ok(AuditEntry {
                id: row.get(0)?,
                user_id: row.get(1)?,
                action: row.get(2)?,
                resource_type: row.get(3)?,
                resource_id: row.get(4)?,
                timestamp: row.get(5)?,
                metadata: row.get(6)?,
            })
        }).map_err(|e| PersistenceError::DatabaseError(e.to_string()))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        Ok(entries)
    }

    pub fn purge_audit_log(&self, before_timestamp: i64) -> Result<usize, PersistenceError> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let count = conn.execute(
            "DELETE FROM audit_log WHERE timestamp < ?1",
            params![before_timestamp],
        ).map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        Ok(count)
    }

    // ---- Feature Flag CRUD ----

    pub fn set_feature_flag(&self, flag: FeatureFlag) -> Result<(), PersistenceError> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let enabled_int = if flag.enabled { 1 } else { 0 };
        conn.execute(
            "INSERT OR REPLACE INTO feature_flags (key, enabled, description, updated_at) VALUES (?1, ?2, ?3, ?4)",
            params![flag.key, enabled_int, flag.description, flag.updated_at],
        ).map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        Ok(())
    }

    pub fn get_feature_flag(&self, key: &str) -> Result<Option<FeatureFlag>, PersistenceError> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let mut stmt = conn.prepare(
            "SELECT key, enabled, description, updated_at FROM feature_flags WHERE key = ?1",
        ).map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let result = stmt.query_row(params![key], |row| {
            let enabled_int: i32 = row.get(1)?;
            Ok(FeatureFlag {
                key: row.get(0)?,
                enabled: enabled_int != 0,
                description: row.get(2)?,
                updated_at: row.get(3)?,
            })
        });
        match result {
            Ok(flag) => Ok(Some(flag)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(PersistenceError::DatabaseError(e.to_string())),
        }
    }

    pub fn list_feature_flags(&self) -> Result<Vec<FeatureFlag>, PersistenceError> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let mut stmt = conn.prepare(
            "SELECT key, enabled, description, updated_at FROM feature_flags ORDER BY key",
        ).map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let flags = stmt.query_map([], |row| {
            let enabled_int: i32 = row.get(1)?;
            Ok(FeatureFlag {
                key: row.get(0)?,
                enabled: enabled_int != 0,
                description: row.get(2)?,
                updated_at: row.get(3)?,
            })
        }).map_err(|e| PersistenceError::DatabaseError(e.to_string()))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        Ok(flags)
    }

    pub fn is_feature_enabled(&self, key: &str) -> bool {
        self.get_feature_flag(key)
            .ok()
            .flatten()
            .map(|f| f.enabled)
            .unwrap_or(false)
    }

    pub fn delete_feature_flag(&self, key: &str) -> Result<(), PersistenceError> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        conn.execute(
            "DELETE FROM feature_flags WHERE key = ?1",
            params![key],
        ).map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        Ok(())
    }
}

impl NoteRepository for SqliteNoteRepository {
    fn create_note(&mut self, note: Note) -> Result<Note> {
        let mut conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id_str = note.id.to_string();
        let folder_id_str = note.folder_id.to_string();
        let content = serde_json::to_string(&note.blocks)?;
        let created_at_str = note.created_at.to_rfc3339();
        let updated_at_str = note.updated_at.to_rfc3339();
        // P1 修复 (P1-6): 写入 is_pinned/is_encrypted
        let is_pinned: i64 = if note.is_pinned { 1 } else { 0 };
        let is_encrypted: i64 = if note.is_encrypted { 1 } else { 0 };

        // P1 修复 (P1-7): INSERT notes + INSERT note_tags 包裹在事务中，
        // 确保笔记创建和标签关联原子完成，避免部分失败导致数据不一致
        let tx = conn.transaction()?;
        tx.execute(
            "INSERT INTO notes (id, title, content, folder_id, is_pinned, is_encrypted, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![id_str, note.title, content, folder_id_str, is_pinned, is_encrypted, created_at_str, updated_at_str],
        )?;

        for tag_id in &note.tags {
            let tag_id_str = tag_id.to_string();
            tx.execute(
                "INSERT OR IGNORE INTO note_tags (note_id, tag_id) VALUES (?1, ?2)",
                params![id_str, tag_id_str],
            )?;
        }
        tx.commit()?;

        Ok(note)
    }

    fn get_note(&self, id: &Uuid) -> Result<Option<Note>> {
        self.fetch_note_by_id(id)
    }

    fn update_note(&mut self, note: Note) -> Result<Note> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id_str = note.id.to_string();
        let content = serde_json::to_string(&note.blocks)?;
        let updated_at_str = note.updated_at.to_rfc3339();
        // P1 修复 (P1-6): 写入 is_pinned/is_encrypted
        let is_pinned: i64 = if note.is_pinned { 1 } else { 0 };
        let is_encrypted: i64 = if note.is_encrypted { 1 } else { 0 };

        conn.execute(
            "UPDATE notes SET title = ?1, content = ?2, is_pinned = ?3, is_encrypted = ?4, updated_at = ?5 WHERE id = ?6",
            params![note.title, content, is_pinned, is_encrypted, updated_at_str, id_str],
        )?;

        Ok(note)
    }

    fn delete_note(&mut self, id: &Uuid) -> Result<()> {
        self.remove_note_by_id(id)
    }

    fn list_notes(&self, folder_id: Option<&Uuid>) -> Result<Vec<Note>> {
        self.fetch_notes_by_folder(folder_id)
    }

    fn create_folder(&mut self, folder: Folder) -> Result<Folder> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id_str = folder.id.to_string();
        let parent_id_str = folder.parent_id.map(|p| p.to_string());
        let created_at_str = folder.created_at.to_rfc3339();
        let updated_at_str = folder.updated_at.to_rfc3339();
        // P1 修复 (P1-6): 写入 sort_order
        let sort_order: i64 = folder.sort_order as i64;

        conn.execute(
            "INSERT INTO folders (id, name, parent_id, sort_order, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![id_str, folder.name, parent_id_str, sort_order, created_at_str, updated_at_str],
        )?;

        Ok(folder)
    }

    fn get_folder(&self, id: &Uuid) -> Result<Option<Folder>> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id_str = id.to_string();
        let mut stmt = conn.prepare(
            // P1 修复 (P1-6): 读取 sort_order 列
            "SELECT id, name, parent_id, created_at, updated_at, sort_order FROM folders WHERE id = ?1",
        )?;

        let result = stmt.query_row(params![id_str], Self::row_to_folder);

        match result {
            Ok(folder) => Ok(Some(folder)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    fn update_folder(&mut self, folder: Folder) -> Result<Folder> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id_str = folder.id.to_string();
        let parent_id_str = folder.parent_id.map(|p| p.to_string());
        let updated_at_str = folder.updated_at.to_rfc3339();
        // P1 修复 (P1-6): 写入 sort_order
        let sort_order: i64 = folder.sort_order as i64;

        conn.execute(
            "UPDATE folders SET name = ?1, parent_id = ?2, sort_order = ?3, updated_at = ?4 WHERE id = ?5",
            params![folder.name, parent_id_str, sort_order, updated_at_str, id_str],
        )?;

        Ok(folder)
    }

    fn delete_folder(&mut self, id: &Uuid) -> Result<()> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id_str = id.to_string();
        conn.execute("DELETE FROM folders WHERE id = ?1", params![id_str])?;
        Ok(())
    }

    fn list_folders(&self, parent_id: Option<&Uuid>) -> Result<Vec<Folder>> {
        self.fetch_folders_by_parent(parent_id)
    }

    fn create_tag(&mut self, tag: Tag) -> Result<Tag> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id_str = tag.id.to_string();
        let created_at_str = tag.created_at.to_rfc3339();

        conn.execute(
            // P1 修复 (P1-6): 写入 color 列
            "INSERT INTO tags (id, name, color, created_at) VALUES (?1, ?2, ?3, ?4)",
            params![id_str, tag.name, tag.color, created_at_str],
        )?;

        Ok(tag)
    }

    fn delete_tag(&mut self, id: &Uuid) -> Result<()> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id_str = id.to_string();
        conn.execute("DELETE FROM tags WHERE id = ?1", params![id_str])?;
        Ok(())
    }

    fn list_tags(&self) -> Result<Vec<Tag>> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let mut stmt = conn.prepare(
            // P1 修复 (P1-6): 读取 color 列
            "SELECT id, name, created_at, color FROM tags ORDER BY name",
        )?;
        let tags = stmt
            .query_map([], Self::row_to_tag)?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(tags)
    }

    fn add_tag_to_note(&mut self, note_id: &Uuid, tag_id: &Uuid) -> Result<()> {
        self.link_tag_to_note(note_id, tag_id)
    }

    fn remove_tag_from_note(&mut self, note_id: &Uuid, tag_id: &Uuid) -> Result<()> {
        self.unlink_tag_from_note(note_id, tag_id)
    }

    fn create_attachment(&mut self, attachment: Attachment) -> Result<Attachment> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id_str = attachment.id.to_string();
        let note_id_str = attachment.note_id.to_string();
        let created_at_str = attachment.created_at.to_rfc3339();

        conn.execute(
            "INSERT INTO attachments (id, note_id, file_name, file_path, file_size, mime_type, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                id_str,
                note_id_str,
                attachment.filename,
                attachment.storage_path,
                attachment.size_bytes as i64,
                attachment.mime_type,
                created_at_str,
            ],
        )?;

        Ok(attachment)
    }

    fn delete_attachment(&mut self, id: &Uuid) -> Result<()> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id_str = id.to_string();
        conn.execute("DELETE FROM attachments WHERE id = ?1", params![id_str])?;
        Ok(())
    }

    fn list_attachments(&self, note_id: &Uuid) -> Result<Vec<Attachment>> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let note_id_str = note_id.to_string();
        let mut stmt = conn.prepare(
            "SELECT id, note_id, file_name, file_path, file_size, mime_type, created_at FROM attachments WHERE note_id = ?1 ORDER BY created_at",
        )?;
        let attachments = stmt
            .query_map(params![note_id_str], Self::row_to_attachment)?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(attachments)
    }
}

pub struct EncryptedNoteRepository {
    inner: Mutex<SqliteNoteRepository>,
    crypto: DefaultCryptoEngine,
    key: Mutex<Option<Vec<u8>>>,
    salt: Mutex<Option<Vec<u8>>>,
}

impl EncryptedNoteRepository {
    pub fn new(repo: SqliteNoteRepository, config: CryptoConfig) -> Self {
        Self {
            inner: Mutex::new(repo),
            crypto: DefaultCryptoEngine::new(config),
            key: Mutex::new(None),
            salt: Mutex::new(None),
        }
    }

    pub fn set_password(&self, password: &str) -> Result<()> {
        let salt = self.crypto.generate_salt();
        let key = self.crypto.derive_key(password, &salt)?;
        *self.key.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))? = Some(key);
        *self.salt.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))? = Some(salt);
        Ok(())
    }

    pub fn change_password(&self, old_password: &str, new_password: &str) -> Result<bool> {
        let salt_guard = self.salt.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        if let Some(ref salt) = *salt_guard {
            let old_key = self.crypto.derive_key(old_password, salt)?;
            let key_guard = self.key.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
            if let Some(ref current_key) = *key_guard {
                if old_key != *current_key {
                    return Ok(false);
                }
            }
            drop(key_guard);
        }
        drop(salt_guard);

        let new_salt = self.crypto.generate_salt();
        let new_key = self.crypto.derive_key(new_password, &new_salt)?;
        *self.key.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))? = Some(new_key);
        *self.salt.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))? = Some(new_salt);
        Ok(true)
    }

    pub fn clear_key(&self) {
        *self.key.lock().expect("mutex lock") = None;
        *self.salt.lock().expect("mutex lock") = None;
    }

    pub fn is_unlocked(&self) -> bool {
        self.key.lock().map_or(false, |k| k.is_some())
    }

    fn encrypt_content(&self, plaintext: &str) -> Result<String> {
        let key_guard = self.key.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let key = key_guard.as_ref().ok_or_else(|| PersistenceError::DatabaseError("encryption key not set".to_string()))?;
        let encrypted = self.crypto.encrypt(plaintext.as_bytes(), key)?;
        Ok(BASE64.encode(&encrypted))
    }

    fn decrypt_content(&self, ciphertext: &str) -> Result<String> {
        let key_guard = self.key.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let key = key_guard.as_ref().ok_or_else(|| PersistenceError::DatabaseError("encryption key not set".to_string()))?;
        let data = BASE64.decode(ciphertext).map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let decrypted = self.crypto.decrypt(&data, key)?;
        String::from_utf8(decrypted).map_err(|e| PersistenceError::SerializationError(e.to_string()).into())
    }
}

impl NoteRepository for EncryptedNoteRepository {
    fn create_note(&mut self, mut note: Note) -> Result<Note> {
        let content = serde_json::to_string(&note.blocks)?;
        let encrypted = self.encrypt_content(&content)?;
        note.is_encrypted = true;
        note.blocks = Vec::new();

        let mut inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let mut conn = inner.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id_str = note.id.to_string();
        let folder_id_str = note.folder_id.to_string();
        let created_at_str = note.created_at.to_rfc3339();
        let updated_at_str = note.updated_at.to_rfc3339();
        // P1 修复 (P1-6): 写入 is_pinned/is_encrypted
        let is_pinned: i64 = if note.is_pinned { 1 } else { 0 };
        let is_encrypted: i64 = if note.is_encrypted { 1 } else { 0 };

        // P1 修复 (P1-7): INSERT notes + INSERT note_tags 包裹在事务中
        let tx = conn.transaction()?;
        tx.execute(
            "INSERT INTO notes (id, title, content, folder_id, is_pinned, is_encrypted, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![id_str, note.title, encrypted, folder_id_str, is_pinned, is_encrypted, created_at_str, updated_at_str],
        )?;

        for tag_id in &note.tags {
            let tag_id_str = tag_id.to_string();
            tx.execute(
                "INSERT OR IGNORE INTO note_tags (note_id, tag_id) VALUES (?1, ?2)",
                params![id_str, tag_id_str],
            )?;
        }
        tx.commit()?;

        Ok(note)
    }

    fn get_note(&self, id: &Uuid) -> Result<Option<Note>> {
        let inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let result = NoteRepository::get_note(&*inner, id)?;
        drop(inner);

        match result {
            Some(mut note) => {
                if note.is_encrypted && self.is_unlocked() {
                    let content = serde_json::to_string(&note.blocks)?;
                    let decrypted = self.decrypt_content(&content).unwrap_or(content);
                    note.blocks = serde_json::from_str(&decrypted)
                    .map_err(|e| PersistenceError::DeserializationError(format!("note blocks: {e}")))?;
                }
                Ok(Some(note))
            }
            None => Ok(None),
        }
    }

    fn update_note(&mut self, mut note: Note) -> Result<Note> {
        let content = serde_json::to_string(&note.blocks)?;
        let encrypted = self.encrypt_content(&content)?;
        note.is_encrypted = true;

        let inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let conn = inner.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let id_str = note.id.to_string();
        let updated_at_str = note.updated_at.to_rfc3339();
        // P1 修复 (P1-6): 写入 is_pinned/is_encrypted
        let is_pinned: i64 = if note.is_pinned { 1 } else { 0 };
        let is_encrypted: i64 = if note.is_encrypted { 1 } else { 0 };

        conn.execute(
            "UPDATE notes SET title = ?1, content = ?2, is_pinned = ?3, is_encrypted = ?4, updated_at = ?5 WHERE id = ?6",
            params![note.title, encrypted, is_pinned, is_encrypted, updated_at_str, id_str],
        )?;

        Ok(note)
    }

    fn delete_note(&mut self, id: &Uuid) -> Result<()> {
        let mut inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        NoteRepository::delete_note(&mut *inner, id)
    }

    fn list_notes(&self, folder_id: Option<&Uuid>) -> Result<Vec<Note>> {
        let inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let notes = NoteRepository::list_notes(&*inner, folder_id)?;
        drop(inner);

        let mut result = Vec::new();
        for mut note in notes {
            if note.is_encrypted && self.is_unlocked() {
                let content = serde_json::to_string(&note.blocks)?;
                let decrypted = self.decrypt_content(&content).unwrap_or(content);
                note.blocks = serde_json::from_str(&decrypted)
                    .map_err(|e| PersistenceError::DeserializationError(format!("note blocks: {e}")))?;
            }
            result.push(note);
        }
        Ok(result)
    }

    fn create_folder(&mut self, folder: Folder) -> Result<Folder> {
        let mut inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        NoteRepository::create_folder(&mut *inner, folder)
    }

    fn get_folder(&self, id: &Uuid) -> Result<Option<Folder>> {
        let inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        NoteRepository::get_folder(&*inner, id)
    }

    fn update_folder(&mut self, folder: Folder) -> Result<Folder> {
        let mut inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        NoteRepository::update_folder(&mut *inner, folder)
    }

    fn delete_folder(&mut self, id: &Uuid) -> Result<()> {
        let mut inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        NoteRepository::delete_folder(&mut *inner, id)
    }

    fn list_folders(&self, parent_id: Option<&Uuid>) -> Result<Vec<Folder>> {
        let inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        NoteRepository::list_folders(&*inner, parent_id)
    }

    fn create_tag(&mut self, tag: Tag) -> Result<Tag> {
        let mut inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        NoteRepository::create_tag(&mut *inner, tag)
    }

    fn delete_tag(&mut self, id: &Uuid) -> Result<()> {
        let mut inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        NoteRepository::delete_tag(&mut *inner, id)
    }

    fn list_tags(&self) -> Result<Vec<Tag>> {
        let inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        NoteRepository::list_tags(&*inner)
    }

    fn add_tag_to_note(&mut self, note_id: &Uuid, tag_id: &Uuid) -> Result<()> {
        let mut inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        NoteRepository::add_tag_to_note(&mut *inner, note_id, tag_id)
    }

    fn remove_tag_from_note(&mut self, note_id: &Uuid, tag_id: &Uuid) -> Result<()> {
        let mut inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        NoteRepository::remove_tag_from_note(&mut *inner, note_id, tag_id)
    }

    fn create_attachment(&mut self, attachment: Attachment) -> Result<Attachment> {
        let mut inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        NoteRepository::create_attachment(&mut *inner, attachment)
    }

    fn delete_attachment(&mut self, id: &Uuid) -> Result<()> {
        let mut inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        NoteRepository::delete_attachment(&mut *inner, id)
    }

    fn list_attachments(&self, note_id: &Uuid) -> Result<Vec<Attachment>> {
        let inner = self.inner.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        NoteRepository::list_attachments(&*inner, note_id)
    }
}

pub struct EncryptedFileStorage {
    base_dir: PathBuf,
    crypto: DefaultCryptoEngine,
    key: Mutex<Option<Vec<u8>>>,
}

impl EncryptedFileStorage {
    pub fn new(base_dir: impl Into<PathBuf>, config: CryptoConfig) -> Self {
        Self {
            base_dir: base_dir.into(),
            crypto: DefaultCryptoEngine::new(config),
            key: Mutex::new(None),
        }
    }

    pub fn set_key(&self, key: Vec<u8>) {
        *self.key.lock().expect("mutex lock") = Some(key);
    }

    pub fn clear_key(&self) {
        *self.key.lock().expect("mutex lock") = None;
    }

    pub fn write_file(&self, relative_path: &str, data: &[u8]) -> Result<()> {
        let key_guard = self.key.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let key = key_guard.as_ref().ok_or_else(|| PersistenceError::DatabaseError("encryption key not set".to_string()))?;

        let encrypted = self.crypto.encrypt(data, key)?;
        let hash = Self::compute_hash(data);

        let file_path = self.base_dir.join(relative_path);
        if let Some(parent) = file_path.parent() {
            fs::create_dir_all(parent)?;
        }

        let mut combined = Vec::new();
        combined.extend_from_slice(&hash);
        combined.extend_from_slice(&encrypted);
        fs::write(&file_path, &combined)?;
        Ok(())
    }

    pub fn read_file(&self, relative_path: &str) -> Result<Vec<u8>> {
        let key_guard = self.key.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let key = key_guard.as_ref().ok_or_else(|| PersistenceError::DatabaseError("encryption key not set".to_string()))?;

        let file_path = self.base_dir.join(relative_path);
        let data = fs::read(&file_path)?;

        if data.len() < 32 {
            return Err(PersistenceError::DatabaseError("file too short".to_string()).into());
        }

        let stored_hash = &data[..32];
        let encrypted = &data[32..];

        let decrypted = self.crypto.decrypt(encrypted, key)?;
        let computed_hash = Self::compute_hash(&decrypted);

        if stored_hash != computed_hash.as_slice() {
            return Err(PersistenceError::DatabaseError("file integrity check failed".to_string()).into());
        }

        Ok(decrypted)
    }

    pub fn delete_file(&self, relative_path: &str) -> Result<()> {
        let file_path = self.base_dir.join(relative_path);
        if file_path.exists() {
            fs::remove_file(&file_path)?;
        }
        Ok(())
    }

    pub fn file_exists(&self, relative_path: &str) -> bool {
        self.base_dir.join(relative_path).exists()
    }

    pub fn verify_integrity(&self, relative_path: &str) -> Result<bool> {
        let key_guard = self.key.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let key = key_guard.as_ref().ok_or_else(|| PersistenceError::DatabaseError("encryption key not set".to_string()))?;

        let file_path = self.base_dir.join(relative_path);
        let data = fs::read(&file_path)?;

        if data.len() < 32 {
            return Ok(false);
        }

        let stored_hash = &data[..32];
        let encrypted = &data[32..];

        let decrypted = match self.crypto.decrypt(encrypted, key) {
            Ok(d) => d,
            Err(_) => return Ok(false),
        };

        let computed_hash = Self::compute_hash(&decrypted);
        Ok(stored_hash == computed_hash.as_slice())
    }

    fn compute_hash(data: &[u8]) -> Vec<u8> {
        let mut hasher = Sha256::new();
        hasher.update(data);
        hasher.finalize().to_vec()
    }
}

// ============================================================================
// RBAC Repository
// ============================================================================

fn permission_to_str(p: &Permission) -> &'static str {
    match p {
        Permission::Read => "Read",
        Permission::Write => "Write",
        Permission::Admin => "Admin",
    }
}

fn str_to_permission(s: &str) -> Permission {
    match s {
        "Write" => Permission::Write,
        "Admin" => Permission::Admin,
        _ => Permission::Read,
    }
}

impl SqliteNoteRepository {
    // ---- ResourceACL CRUD ----

    pub fn create_resource_acl(&self, acl: ResourceACL) -> Result<ResourceACL> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let permission_str = permission_to_str(&acl.permission);
        let granted_at_str = acl.granted_at.to_rfc3339();
        conn.execute(
            "INSERT INTO resource_acls (id, resource_id, resource_type, user_id, permission, granted_by, granted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![acl.id, acl.resource_id, acl.resource_type, acl.user_id, permission_str, acl.granted_by, granted_at_str],
        )?;
        Ok(acl)
    }

    pub fn get_resource_acl(&self, id: &str) -> Result<Option<ResourceACL>> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let mut stmt = conn.prepare(
            "SELECT id, resource_id, resource_type, user_id, permission, granted_by, granted_at FROM resource_acls WHERE id = ?1",
        )?;
        let result = stmt.query_row(params![id], |row| {
            Ok(ResourceACL {
                id: row.get(0)?,
                resource_id: row.get(1)?,
                resource_type: row.get(2)?,
                user_id: row.get(3)?,
                permission: str_to_permission(&row.get::<_, String>(4)?),
                granted_by: row.get(5)?,
                granted_at: chrono::DateTime::parse_from_rfc3339(&row.get::<_, String>(6)?)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?
                    .to_utc(),
            })
        });
        match result {
            Ok(acl) => Ok(Some(acl)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    pub fn list_resource_acls_for_resource(&self, resource_id: &str) -> Result<Vec<ResourceACL>> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let mut stmt = conn.prepare(
            "SELECT id, resource_id, resource_type, user_id, permission, granted_by, granted_at FROM resource_acls WHERE resource_id = ?1",
        )?;
        let acls = stmt.query_map(params![resource_id], |row| {
            Ok(ResourceACL {
                id: row.get(0)?,
                resource_id: row.get(1)?,
                resource_type: row.get(2)?,
                user_id: row.get(3)?,
                permission: str_to_permission(&row.get::<_, String>(4)?),
                granted_by: row.get(5)?,
                granted_at: chrono::DateTime::parse_from_rfc3339(&row.get::<_, String>(6)?)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?
                    .to_utc(),
            })
        })?.collect::<Result<Vec<_>, _>>()?;
        Ok(acls)
    }

    pub fn list_resource_acls_for_user(&self, user_id: &str) -> Result<Vec<ResourceACL>> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let mut stmt = conn.prepare(
            "SELECT id, resource_id, resource_type, user_id, permission, granted_by, granted_at FROM resource_acls WHERE user_id = ?1",
        )?;
        let acls = stmt.query_map(params![user_id], |row| {
            Ok(ResourceACL {
                id: row.get(0)?,
                resource_id: row.get(1)?,
                resource_type: row.get(2)?,
                user_id: row.get(3)?,
                permission: str_to_permission(&row.get::<_, String>(4)?),
                granted_by: row.get(5)?,
                granted_at: chrono::DateTime::parse_from_rfc3339(&row.get::<_, String>(6)?)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?
                    .to_utc(),
            })
        })?.collect::<Result<Vec<_>, _>>()?;
        Ok(acls)
    }

    pub fn update_resource_acl(&self, acl: ResourceACL) -> Result<ResourceACL> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let permission_str = permission_to_str(&acl.permission);
        conn.execute(
            "UPDATE resource_acls SET permission = ?1 WHERE id = ?2",
            params![permission_str, acl.id],
        )?;
        Ok(acl)
    }

    pub fn delete_resource_acl(&self, id: &str) -> Result<()> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        conn.execute("DELETE FROM resource_acls WHERE id = ?1", params![id])?;
        Ok(())
    }

    // ---- Workspace CRUD ----

    pub fn create_workspace(&self, workspace: Workspace) -> Result<Workspace> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let created_at_str = workspace.created_at.to_rfc3339();
        let updated_at_str = workspace.updated_at.to_rfc3339();
        conn.execute(
            "INSERT INTO workspaces (id, name, owner_id, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![workspace.id, workspace.name, workspace.owner_id, created_at_str, updated_at_str],
        )?;
        Ok(workspace)
    }

    pub fn get_workspace(&self, id: &str) -> Result<Option<Workspace>> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let mut stmt = conn.prepare(
            "SELECT id, name, owner_id, created_at, updated_at FROM workspaces WHERE id = ?1",
        )?;
        let result = stmt.query_row(params![id], |row| {
            Ok(Workspace {
                id: row.get(0)?,
                name: row.get(1)?,
                owner_id: row.get(2)?,
                created_at: chrono::DateTime::parse_from_rfc3339(&row.get::<_, String>(3)?)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?
                    .to_utc(),
                updated_at: chrono::DateTime::parse_from_rfc3339(&row.get::<_, String>(4)?)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?
                    .to_utc(),
            })
        });
        match result {
            Ok(ws) => Ok(Some(ws)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    pub fn list_workspaces_for_owner(&self, owner_id: &str) -> Result<Vec<Workspace>> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let mut stmt = conn.prepare(
            "SELECT id, name, owner_id, created_at, updated_at FROM workspaces WHERE owner_id = ?1 ORDER BY name",
        )?;
        let workspaces = stmt.query_map(params![owner_id], |row| {
            Ok(Workspace {
                id: row.get(0)?,
                name: row.get(1)?,
                owner_id: row.get(2)?,
                created_at: chrono::DateTime::parse_from_rfc3339(&row.get::<_, String>(3)?)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?
                    .to_utc(),
                updated_at: chrono::DateTime::parse_from_rfc3339(&row.get::<_, String>(4)?)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?
                    .to_utc(),
            })
        })?.collect::<Result<Vec<_>, _>>()?;
        Ok(workspaces)
    }

    pub fn update_workspace(&self, workspace: Workspace) -> Result<Workspace> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let updated_at_str = workspace.updated_at.to_rfc3339();
        conn.execute(
            "UPDATE workspaces SET name = ?1, updated_at = ?2 WHERE id = ?3",
            params![workspace.name, updated_at_str, workspace.id],
        )?;
        Ok(workspace)
    }

    pub fn delete_workspace(&self, id: &str) -> Result<()> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        conn.execute("DELETE FROM workspaces WHERE id = ?1", params![id])?;
        Ok(())
    }

    // ---- WorkspaceMember CRUD ----

    pub fn create_workspace_member(&self, member: WorkspaceMember) -> Result<WorkspaceMember> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let role_str = permission_to_str(&member.role);
        let joined_at_str = member.joined_at.to_rfc3339();
        conn.execute(
            "INSERT INTO workspace_members (id, workspace_id, user_id, role, joined_at) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![member.id, member.workspace_id, member.user_id, role_str, joined_at_str],
        )?;
        Ok(member)
    }

    pub fn get_workspace_member(&self, id: &str) -> Result<Option<WorkspaceMember>> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let mut stmt = conn.prepare(
            "SELECT id, workspace_id, user_id, role, joined_at FROM workspace_members WHERE id = ?1",
        )?;
        let result = stmt.query_row(params![id], |row| {
            Ok(WorkspaceMember {
                id: row.get(0)?,
                workspace_id: row.get(1)?,
                user_id: row.get(2)?,
                role: str_to_permission(&row.get::<_, String>(3)?),
                joined_at: chrono::DateTime::parse_from_rfc3339(&row.get::<_, String>(4)?)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?
                    .to_utc(),
            })
        });
        match result {
            Ok(m) => Ok(Some(m)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    pub fn list_workspace_members(&self, workspace_id: &str) -> Result<Vec<WorkspaceMember>> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let mut stmt = conn.prepare(
            "SELECT id, workspace_id, user_id, role, joined_at FROM workspace_members WHERE workspace_id = ?1 ORDER BY joined_at",
        )?;
        let members = stmt.query_map(params![workspace_id], |row| {
            Ok(WorkspaceMember {
                id: row.get(0)?,
                workspace_id: row.get(1)?,
                user_id: row.get(2)?,
                role: str_to_permission(&row.get::<_, String>(3)?),
                joined_at: chrono::DateTime::parse_from_rfc3339(&row.get::<_, String>(4)?)
                    .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?
                    .to_utc(),
            })
        })?.collect::<Result<Vec<_>, _>>()?;
        Ok(members)
    }

    pub fn update_workspace_member(&self, member: WorkspaceMember) -> Result<WorkspaceMember> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        let role_str = permission_to_str(&member.role);
        conn.execute(
            "UPDATE workspace_members SET role = ?1 WHERE id = ?2",
            params![role_str, member.id],
        )?;
        Ok(member)
    }

    pub fn delete_workspace_member(&self, id: &str) -> Result<()> {
        let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
        conn.execute("DELETE FROM workspace_members WHERE id = ?1", params![id])?;
        Ok(())
    }
}

// ============================================================================
// IPFS Block Storage (feature-gated)
// ============================================================================

#[cfg(feature = "ipfs")]
pub mod ipfs {
    use devnote_extensions::ipfs::{IpfsClient, IpfsConfig, IpfsError};
    use rusqlite::params;
    use std::sync::Mutex;
    use uuid::Uuid;
    use anyhow::Result;

    /// Tracks the association between notes/attachments and IPFS CIDs.
    #[derive(Debug, Clone)]
    pub struct IpfsMetadata {
        pub id: Uuid,
        pub note_id: Uuid,
        pub attachment_id: Option<Uuid>,
        pub cid: String,
        pub content_type: String,
        pub size_bytes: u64,
        pub pinned: bool,
        pub created_at: chrono::DateTime<chrono::Utc>,
    }

    /// IPFS-backed block storage that stores attachment data on IPFS
    /// and tracks CID-to-note mappings in the local SQLite database.
    pub struct IpfsBlockStorage {
        client: IpfsClient,
        conn: Mutex<rusqlite::Connection>,
    }

    impl IpfsBlockStorage {
        /// Create a new IpfsBlockStorage with the given IPFS config and a shared
        /// SQLite connection (typically from the existing SqliteNoteRepository).
        pub fn new(config: IpfsConfig, conn: rusqlite::Connection) -> Result<Self, IpfsError> {
            let client = IpfsClient::new(config, None)?;
            Ok(Self {
                client,
                conn: Mutex::new(conn),
            })
        }

        /// Check if the configured IPFS node is reachable.
        pub async fn ping(&self) -> Result<bool, IpfsError> {
            self.client.ping().await
        }

        /// Check if IPFS is available (sync check - just verifies client exists).
        pub fn is_available(&self) -> bool {
            true
        }

        /// Store attachment data on IPFS and track the CID mapping.
        /// Returns the CID of the stored data.
        pub async fn store_attachment_ipfs(
            &self,
            note_id: &Uuid,
            attachment_id: Option<&Uuid>,
            data: &[u8],
            content_type: &str,
        ) -> Result<String> {
            let cid = self.client.add(data).await
                .map_err(|e| anyhow::anyhow!("IPFS store failed: {}", e))?;

            let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
            let id = Uuid::new_v4();
            let id_str = id.to_string();
            let note_id_str = note_id.to_string();
            let attachment_id_str = attachment_id.map(|a| a.to_string());
            let now = chrono::Utc::now();
            let now_str = now.to_rfc3339();

            conn.execute(
                "INSERT INTO ipfs_metadata (id, note_id, attachment_id, cid, content_type, size_bytes, pinned, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                params![id_str, note_id_str, attachment_id_str, cid, content_type, data.len() as i64, true, now_str],
            )?;

            Ok(cid)
        }

        /// Retrieve attachment data from IPFS by CID.
        pub async fn retrieve_attachment_ipfs(&self, cid: &str) -> Result<Vec<u8>> {
            let bytes = self.client.get(cid).await
                .map_err(|e| anyhow::anyhow!("IPFS retrieve failed: {}", e))?;
            Ok(bytes.to_vec())
        }

        /// Delete attachment data from IPFS and remove the CID mapping.
        pub async fn delete_attachment_ipfs(&self, cid: &str) -> Result<()> {
            self.client.remove(cid).await
                .map_err(|e| anyhow::anyhow!("IPFS delete failed: {}", e))?;

            let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
            conn.execute(
                "DELETE FROM ipfs_metadata WHERE cid = ?1",
                params![cid],
            )?;

            Ok(())
        }

        /// List all IPFS metadata entries for a given note.
        pub fn list_ipfs_metadata(&self, note_id: &Uuid) -> Result<Vec<IpfsMetadata>> {
            let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
            let note_id_str = note_id.to_string();
            let mut stmt = conn.prepare(
                "SELECT id, note_id, attachment_id, cid, content_type, size_bytes, pinned, created_at
                 FROM ipfs_metadata WHERE note_id = ?1 ORDER BY created_at",
            )?;

            let rows = stmt.query_map(params![note_id_str], |row| {
                let id_str: String = row.get(0)?;
                let note_id_str: String = row.get(1)?;
                let attachment_id_str: Option<String> = row.get(2)?;
                let cid: String = row.get(3)?;
                let content_type: String = row.get(4)?;
                let size_bytes: i64 = row.get(5)?;
                let pinned: bool = row.get(6)?;
                let created_at_str: String = row.get(7)?;

                Ok(IpfsMetadata {
                    id: Uuid::parse_str(&id_str)
                        .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
                    note_id: Uuid::parse_str(&note_id_str)
                        .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
                    attachment_id: attachment_id_str
                        .map(|a| Uuid::parse_str(&a))
                        .transpose()
                        .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
                    cid,
                    content_type,
                    size_bytes: size_bytes as u64,
                    pinned,
                    created_at: chrono::DateTime::parse_from_rfc3339(&created_at_str)
                        .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?
                        .to_utc(),
                })
            })?;

            rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
        }

        /// Pin a CID to prevent garbage collection.
        pub async fn pin_cid(&self, cid: &str) -> Result<()> {
            self.client.pin(cid).await
                .map_err(|e| anyhow::anyhow!("IPFS pin failed: {}", e))?;

            let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
            conn.execute(
                "UPDATE ipfs_metadata SET pinned = 1 WHERE cid = ?1",
                params![cid],
            )?;

            Ok(())
        }

        /// Unpin a CID (allows garbage collection).
        pub async fn unpin_cid(&self, cid: &str) -> Result<()> {
            self.client.unpin(cid).await
                .map_err(|e| anyhow::anyhow!("IPFS unpin failed: {}", e))?;

            let conn = self.conn.lock().map_err(|e| PersistenceError::DatabaseError(e.to_string()))?;
            conn.execute(
                "UPDATE ipfs_metadata SET pinned = 0 WHERE cid = ?1",
                params![cid],
            )?;

            Ok(())
        }
    }
}

/// Stub indicating IPFS is not compiled in.
#[cfg(not(feature = "ipfs"))]
pub mod ipfs {
    /// Returns false when the `ipfs` feature is not enabled.
    pub fn is_ipfs_available() -> bool {
        false
    }
}
