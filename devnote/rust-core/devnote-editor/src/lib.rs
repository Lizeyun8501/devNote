use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum BlockType {
    Paragraph,
    Heading { level: u8 },
    CodeBlock { language: Option<String> },
    List { ordered: bool },
    Quote,
    Table { rows: usize, cols: usize },
    Image { url: String, alt: Option<String> },
    LaTeX,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Block {
    pub id: Uuid,
    pub block_type: BlockType,
    pub content: String,
    pub children: Vec<Block>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl Block {
    pub fn new(block_type: BlockType, content: String) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            block_type,
            content,
            children: Vec::new(),
            created_at: now,
            updated_at: now,
        }
    }
}

pub trait BlockEditor: Send + Sync {
    fn insert_block(&mut self, parent_id: Option<&Uuid>, index: usize, block: Block) -> anyhow::Result<()>;
    fn remove_block(&mut self, block_id: &Uuid) -> anyhow::Result<Block>;
    fn update_block_content(&mut self, block_id: &Uuid, content: String) -> anyhow::Result<()>;
    fn move_block(&mut self, block_id: &Uuid, new_parent_id: Option<&Uuid>, new_index: usize) -> anyhow::Result<()>;
    fn get_block(&self, block_id: &Uuid) -> anyhow::Result<Option<&Block>>;
    fn get_children(&self, parent_id: &Uuid) -> anyhow::Result<Vec<&Block>>;
}
