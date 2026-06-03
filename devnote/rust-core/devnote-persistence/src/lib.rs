use devnote_core::models::{Attachment, Folder, Note, Tag};
use devnote_observe::{instrument, warn};
use devnote_core::traits::NoteRepository;
use devnote_crypto::{CryptoEngine, DefaultCryptoEngine, CryptoConfig};
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
}

const _DB_VERSION: i32 = 1;

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
        let conn = self.conn.lock().unwrap();
        let current_version: i32 = conn
            .query_row(
                "SELECT version FROM schema_version ORDER BY version DESC LIMIT 1",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        if current_version < 1 {
            conn.execute_batch(SCHEMA_V1)?;
            conn.execute(
                "INSERT OR REPLACE INTO schema_version (version) VALUES (?1)",
                params![1],
            )?;
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

        let blocks = serde_json::from_str(&content).unwrap_or_default();

        Ok(Note {
            id: Uuid::parse_str(&id_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            title,
            folder_id: Uuid::parse_str(&folder_id_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            blocks,
            tags: Vec::new(),
            is_pinned: false,
            is_encrypted: false,
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

        Ok(Folder {
            id: Uuid::parse_str(&id_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            name,
            parent_id: parent_id_str
                .map(|p| Uuid::parse_str(&p))
                .transpose()
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            sort_order: 0,
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

        Ok(Tag {
            id: Uuid::parse_str(&id_str)
                .map_err(|e| rusqlite::Error::ToSqlConversionFailure(Box::new(e)))?,
            name,
            color: None,
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
        let conn = self.conn.lock().unwrap();
        let id_str = id.to_string();
        let mut stmt = conn.prepare(
            "SELECT id, title, content, folder_id, created_at, updated_at FROM notes WHERE id = ?1",
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
        let conn = self.conn.lock().unwrap();
        let notes = match folder_id {
            Some(fid) => {
                let fid_str = fid.to_string();
                let mut stmt = conn.prepare(
                    "SELECT id, title, content, folder_id, created_at, updated_at FROM notes WHERE folder_id = ?1 ORDER BY updated_at DESC",
                )?;
                let result = stmt.query_map(params![fid_str], Self::row_to_note)?
                    .collect::<Result<Vec<_>, _>>()?;
                result
            }
            None => {
                let mut stmt = conn.prepare(
                    "SELECT id, title, content, folder_id, created_at, updated_at FROM notes ORDER BY updated_at DESC",
                )?;
                let result = stmt.query_map([], Self::row_to_note)?
                    .collect::<Result<Vec<_>, _>>()?;
                result
            }
        };
        Ok(notes)
    }

    fn fetch_folders_by_parent(&self, parent_id: Option<&Uuid>) -> Result<Vec<Folder>> {
        let conn = self.conn.lock().unwrap();
        let folders = match parent_id {
            Some(pid) => {
                let pid_str = pid.to_string();
                let mut stmt = conn.prepare(
                    "SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE parent_id = ?1 ORDER BY name",
                )?;
                let result = stmt.query_map(params![pid_str], Self::row_to_folder)?
                    .collect::<Result<Vec<_>, _>>()?;
                result
            }
            None => {
                let mut stmt = conn.prepare(
                    "SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE parent_id IS NULL ORDER BY name",
                )?;
                let result = stmt.query_map([], Self::row_to_folder)?
                    .collect::<Result<Vec<_>, _>>()?;
                result
            }
        };
        Ok(folders)
    }

    fn remove_note_by_id(&self, id: &Uuid) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        let id_str = id.to_string();
        conn.execute("DELETE FROM notes WHERE id = ?1", params![id_str])?;
        Ok(())
    }

    fn link_tag_to_note(&self, note_id: &Uuid, tag_id: &Uuid) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        let note_id_str = note_id.to_string();
        let tag_id_str = tag_id.to_string();
        conn.execute(
            "INSERT INTO note_tags (note_id, tag_id) VALUES (?1, ?2)",
            params![note_id_str, tag_id_str],
        )?;
        Ok(())
    }

    fn unlink_tag_from_note(&self, note_id: &Uuid, tag_id: &Uuid) -> Result<()> {
        let conn = self.conn.lock().unwrap();
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
        let conn = self.conn.lock().unwrap();
        let id = Uuid::new_v4();
        let now = Utc::now();
        let id_str = id.to_string();
        let folder_id_str = folder_id.to_string();
        let now_str = now.to_rfc3339();

        conn.execute(
            "INSERT INTO notes (id, title, content, folder_id, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![id_str, title, content, folder_id_str, now_str, now_str],
        )?;

        Ok(Note {
            id,
            title: title.to_string(),
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
        let conn = self.conn.lock().unwrap();
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
        let conn = self.conn.lock().unwrap();
        let id = Uuid::new_v4();
        let now = Utc::now();
        let id_str = id.to_string();
        let parent_id_str = parent_id.map(|p| p.to_string());
        let now_str = now.to_rfc3339();

        conn.execute(
            "INSERT INTO folders (id, name, parent_id, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5)",
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
        let conn = self.conn.lock().unwrap();
        let id = Uuid::new_v4();
        let now = Utc::now();
        let id_str = id.to_string();
        let now_str = now.to_rfc3339();

        conn.execute(
            "INSERT INTO tags (id, name, created_at) VALUES (?1, ?2, ?3)",
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
}

impl NoteRepository for SqliteNoteRepository {
    fn create_note(&mut self, note: Note) -> Result<Note> {
        let conn = self.conn.lock().unwrap();
        let id_str = note.id.to_string();
        let folder_id_str = note.folder_id.to_string();
        let content = serde_json::to_string(&note.blocks)?;
        let created_at_str = note.created_at.to_rfc3339();
        let updated_at_str = note.updated_at.to_rfc3339();

        conn.execute(
            "INSERT INTO notes (id, title, content, folder_id, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![id_str, note.title, content, folder_id_str, created_at_str, updated_at_str],
        )?;

        for tag_id in &note.tags {
            let tag_id_str = tag_id.to_string();
            conn.execute(
                "INSERT OR IGNORE INTO note_tags (note_id, tag_id) VALUES (?1, ?2)",
                params![id_str, tag_id_str],
            )?;
        }

        Ok(note)
    }

    fn get_note(&self, id: &Uuid) -> Result<Option<Note>> {
        self.fetch_note_by_id(id)
    }

    fn update_note(&mut self, note: Note) -> Result<Note> {
        let conn = self.conn.lock().unwrap();
        let id_str = note.id.to_string();
        let content = serde_json::to_string(&note.blocks)?;
        let updated_at_str = note.updated_at.to_rfc3339();

        conn.execute(
            "UPDATE notes SET title = ?1, content = ?2, updated_at = ?3 WHERE id = ?4",
            params![note.title, content, updated_at_str, id_str],
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
        let conn = self.conn.lock().unwrap();
        let id_str = folder.id.to_string();
        let parent_id_str = folder.parent_id.map(|p| p.to_string());
        let created_at_str = folder.created_at.to_rfc3339();
        let updated_at_str = folder.updated_at.to_rfc3339();

        conn.execute(
            "INSERT INTO folders (id, name, parent_id, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![id_str, folder.name, parent_id_str, created_at_str, updated_at_str],
        )?;

        Ok(folder)
    }

    fn get_folder(&self, id: &Uuid) -> Result<Option<Folder>> {
        let conn = self.conn.lock().unwrap();
        let id_str = id.to_string();
        let mut stmt = conn.prepare(
            "SELECT id, name, parent_id, created_at, updated_at FROM folders WHERE id = ?1",
        )?;

        let result = stmt.query_row(params![id_str], Self::row_to_folder);

        match result {
            Ok(folder) => Ok(Some(folder)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    fn update_folder(&mut self, folder: Folder) -> Result<Folder> {
        let conn = self.conn.lock().unwrap();
        let id_str = folder.id.to_string();
        let parent_id_str = folder.parent_id.map(|p| p.to_string());
        let updated_at_str = folder.updated_at.to_rfc3339();

        conn.execute(
            "UPDATE folders SET name = ?1, parent_id = ?2, updated_at = ?3 WHERE id = ?4",
            params![folder.name, parent_id_str, updated_at_str, id_str],
        )?;

        Ok(folder)
    }

    fn delete_folder(&mut self, id: &Uuid) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        let id_str = id.to_string();
        conn.execute("DELETE FROM folders WHERE id = ?1", params![id_str])?;
        Ok(())
    }

    fn list_folders(&self, parent_id: Option<&Uuid>) -> Result<Vec<Folder>> {
        self.fetch_folders_by_parent(parent_id)
    }

    fn create_tag(&mut self, tag: Tag) -> Result<Tag> {
        let conn = self.conn.lock().unwrap();
        let id_str = tag.id.to_string();
        let created_at_str = tag.created_at.to_rfc3339();

        conn.execute(
            "INSERT INTO tags (id, name, created_at) VALUES (?1, ?2, ?3)",
            params![id_str, tag.name, created_at_str],
        )?;

        Ok(tag)
    }

    fn delete_tag(&mut self, id: &Uuid) -> Result<()> {
        let conn = self.conn.lock().unwrap();
        let id_str = id.to_string();
        conn.execute("DELETE FROM tags WHERE id = ?1", params![id_str])?;
        Ok(())
    }

    fn list_tags(&self) -> Result<Vec<Tag>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, name, created_at FROM tags ORDER BY name",
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
        let conn = self.conn.lock().unwrap();
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
        let conn = self.conn.lock().unwrap();
        let id_str = id.to_string();
        conn.execute("DELETE FROM attachments WHERE id = ?1", params![id_str])?;
        Ok(())
    }

    fn list_attachments(&self, note_id: &Uuid) -> Result<Vec<Attachment>> {
        let conn = self.conn.lock().unwrap();
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
        *self.key.lock().unwrap() = Some(key);
        *self.salt.lock().unwrap() = Some(salt);
        Ok(())
    }

    pub fn change_password(&self, old_password: &str, new_password: &str) -> Result<bool> {
        let salt_guard = self.salt.lock().unwrap();
        if let Some(ref salt) = *salt_guard {
            let old_key = self.crypto.derive_key(old_password, salt)?;
            let key_guard = self.key.lock().unwrap();
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
        *self.key.lock().unwrap() = Some(new_key);
        *self.salt.lock().unwrap() = Some(new_salt);
        Ok(true)
    }

    pub fn clear_key(&self) {
        *self.key.lock().unwrap() = None;
        *self.salt.lock().unwrap() = None;
    }

    pub fn is_unlocked(&self) -> bool {
        self.key.lock().unwrap().is_some()
    }

    fn encrypt_content(&self, plaintext: &str) -> Result<String> {
        let key_guard = self.key.lock().unwrap();
        let key = key_guard.as_ref().ok_or_else(|| PersistenceError::DatabaseError("encryption key not set".to_string()))?;
        let encrypted = self.crypto.encrypt(plaintext.as_bytes(), key)?;
        Ok(BASE64.encode(&encrypted))
    }

    fn decrypt_content(&self, ciphertext: &str) -> Result<String> {
        let key_guard = self.key.lock().unwrap();
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

        let inner = self.inner.lock().unwrap();
        let conn = inner.conn.lock().unwrap();
        let id_str = note.id.to_string();
        let folder_id_str = note.folder_id.to_string();
        let created_at_str = note.created_at.to_rfc3339();
        let updated_at_str = note.updated_at.to_rfc3339();

        conn.execute(
            "INSERT INTO notes (id, title, content, folder_id, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![id_str, note.title, encrypted, folder_id_str, created_at_str, updated_at_str],
        )?;

        for tag_id in &note.tags {
            let tag_id_str = tag_id.to_string();
            conn.execute(
                "INSERT OR IGNORE INTO note_tags (note_id, tag_id) VALUES (?1, ?2)",
                params![id_str, tag_id_str],
            )?;
        }

        Ok(note)
    }

    fn get_note(&self, id: &Uuid) -> Result<Option<Note>> {
        let inner = self.inner.lock().unwrap();
        let result = NoteRepository::get_note(&*inner, id)?;
        drop(inner);

        match result {
            Some(mut note) => {
                if note.is_encrypted && self.is_unlocked() {
                    let content = serde_json::to_string(&note.blocks)?;
                    let decrypted = self.decrypt_content(&content).unwrap_or(content);
                    note.blocks = serde_json::from_str(&decrypted).unwrap_or_default();
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

        let inner = self.inner.lock().unwrap();
        let conn = inner.conn.lock().unwrap();
        let id_str = note.id.to_string();
        let updated_at_str = note.updated_at.to_rfc3339();

        conn.execute(
            "UPDATE notes SET title = ?1, content = ?2, updated_at = ?3 WHERE id = ?4",
            params![note.title, encrypted, updated_at_str, id_str],
        )?;

        Ok(note)
    }

    fn delete_note(&mut self, id: &Uuid) -> Result<()> {
        let mut inner = self.inner.lock().unwrap();
        NoteRepository::delete_note(&mut *inner, id)
    }

    fn list_notes(&self, folder_id: Option<&Uuid>) -> Result<Vec<Note>> {
        let inner = self.inner.lock().unwrap();
        let notes = NoteRepository::list_notes(&*inner, folder_id)?;
        drop(inner);

        let mut result = Vec::new();
        for mut note in notes {
            if note.is_encrypted && self.is_unlocked() {
                let content = serde_json::to_string(&note.blocks)?;
                let decrypted = self.decrypt_content(&content).unwrap_or(content);
                note.blocks = serde_json::from_str(&decrypted).unwrap_or_default();
            }
            result.push(note);
        }
        Ok(result)
    }

    fn create_folder(&mut self, folder: Folder) -> Result<Folder> {
        let mut inner = self.inner.lock().unwrap();
        NoteRepository::create_folder(&mut *inner, folder)
    }

    fn get_folder(&self, id: &Uuid) -> Result<Option<Folder>> {
        let inner = self.inner.lock().unwrap();
        NoteRepository::get_folder(&*inner, id)
    }

    fn update_folder(&mut self, folder: Folder) -> Result<Folder> {
        let mut inner = self.inner.lock().unwrap();
        NoteRepository::update_folder(&mut *inner, folder)
    }

    fn delete_folder(&mut self, id: &Uuid) -> Result<()> {
        let mut inner = self.inner.lock().unwrap();
        NoteRepository::delete_folder(&mut *inner, id)
    }

    fn list_folders(&self, parent_id: Option<&Uuid>) -> Result<Vec<Folder>> {
        let inner = self.inner.lock().unwrap();
        NoteRepository::list_folders(&*inner, parent_id)
    }

    fn create_tag(&mut self, tag: Tag) -> Result<Tag> {
        let mut inner = self.inner.lock().unwrap();
        NoteRepository::create_tag(&mut *inner, tag)
    }

    fn delete_tag(&mut self, id: &Uuid) -> Result<()> {
        let mut inner = self.inner.lock().unwrap();
        NoteRepository::delete_tag(&mut *inner, id)
    }

    fn list_tags(&self) -> Result<Vec<Tag>> {
        let inner = self.inner.lock().unwrap();
        NoteRepository::list_tags(&*inner)
    }

    fn add_tag_to_note(&mut self, note_id: &Uuid, tag_id: &Uuid) -> Result<()> {
        let mut inner = self.inner.lock().unwrap();
        NoteRepository::add_tag_to_note(&mut *inner, note_id, tag_id)
    }

    fn remove_tag_from_note(&mut self, note_id: &Uuid, tag_id: &Uuid) -> Result<()> {
        let mut inner = self.inner.lock().unwrap();
        NoteRepository::remove_tag_from_note(&mut *inner, note_id, tag_id)
    }

    fn create_attachment(&mut self, attachment: Attachment) -> Result<Attachment> {
        let mut inner = self.inner.lock().unwrap();
        NoteRepository::create_attachment(&mut *inner, attachment)
    }

    fn delete_attachment(&mut self, id: &Uuid) -> Result<()> {
        let mut inner = self.inner.lock().unwrap();
        NoteRepository::delete_attachment(&mut *inner, id)
    }

    fn list_attachments(&self, note_id: &Uuid) -> Result<Vec<Attachment>> {
        let inner = self.inner.lock().unwrap();
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
        *self.key.lock().unwrap() = Some(key);
    }

    pub fn clear_key(&self) {
        *self.key.lock().unwrap() = None;
    }

    pub fn write_file(&self, relative_path: &str, data: &[u8]) -> Result<()> {
        let key_guard = self.key.lock().unwrap();
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
        let key_guard = self.key.lock().unwrap();
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
        let key_guard = self.key.lock().unwrap();
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
// IPFS Block Storage (feature-gated)
// ============================================================================

#[cfg(feature = "ipfs")]
pub mod ipfs {
    use devnote_ipfs::{IpfsClient, IpfsConfig, IpfsError};
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
            let client = IpfsClient::new(config)?;
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

            let conn = self.conn.lock().unwrap();
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

            let conn = self.conn.lock().unwrap();
            conn.execute(
                "DELETE FROM ipfs_metadata WHERE cid = ?1",
                params![cid],
            )?;

            Ok(())
        }

        /// List all IPFS metadata entries for a given note.
        pub fn list_ipfs_metadata(&self, note_id: &Uuid) -> Result<Vec<IpfsMetadata>> {
            let conn = self.conn.lock().unwrap();
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

            let conn = self.conn.lock().unwrap();
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

            let conn = self.conn.lock().unwrap();
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
