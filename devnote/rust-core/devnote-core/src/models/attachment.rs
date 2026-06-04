use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Attachment {
    pub id: Uuid,
    pub note_id: Uuid,
    pub filename: String,
    pub mime_type: String,
    pub size_bytes: u64,
    pub storage_path: String,
    pub created_at: DateTime<Utc>,
}

impl Attachment {
    pub fn new(note_id: Uuid, filename: String, mime_type: String, size_bytes: u64, storage_path: String) -> Self {
        Self {
            id: Uuid::new_v4(),
            note_id,
            filename,
            mime_type,
            size_bytes,
            storage_path,
            created_at: Utc::now(),
        }
    }
}
