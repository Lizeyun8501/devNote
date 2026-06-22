use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};
use devnote_editor::Block;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Note {
    pub id: Uuid,
    pub title: String,
    /// 笔记纯文本内容（与 Dart NoteModel.content 对齐）
    /// P0 修复: 原 Rust Note 无此字段，Dart NoteModel.fromJson 因 required 字段缺失抛异常
    #[serde(default)]
    pub content: String,
    pub folder_id: Uuid,
    pub blocks: Vec<Block>,
    pub tags: Vec<Uuid>,
    pub is_pinned: bool,
    pub is_encrypted: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl Note {
    pub fn new(title: String, folder_id: Uuid) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            title,
            content: String::new(),
            folder_id,
            blocks: Vec::new(),
            tags: Vec::new(),
            is_pinned: false,
            is_encrypted: false,
            created_at: now,
            updated_at: now,
        }
    }
}
