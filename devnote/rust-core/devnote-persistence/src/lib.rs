use devnote_core::models::{Attachment, Folder, Note, Tag};
use devnote_core::traits::NoteRepository;
use std::sync::Mutex;
use thiserror::Error;
use uuid::Uuid;
use anyhow::Result;
use chrono::Utc;
use rusqlite::params;

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

CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY
);
"#;

pub struct SqliteNoteRepository {
    conn: Mutex<rusqlite::Connection>,
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

    pub fn delete_note(&self, id: &Uuid) -> Result<()> {
        self.remove_note_by_id(id)
    }

    pub fn list_notes(&self, folder_id: &Uuid) -> Result<Vec<Note>> {
        self.fetch_notes_by_folder(Some(folder_id))
    }

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
