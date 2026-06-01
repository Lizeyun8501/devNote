use once_cell::sync::Lazy;
use rusqlite::Connection;
use std::sync::Mutex;

use crate::models::{Note, NoteFolder};

static DB: Lazy<Mutex<Connection>> = Lazy::new(|| {
    let conn = Connection::open_in_memory().expect("failed to open in-memory database");
    Mutex::new(conn)
});

pub fn init(db_path: &str) -> Result<(), String> {
    let conn = Connection::open(db_path).map_err(|e| e.to_string())?;
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS notes (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            content TEXT NOT NULL DEFAULT '',
            folder_id TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS folders (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            parent_id TEXT,
            created_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS tags (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            note_id TEXT NOT NULL
        );",
    )
    .map_err(|e| e.to_string())?;
    let mut guard = DB.lock().map_err(|e| e.to_string())?;
    *guard = conn;
    Ok(())
}

pub fn create_note(title: &str, content: &str, folder_id: Option<&str>) -> Result<Note, String> {
    let id = uuid();
    let now = now_millis();
    let note = Note {
        id: id.clone(),
        title: title.to_string(),
        content: content.to_string(),
        folder_id: folder_id.map(|s| s.to_string()),
        created_at: now,
        updated_at: now,
    };
    let guard = DB.lock().map_err(|e| e.to_string())?;
    guard
        .execute(
            "INSERT INTO notes (id, title, content, folder_id, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            rusqlite::params![
                note.id,
                note.title,
                note.content,
                note.folder_id,
                note.created_at,
                note.updated_at,
            ],
        )
        .map_err(|e| e.to_string())?;
    Ok(note)
}

pub fn list_notes(folder_id: Option<&str>) -> Result<Vec<Note>, String> {
    let guard = DB.lock().map_err(|e| e.to_string())?;
    let notes = match folder_id {
        Some(fid) => {
            let mut stmt = guard
                .prepare("SELECT id, title, content, folder_id, created_at, updated_at FROM notes WHERE folder_id = ?1")
                .map_err(|e| e.to_string())?;
            let rows = stmt
                .query_map(rusqlite::params![fid], |row| {
                    Ok(Note {
                        id: row.get(0)?,
                        title: row.get(1)?,
                        content: row.get(2)?,
                        folder_id: row.get(3)?,
                        created_at: row.get(4)?,
                        updated_at: row.get(5)?,
                    })
                })
                .map_err(|e| e.to_string())?;
            rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())?
        }
        None => {
            let mut stmt = guard
                .prepare("SELECT id, title, content, folder_id, created_at, updated_at FROM notes")
                .map_err(|e| e.to_string())?;
            let rows = stmt
                .query_map([], |row| {
                    Ok(Note {
                        id: row.get(0)?,
                        title: row.get(1)?,
                        content: row.get(2)?,
                        folder_id: row.get(3)?,
                        created_at: row.get(4)?,
                        updated_at: row.get(5)?,
                    })
                })
                .map_err(|e| e.to_string())?;
            rows.collect::<Result<Vec<_>, _>>().map_err(|e| e.to_string())?
        }
    };
    Ok(notes)
}

pub fn get_note(id: &str) -> Result<Option<Note>, String> {
    let guard = DB.lock().map_err(|e| e.to_string())?;
    let mut stmt = guard
        .prepare("SELECT id, title, content, folder_id, created_at, updated_at FROM notes WHERE id = ?1")
        .map_err(|e| e.to_string())?;
    let mut rows = stmt
        .query_map(rusqlite::params![id], |row| {
            Ok(Note {
                id: row.get(0)?,
                title: row.get(1)?,
                content: row.get(2)?,
                folder_id: row.get(3)?,
                created_at: row.get(4)?,
                updated_at: row.get(5)?,
            })
        })
        .map_err(|e| e.to_string())?;
    match rows.next() {
        Some(row) => Ok(Some(row.map_err(|e| e.to_string())?)),
        None => Ok(None),
    }
}

pub fn update_note(id: &str, title: &str, content: &str) -> Result<i32, String> {
    let now = now_millis();
    let guard = DB.lock().map_err(|e| e.to_string())?;
    let affected = guard
        .execute(
            "UPDATE notes SET title = ?1, content = ?2, updated_at = ?3 WHERE id = ?4",
            rusqlite::params![title, content, now, id],
        )
        .map_err(|e| e.to_string())?;
    Ok(affected as i32)
}

pub fn delete_note(id: &str) -> Result<i32, String> {
    let guard = DB.lock().map_err(|e| e.to_string())?;
    let affected = guard
        .execute("DELETE FROM notes WHERE id = ?1", rusqlite::params![id])
        .map_err(|e| e.to_string())?;
    Ok(affected as i32)
}

pub fn create_folder(name: &str, parent_id: Option<&str>) -> Result<NoteFolder, String> {
    let id = uuid();
    let now = now_millis();
    let folder = NoteFolder {
        id: id.clone(),
        name: name.to_string(),
        parent_id: parent_id.map(|s| s.to_string()),
        created_at: now,
    };
    let guard = DB.lock().map_err(|e| e.to_string())?;
    guard
        .execute(
            "INSERT INTO folders (id, name, parent_id, created_at) VALUES (?1, ?2, ?3, ?4)",
            rusqlite::params![folder.id, folder.name, folder.parent_id, folder.created_at],
        )
        .map_err(|e| e.to_string())?;
    Ok(folder)
}

pub fn list_folders() -> Result<Vec<NoteFolder>, String> {
    let guard = DB.lock().map_err(|e| e.to_string())?;
    let mut stmt = guard
        .prepare("SELECT id, name, parent_id, created_at FROM folders")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |row| {
            Ok(NoteFolder {
                id: row.get(0)?,
                name: row.get(1)?,
                parent_id: row.get(2)?,
                created_at: row.get(3)?,
            })
        })
        .map_err(|e| e.to_string())?;
    let folders = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;
    Ok(folders)
}

fn uuid() -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    format!("{:016x}-{:016x}", now, rand_u64())
}

fn rand_u64() -> u64 {
    use std::time::SystemTime;
    let t = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap()
        .subsec_nanos();
    let ptr = &t as *const u32 as usize;
    let stack_var = 0u64;
    let stack_ptr = &stack_var as *const u64 as usize;
    (t as u64).wrapping_mul(6364136223846793005).wrapping_add(ptr as u64).wrapping_add(stack_ptr as u64)
}

fn now_millis() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as i64
}
