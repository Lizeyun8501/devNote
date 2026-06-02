use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    pub note_id: Uuid,
    pub title: String,
    pub snippet: String,
    pub score: f64,
    pub highlighted_content: String,
    pub matched_at: DateTime<Utc>,
}

pub trait SearchEngine: Send + Sync {
    fn index_note(&mut self, note_id: &Uuid, title: &str, content: &str) -> anyhow::Result<()>;
    fn remove_note(&mut self, note_id: &Uuid) -> anyhow::Result<()>;
    fn search(&self, query: &str, limit: usize, offset: usize) -> anyhow::Result<Vec<SearchResult>>;
    fn search_by_tag(&self, tag: &str, limit: usize, offset: usize) -> anyhow::Result<Vec<SearchResult>>;
    fn rebuild_index(&mut self) -> anyhow::Result<()>;
}
