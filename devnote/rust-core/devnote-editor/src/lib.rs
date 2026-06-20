//! 块编辑器引擎 —— 实现块级 Markdown 解析和渲染
//! 借鉴思源笔记的块编辑模型和 Obsidian 的 Markdown 解析策略
//!
//! 借鉴思源笔记的块编辑模型
//! 来源: https://github.com/siyuan-note/siyuan
//! 借鉴内容: 内容块(Block)作为最小编辑单元、块类型枚举(标题/段落/代码/列表/表格等)
//!
//! 借鉴 Obsidian 的 Markdown 解析策略
//! 来源: https://obsidian.md
//! 借鉴内容: 逐行解析 Markdown、代码块语法高亮、LaTeX 数学公式渲染、任务列表语法

use devnote_observe::{instrument, warn};
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
    TableBlock { rows: usize, cols: usize },
    Image { url: String, alt: Option<String> },
    LatexBlock,
    TaskListBlock,
    Audio {
        url: String,
        duration_ms: u64,
        transcript: Option<String>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Block {
    pub id: Uuid,
    pub note_id: Uuid,
    pub block_type: BlockType,
    pub content: String,
    pub position: usize,
    pub children: Vec<Block>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl Block {
    pub fn new(note_id: Uuid, block_type: BlockType, content: String, position: usize) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            note_id,
            block_type,
            content,
            position,
            children: Vec::new(),
            created_at: now,
            updated_at: now,
        }
    }
}

pub trait BlockEditor: Send + Sync {
    fn create_block(&mut self, note_id: Uuid, block_type: BlockType, content: String, position: usize) -> anyhow::Result<Block>;
    fn get_block(&self, id: &Uuid) -> anyhow::Result<Option<Block>>;
    fn update_block(&mut self, id: &Uuid, content: String) -> anyhow::Result<()>;
    fn delete_block(&mut self, id: &Uuid) -> anyhow::Result<()>;
    fn move_block(&mut self, id: &Uuid, new_position: usize) -> anyhow::Result<()>;
    fn list_blocks(&mut self, note_id: &Uuid, offset: Option<usize>, limit: Option<usize>) -> anyhow::Result<Vec<Block>>;
    fn list_blocks_paged(&mut self, note_id: &Uuid, page: usize, page_size: usize) -> anyhow::Result<Vec<Block>>;
    fn parse_markdown(&mut self, content: &str, note_id: Uuid) -> anyhow::Result<Vec<Block>>;

    fn insert_block(&mut self, parent_id: Option<&Uuid>, index: usize, block: Block) -> anyhow::Result<()>;
    fn remove_block(&mut self, block_id: &Uuid) -> anyhow::Result<Block>;
    fn update_block_content(&mut self, block_id: &Uuid, content: String) -> anyhow::Result<()>;
    fn move_block_to(&mut self, block_id: &Uuid, new_parent_id: Option<&Uuid>, new_index: usize) -> anyhow::Result<()>;
    fn get_children(&self, parent_id: &Uuid) -> anyhow::Result<Vec<&Block>>;
}

#[derive(Debug)]
pub struct DefaultBlockEditor {
    blocks: Vec<Block>,
}

impl DefaultBlockEditor {
    pub fn new() -> Self {
        Self {
            blocks: Vec::new(),
        }
    }

    fn reindex_positions(&mut self, note_id: &Uuid) {
        let mut note_blocks: Vec<&mut Block> = self.blocks
            .iter_mut()
            .filter(|b| &b.note_id == note_id)
            .collect();
        note_blocks.sort_by(|a, b| a.position.cmp(&b.position));
        for (i, block) in note_blocks.iter_mut().enumerate() {
            block.position = i;
        }
    }
}

impl Default for DefaultBlockEditor {
    fn default() -> Self {
        Self::new()
    }
}

impl BlockEditor for DefaultBlockEditor {
    #[instrument]
    fn create_block(&mut self, note_id: Uuid, block_type: BlockType, content: String, position: usize) -> anyhow::Result<Block> {
        for block in self.blocks.iter_mut().filter(|b| b.note_id == note_id && b.position >= position) {
            block.position += 1;
        }
        let block = Block::new(note_id, block_type, content, position);
        self.blocks.push(block.clone());
        Ok(block)
    }

    fn get_block(&self, id: &Uuid) -> anyhow::Result<Option<Block>> {
        Ok(self.blocks.iter().find(|b| &b.id == id).cloned())
    }

    fn update_block(&mut self, id: &Uuid, content: String) -> anyhow::Result<()> {
        let block = self.blocks.iter_mut().find(|b| &b.id == id)
            .ok_or_else(|| anyhow::anyhow!("Block not found"))?;
        block.content = content;
        block.updated_at = Utc::now();
        Ok(())
    }

    #[instrument]
    fn delete_block(&mut self, id: &Uuid) -> anyhow::Result<()> {
        let block = self.blocks.iter().find(|b| &b.id == id)
            .ok_or_else(|| anyhow::anyhow!("Block not found"))?;
        let note_id = block.note_id;
        let pos = block.position;
        self.blocks.retain(|b| &b.id != id);
        for block in self.blocks.iter_mut().filter(|b| b.note_id == note_id && b.position > pos) {
            block.position -= 1;
        }
        Ok(())
    }

    fn move_block(&mut self, id: &Uuid, new_position: usize) -> anyhow::Result<()> {
        let block = self.blocks.iter().find(|b| &b.id == id)
            .ok_or_else(|| anyhow::anyhow!("Block not found"))?;
        let note_id = block.note_id;
        let old_position = block.position;

        if old_position == new_position {
            return Ok(());
        }

        if new_position > old_position {
            for b in self.blocks.iter_mut().filter(|b| b.note_id == note_id && b.position > old_position && b.position <= new_position) {
                b.position -= 1;
            }
        } else {
            for b in self.blocks.iter_mut().filter(|b| b.note_id == note_id && b.position >= new_position && b.position < old_position) {
                b.position += 1;
            }
        }

        let block = self
            .blocks
            .iter_mut()
            .find(|b| &b.id == id)
            .expect("block existence verified earlier in move_block");
        block.position = new_position;
        block.updated_at = Utc::now();
        Ok(())
    }

    fn list_blocks(&mut self, note_id: &Uuid, offset: Option<usize>, limit: Option<usize>) -> anyhow::Result<Vec<Block>> {
        self.reindex_positions(note_id);
        let mut blocks: Vec<Block> = self.blocks.iter()
            .filter(|b| b.note_id == *note_id)
            .cloned()
            .collect();
        blocks.sort_by_key(|b| b.position);
        let start = offset.unwrap_or(0);
        if start >= blocks.len() {
            return Ok(Vec::new());
        }
        let end = match limit {
            Some(lim) => (start + lim).min(blocks.len()),
            None => blocks.len(),
        };
        Ok(blocks[start..end].to_vec())
    }

    fn list_blocks_paged(&mut self, note_id: &Uuid, page: usize, page_size: usize) -> anyhow::Result<Vec<Block>> {
        let offset = page * page_size;
        self.list_blocks(note_id, Some(offset), Some(page_size))
    }

    #[instrument]
    fn parse_markdown(&mut self, content: &str, note_id: Uuid) -> anyhow::Result<Vec<Block>> {
        let parsed = MarkdownParser::parse(content);
        let mut blocks = Vec::new();
        for (position, item) in parsed.into_iter().enumerate() {
            let block = Block::new(note_id, item.block_type, item.content, position);
            blocks.push(block.clone());
            self.blocks.push(block);
        }
        Ok(blocks)
    }

    fn insert_block(&mut self, _parent_id: Option<&Uuid>, index: usize, block: Block) -> anyhow::Result<()> {
        for b in self.blocks.iter_mut().filter(|b| b.note_id == block.note_id && b.position >= index) {
            b.position += 1;
        }
        let mut block = block;
        block.position = index;
        self.blocks.push(block);
        Ok(())
    }

    fn remove_block(&mut self, block_id: &Uuid) -> anyhow::Result<Block> {
        let block = self.blocks.iter().find(|b| &b.id == block_id)
            .ok_or_else(|| anyhow::anyhow!("Block not found"))?;
        let removed = block.clone();
        self.delete_block(block_id)?;
        Ok(removed)
    }

    fn update_block_content(&mut self, block_id: &Uuid, content: String) -> anyhow::Result<()> {
        self.update_block(block_id, content)
    }

    fn move_block_to(&mut self, block_id: &Uuid, _new_parent_id: Option<&Uuid>, new_index: usize) -> anyhow::Result<()> {
        self.move_block(block_id, new_index)
    }

    fn get_children(&self, parent_id: &Uuid) -> anyhow::Result<Vec<&Block>> {
        Ok(self.blocks.iter().filter(|b| &b.note_id == parent_id).collect())
    }
}

pub(crate) struct ParsedBlock {
    block_type: BlockType,
    content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TokenType {
    Keyword,
    String,
    Comment,
    Number,
    Function,
    Operator,
    Punctuation,
    Identifier,
    Whitespace,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyntaxToken {
    pub token_type: TokenType,
    pub text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyntaxLine {
    pub tokens: Vec<SyntaxToken>,
}

pub struct CodeBlockRenderer;

impl CodeBlockRenderer {
    pub fn highlight(code: &str, language: Option<&str>) -> Vec<SyntaxLine> {
        let keywords = Self::get_keywords(language);
        code.lines().map(|line| Self::tokenize_line(line, &keywords)).collect()
    }

    fn get_keywords(language: Option<&str>) -> Vec<&'static str> {
        match language.map(|l| l.to_lowercase()).as_deref() {
            Some("rust") => vec![
                "fn", "let", "mut", "if", "else", "match", "loop", "while", "for", "in",
                "return", "struct", "enum", "impl", "trait", "pub", "use", "mod", "crate",
                "self", "super", "where", "type", "const", "static", "ref", "move", "async",
                "await", "dyn", "as", "break", "continue", "true", "false",
            ],
            Some("python") => vec![
                "def", "class", "if", "elif", "else", "for", "while", "return", "import",
                "from", "as", "try", "except", "finally", "with", "yield", "lambda", "pass",
                "raise", "and", "or", "not", "in", "is", "True", "False", "None", "global",
                "nonlocal", "assert", "del", "break", "continue",
            ],
            Some("javascript") | Some("js") | Some("typescript") | Some("ts") => vec![
                "function", "var", "let", "const", "if", "else", "for", "while", "do",
                "switch", "case", "break", "continue", "return", "class", "extends", "new",
                "this", "super", "import", "export", "from", "default", "try", "catch",
                "finally", "throw", "typeof", "instanceof", "in", "of", "async", "await",
                "yield", "void", "delete", "true", "false", "null", "undefined",
            ],
            Some("java") => vec![
                "public", "private", "protected", "class", "interface", "extends",
                "implements", "static", "final", "void", "int", "long", "double", "float",
                "boolean", "char", "byte", "short", "if", "else", "for", "while", "do",
                "switch", "case", "break", "continue", "return", "new", "this", "super",
                "try", "catch", "finally", "throw", "throws", "import", "package",
                "abstract", "synchronized", "volatile", "native", "true", "false", "null",
            ],
            Some("go") => vec![
                "func", "var", "const", "type", "struct", "interface", "map", "chan", "go",
                "select", "case", "default", "if", "else", "for", "range", "switch", "break",
                "continue", "return", "defer", "fallthrough", "package", "import", "true",
                "false", "nil", "make", "new", "len", "cap", "append", "copy", "delete",
            ],
            Some("c") | Some("cpp") | Some("c++") => vec![
                "int", "long", "short", "float", "double", "char", "void", "bool", "auto",
                "const", "static", "extern", "register", "volatile", "inline", "if", "else",
                "for", "while", "do", "switch", "case", "break", "continue", "return",
                "struct", "union", "enum", "typedef", "class", "namespace", "using",
                "template", "virtual", "override", "public", "private", "protected", "new",
                "delete", "try", "catch", "throw", "true", "false", "nullptr", "NULL",
            ],
            _ => vec![],
        }
    }

    fn tokenize_line(line: &str, keywords: &[&str]) -> SyntaxLine {
        let mut tokens = Vec::new();
        let chars: Vec<char> = line.chars().collect();
        let mut i = 0;
        let is_python = keywords.contains(&"def");

        while i < chars.len() {
            if !is_python && chars[i] == '/' && i + 1 < chars.len() && chars[i + 1] == '/' {
                tokens.push(SyntaxToken {
                    token_type: TokenType::Comment,
                    text: chars[i..].iter().collect(),
                });
                break;
            }

            if is_python && chars[i] == '#' {
                tokens.push(SyntaxToken {
                    token_type: TokenType::Comment,
                    text: chars[i..].iter().collect(),
                });
                break;
            }

            if chars[i] == '"' || chars[i] == '\'' {
                let quote = chars[i];
                let mut end = i + 1;
                while end < chars.len() && chars[end] != quote {
                    if chars[end] == '\\' && end + 1 < chars.len() {
                        end += 2;
                    } else {
                        end += 1;
                    }
                }
                if end < chars.len() {
                    end += 1;
                }
                tokens.push(SyntaxToken {
                    token_type: TokenType::String,
                    text: chars[i..end].iter().collect(),
                });
                i = end;
                continue;
            }

            if chars[i].is_whitespace() {
                let mut end = i;
                while end < chars.len() && chars[end].is_whitespace() {
                    end += 1;
                }
                tokens.push(SyntaxToken {
                    token_type: TokenType::Whitespace,
                    text: chars[i..end].iter().collect(),
                });
                i = end;
                continue;
            }

            if chars[i].is_ascii_digit() {
                let mut end = i;
                while end < chars.len() && (chars[end].is_ascii_digit() || chars[end] == '.' || chars[end] == '_' || chars[end].is_ascii_hexdigit()) {
                    end += 1;
                }
                tokens.push(SyntaxToken {
                    token_type: TokenType::Number,
                    text: chars[i..end].iter().collect(),
                });
                i = end;
                continue;
            }

            if chars[i].is_alphabetic() || chars[i] == '_' {
                let mut end = i;
                while end < chars.len() && (chars[end].is_alphanumeric() || chars[end] == '_') {
                    end += 1;
                }
                let word: String = chars[i..end].iter().collect();
                let token_type = if keywords.contains(&word.as_str()) {
                    TokenType::Keyword
                } else if end < chars.len() && chars[end] == '(' {
                    TokenType::Function
                } else {
                    TokenType::Identifier
                };
                tokens.push(SyntaxToken {
                    token_type,
                    text: word,
                });
                i = end;
                continue;
            }

            let op_chars = ['+', '-', '*', '/', '%', '=', '<', '>', '!', '&', '|', '^', '~', '?', ':', '.'];
            if op_chars.contains(&chars[i]) {
                let mut end = i + 1;
                while end < chars.len() && op_chars.contains(&chars[end]) {
                    end += 1;
                }
                tokens.push(SyntaxToken {
                    token_type: TokenType::Operator,
                    text: chars[i..end].iter().collect(),
                });
                i = end;
                continue;
            }

            let punct_chars = ['(', ')', '{', '}', '[', ']', ',', ';'];
            if punct_chars.contains(&chars[i]) {
                tokens.push(SyntaxToken {
                    token_type: TokenType::Punctuation,
                    text: chars[i].to_string(),
                });
                i += 1;
                continue;
            }

            tokens.push(SyntaxToken {
                token_type: TokenType::Identifier,
                text: chars[i].to_string(),
            });
            i += 1;
        }

        SyntaxLine { tokens }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum LatexNodeType {
    DisplayMath,
    InlineMath,
    Command,
    Text,
    Superscript,
    Subscript,
    Fraction,
    SquareRoot,
    Group,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LatexNode {
    pub node_type: LatexNodeType,
    pub content: String,
    pub children: Vec<LatexNode>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenderedLatex {
    pub is_display: bool,
    pub root: LatexNode,
}

pub struct LatexRenderer;

impl LatexRenderer {
    pub fn render(latex: &str) -> RenderedLatex {
        let is_display = latex.trim().starts_with("$$") || latex.trim().starts_with("\\[");
        let content = Self::strip_delimiters(latex);
        let root = Self::parse_nodes(&content);
        RenderedLatex { is_display, root }
    }

    fn strip_delimiters(latex: &str) -> String {
        let trimmed = latex.trim();
        if trimmed.starts_with("$$") && trimmed.ends_with("$$") && trimmed.len() > 4 {
            trimmed[2..trimmed.len() - 2].trim().to_string()
        } else if trimmed.starts_with("\\[") && trimmed.ends_with("\\]") && trimmed.len() > 4 {
            trimmed[2..trimmed.len() - 2].trim().to_string()
        } else if trimmed.starts_with("\\(") && trimmed.ends_with("\\)") && trimmed.len() > 4 {
            trimmed[2..trimmed.len() - 2].trim().to_string()
        } else if trimmed.starts_with('$') && trimmed.ends_with('$') && trimmed.len() > 2 {
            trimmed[1..trimmed.len() - 1].trim().to_string()
        } else {
            trimmed.to_string()
        }
    }

    fn parse_nodes(content: &str) -> LatexNode {
        let mut children = Vec::new();
        let chars: Vec<char> = content.chars().collect();
        let mut i = 0;
        let mut text_buf = String::new();

        while i < chars.len() {
            if chars[i] == '\\' && i + 1 < chars.len() {
                if !text_buf.is_empty() {
                    children.push(LatexNode {
                        node_type: LatexNodeType::Text,
                        content: std::mem::take(&mut text_buf),
                        children: Vec::new(),
                    });
                }
                let mut cmd_end = i + 1;
                while cmd_end < chars.len() && chars[cmd_end].is_alphabetic() {
                    cmd_end += 1;
                }
                let cmd: String = chars[i..cmd_end].iter().collect();
                let node_type = match cmd.as_str() {
                    "\\frac" => LatexNodeType::Fraction,
                    "\\sqrt" => LatexNodeType::SquareRoot,
                    "\\text" => LatexNodeType::Text,
                    _ => LatexNodeType::Command,
                };
                children.push(LatexNode {
                    node_type,
                    content: cmd,
                    children: Vec::new(),
                });
                i = cmd_end;
                continue;
            }
            if chars[i] == '^' {
                if !text_buf.is_empty() {
                    children.push(LatexNode {
                        node_type: LatexNodeType::Text,
                        content: std::mem::take(&mut text_buf),
                        children: Vec::new(),
                    });
                }
                children.push(LatexNode {
                    node_type: LatexNodeType::Superscript,
                    content: "^".to_string(),
                    children: Vec::new(),
                });
                i += 1;
                continue;
            }
            if chars[i] == '_' {
                if !text_buf.is_empty() {
                    children.push(LatexNode {
                        node_type: LatexNodeType::Text,
                        content: std::mem::take(&mut text_buf),
                        children: Vec::new(),
                    });
                }
                children.push(LatexNode {
                    node_type: LatexNodeType::Subscript,
                    content: "_".to_string(),
                    children: Vec::new(),
                });
                i += 1;
                continue;
            }
            if chars[i] == '{' {
                if !text_buf.is_empty() {
                    children.push(LatexNode {
                        node_type: LatexNodeType::Text,
                        content: std::mem::take(&mut text_buf),
                        children: Vec::new(),
                    });
                }
                let mut depth = 1;
                let mut end = i + 1;
                while end < chars.len() && depth > 0 {
                    if chars[end] == '{' {
                        depth += 1;
                    }
                    if chars[end] == '}' {
                        depth -= 1;
                    }
                    end += 1;
                }
                let group_content: String = chars[i + 1..end.saturating_sub(1)].iter().collect();
                children.push(LatexNode {
                    node_type: LatexNodeType::Group,
                    content: group_content,
                    children: Vec::new(),
                });
                i = end;
                continue;
            }
            text_buf.push(chars[i]);
            i += 1;
        }

        if !text_buf.is_empty() {
            children.push(LatexNode {
                node_type: LatexNodeType::Text,
                content: text_buf,
                children: Vec::new(),
            });
        }

        LatexNode {
            node_type: if content.contains('\\') {
                LatexNodeType::DisplayMath
            } else {
                LatexNodeType::InlineMath
            },
            content: content.to_string(),
            children,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TableAlignment {
    Left,
    Center,
    Right,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TableData {
    pub headers: Vec<String>,
    pub rows: Vec<Vec<String>>,
    pub alignments: Vec<TableAlignment>,
}

pub struct TableParser;

impl TableParser {
    pub fn parse(markdown: &str) -> Option<TableData> {
        let lines: Vec<&str> = markdown.lines().collect();
        if lines.len() < 2 {
            return None;
        }

        let headers = Self::parse_row(lines[0])?;
        let alignments = Self::parse_alignments(lines[1])?;

        if alignments.len() != headers.len() {
            return None;
        }

        let mut rows = Vec::new();
        for line in lines.iter().skip(2) {
            if let Some(row) = Self::parse_row(line) {
                let mut padded_row = row;
                while padded_row.len() < headers.len() {
                    padded_row.push(String::new());
                }
                rows.push(padded_row);
            }
        }

        Some(TableData { headers, rows, alignments })
    }

    fn parse_row(line: &str) -> Option<Vec<String>> {
        let trimmed = line.trim();
        if !trimmed.starts_with('|') || !trimmed.ends_with('|') {
            return None;
        }
        let inner = &trimmed[1..trimmed.len() - 1];
        let cells: Vec<String> = inner.split('|').map(|c| c.trim().to_string()).collect();
        Some(cells)
    }

    fn parse_alignments(line: &str) -> Option<Vec<TableAlignment>> {
        let trimmed = line.trim();
        if !trimmed.starts_with('|') || !trimmed.ends_with('|') {
            return None;
        }
        let inner = &trimmed[1..trimmed.len() - 1];
        let cells: Vec<&str> = inner.split('|').map(|c| c.trim()).collect();
        let alignments: Vec<TableAlignment> = cells.iter().map(|c| {
            let c = c.trim();
            if c.starts_with(':') && c.ends_with(':') {
                TableAlignment::Center
            } else if c.ends_with(':') {
                TableAlignment::Right
            } else {
                TableAlignment::Left
            }
        }).collect();
        Some(alignments)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskItem {
    pub text: String,
    pub checked: bool,
    pub indent: usize,
}

pub struct TaskListParser;

impl TaskListParser {
    pub fn parse(content: &str) -> Vec<TaskItem> {
        content.lines().filter_map(|line| {
            let trimmed = line.trim_start();
            let indent = line.len() - trimmed.len();
            let indent_level = indent / 2;

            if trimmed.starts_with("- [x] ") {
                Some(TaskItem {
                    text: trimmed[6..].to_string(),
                    checked: true,
                    indent: indent_level,
                })
            } else if trimmed.starts_with("- [ ] ") {
                Some(TaskItem {
                    text: trimmed[6..].to_string(),
                    checked: false,
                    indent: indent_level,
                })
            } else if trimmed.starts_with("* [x] ") {
                Some(TaskItem {
                    text: trimmed[6..].to_string(),
                    checked: true,
                    indent: indent_level,
                })
            } else if trimmed.starts_with("* [ ] ") {
                Some(TaskItem {
                    text: trimmed[6..].to_string(),
                    checked: false,
                    indent: indent_level,
                })
            } else {
                None
            }
        }).collect()
    }
}

pub struct MarkdownParser;

impl MarkdownParser {
    #[instrument]
    pub(crate) fn parse(content: &str) -> Vec<ParsedBlock> {
        let mut blocks = Vec::new();
        let mut lines = content.lines().peekable();
        let mut current_lines: Vec<String> = Vec::new();

        let flush_paragraph = |lines: &mut Vec<String>, blocks: &mut Vec<ParsedBlock>| {
            if !lines.is_empty() {
                let text = lines.join("\n");
                if !text.trim().is_empty() {
                    blocks.push(ParsedBlock {
                        block_type: BlockType::Paragraph,
                        content: text.trim().to_string(),
                    });
                }
                lines.clear();
            }
        };

        while let Some(line) = lines.next() {
            if line.starts_with("```") {
                flush_paragraph(&mut current_lines, &mut blocks);
                let language = if line.len() > 3 {
                    Some(line[3..].trim().to_string())
                } else {
                    None
                };
                let mut code_lines = Vec::new();
                while let Some(code_line) = lines.next() {
                    if code_line.starts_with("```") {
                        break;
                    }
                    code_lines.push(code_line.to_string());
                }
                blocks.push(ParsedBlock {
                    block_type: BlockType::CodeBlock { language },
                    content: code_lines.join("\n"),
                });
            } else if line.starts_with("# ") {
                flush_paragraph(&mut current_lines, &mut blocks);
                blocks.push(ParsedBlock {
                    block_type: BlockType::Heading { level: 1 },
                    content: line[2..].to_string(),
                });
            } else if line.starts_with("## ") {
                flush_paragraph(&mut current_lines, &mut blocks);
                blocks.push(ParsedBlock {
                    block_type: BlockType::Heading { level: 2 },
                    content: line[3..].to_string(),
                });
            } else if line.starts_with("### ") {
                flush_paragraph(&mut current_lines, &mut blocks);
                blocks.push(ParsedBlock {
                    block_type: BlockType::Heading { level: 3 },
                    content: line[4..].to_string(),
                });
            } else if line.starts_with("#### ") {
                flush_paragraph(&mut current_lines, &mut blocks);
                blocks.push(ParsedBlock {
                    block_type: BlockType::Heading { level: 4 },
                    content: line[5..].to_string(),
                });
            } else if line.starts_with("##### ") {
                flush_paragraph(&mut current_lines, &mut blocks);
                blocks.push(ParsedBlock {
                    block_type: BlockType::Heading { level: 5 },
                    content: line[6..].to_string(),
                });
            } else if line.starts_with("###### ") {
                flush_paragraph(&mut current_lines, &mut blocks);
                blocks.push(ParsedBlock {
                    block_type: BlockType::Heading { level: 6 },
                    content: line[7..].to_string(),
                });
            } else if line.starts_with("> ") {
                flush_paragraph(&mut current_lines, &mut blocks);
                let mut quote_lines = vec![line[2..].to_string()];
                while let Some(next) = lines.peek() {
                    if next.starts_with("> ") {
                        quote_lines.push(
                            lines
                                .next()
                                .expect("peek confirmed element exists")[2..]
                                .to_string(),
                        );
                    } else {
                        break;
                    }
                }
                blocks.push(ParsedBlock {
                    block_type: BlockType::Quote,
                    content: quote_lines.join("\n"),
                });
            } else if line.trim_start().starts_with("- [") || line.trim_start().starts_with("* [") {
                flush_paragraph(&mut current_lines, &mut blocks);
                let mut task_lines = vec![line.to_string()];
                while let Some(next) = lines.peek() {
                    let next_trimmed = next.trim_start();
                    if next_trimmed.starts_with("- [") || next_trimmed.starts_with("* [") {
                        task_lines.push(
                            lines
                                .next()
                                .expect("peek confirmed element exists")
                                .to_string(),
                        );
                    } else {
                        break;
                    }
                }
                blocks.push(ParsedBlock {
                    block_type: BlockType::TaskListBlock,
                    content: task_lines.join("\n"),
                });
            } else if line.trim().starts_with('|') {
                flush_paragraph(&mut current_lines, &mut blocks);
                let mut table_lines = vec![line.to_string()];
                while let Some(next) = lines.peek() {
                    if next.trim().starts_with('|') {
                        table_lines.push(
                            lines
                                .next()
                                .expect("peek confirmed element exists")
                                .to_string(),
                        );
                    } else {
                        break;
                    }
                }
                if let Some(data) = TableParser::parse(&table_lines.join("\n")) {
                    blocks.push(ParsedBlock {
                        block_type: BlockType::TableBlock { rows: data.rows.len(), cols: data.headers.len() },
                        content: table_lines.join("\n"),
                    });
                } else {
                    blocks.push(ParsedBlock {
                        block_type: BlockType::Paragraph,
                        content: table_lines.join("\n"),
                    });
                }
            } else if line.trim() == ":::audio" {
                flush_paragraph(&mut current_lines, &mut blocks);
                let mut audio_lines = Vec::new();
                while let Some(next) = lines.next() {
                    if next.trim() == ":::" {
                        break;
                    }
                    audio_lines.push(next.to_string());
                }
                let json_content = audio_lines.join("\n");
                let block_type = if let Ok(value) =
                    serde_json::from_str::<serde_json::Value>(&json_content)
                {
                    BlockType::Audio {
                        url: value
                            .get("url")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string(),
                        duration_ms: value
                            .get("duration_ms")
                            .and_then(|v| v.as_u64())
                            .unwrap_or(0),
                        transcript: value
                            .get("transcript")
                            .and_then(|v| v.as_str())
                            .map(|s| s.to_string()),
                    }
                } else {
                    BlockType::Audio {
                        url: String::new(),
                        duration_ms: 0,
                        transcript: None,
                    }
                };
                blocks.push(ParsedBlock {
                    block_type,
                    content: json_content,
                });
            } else if line.starts_with("$$") {
                flush_paragraph(&mut current_lines, &mut blocks);
                let mut latex_lines = vec![line.to_string()];
                if !line.trim().ends_with("$$") || line.trim() == "$$" {
                    while let Some(next) = lines.next() {
                        latex_lines.push(next.to_string());
                        if next.trim().ends_with("$$") {
                            break;
                        }
                    }
                }
                blocks.push(ParsedBlock {
                    block_type: BlockType::LatexBlock,
                    content: latex_lines.join("\n"),
                });
            } else if line.starts_with("- ") || line.starts_with("* ") {
                flush_paragraph(&mut current_lines, &mut blocks);
                let mut list_lines = vec![line[2..].to_string()];
                while let Some(next) = lines.peek() {
                    if next.starts_with("- ") || next.starts_with("* ") {
                        list_lines.push(
                            lines
                                .next()
                                .expect("peek confirmed element exists")[2..]
                                .to_string(),
                        );
                    } else {
                        break;
                    }
                }
                blocks.push(ParsedBlock {
                    block_type: BlockType::List { ordered: false },
                    content: list_lines.join("\n"),
                });
            } else if line.trim().starts_with(|c: char| c.is_ascii_digit()) && line.trim().contains(". ") {
                flush_paragraph(&mut current_lines, &mut blocks);
                let trimmed = line.trim();
                let dot_pos = trimmed.find(". ").unwrap_or(0);
                let item_content = if dot_pos + 2 < trimmed.len() {
                    trimmed[dot_pos + 2..].to_string()
                } else {
                    String::new()
                };
                let mut list_lines = vec![item_content];
                while let Some(next) = lines.peek() {
                    let next_trimmed = next.trim();
                    if next_trimmed.starts_with(|c: char| c.is_ascii_digit()) && next_trimmed.contains(". ") {
                        let np = next_trimmed.find(". ").unwrap_or(0);
                        let ic = if np + 2 < next_trimmed.len() {
                            next_trimmed[np + 2..].to_string()
                        } else {
                            String::new()
                        };
                        list_lines.push(ic);
                        let _ = lines.next();
                    } else {
                        break;
                    }
                }
                blocks.push(ParsedBlock {
                    block_type: BlockType::List { ordered: true },
                    content: list_lines.join("\n"),
                });
            } else if line.trim().is_empty() {
                flush_paragraph(&mut current_lines, &mut blocks);
            } else {
                current_lines.push(line.to_string());
            }
        }

        flush_paragraph(&mut current_lines, &mut blocks);
        blocks
    }
}

#[cfg(test)]
// 测试约定：测试中使用 `.unwrap()` 是 Rust 惯用写法，由 `#[cfg(test)]` 门控，
// 不会编译进生产二进制。生产代码使用 `?` 运算符传播错误。
mod tests {
    use super::*;

    #[test]
    fn test_parse_heading() {
        let blocks = MarkdownParser::parse("# Hello World");
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].block_type, BlockType::Heading { level: 1 });
        assert_eq!(blocks[0].content, "Hello World");
    }

    #[test]
    fn test_parse_paragraph() {
        let blocks = MarkdownParser::parse("Just a paragraph");
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].block_type, BlockType::Paragraph);
        assert_eq!(blocks[0].content, "Just a paragraph");
    }

    #[test]
    fn test_parse_code_block() {
        let blocks = MarkdownParser::parse("```rust\nfn main() {}\n```");
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].block_type, BlockType::CodeBlock { language: Some("rust".to_string()) });
        assert_eq!(blocks[0].content, "fn main() {}");
    }

    #[test]
    fn test_parse_list() {
        let blocks = MarkdownParser::parse("- item1\n- item2\n- item3");
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].block_type, BlockType::List { ordered: false });
        assert_eq!(blocks[0].content, "item1\nitem2\nitem3");
    }

    #[test]
    fn test_parse_quote() {
        let blocks = MarkdownParser::parse("> quote line 1\n> quote line 2");
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].block_type, BlockType::Quote);
        assert_eq!(blocks[0].content, "quote line 1\nquote line 2");
    }

    #[test]
    fn test_parse_task_list() {
        let blocks = MarkdownParser::parse("- [ ] todo1\n- [x] todo2");
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].block_type, BlockType::TaskListBlock);
        let items = TaskListParser::parse(&blocks[0].content);
        assert_eq!(items.len(), 2);
        assert!(!items[0].checked);
        assert!(items[1].checked);
    }

    #[test]
    fn test_parse_table() {
        let md = "| H1 | H2 |\n| --- | --- |\n| A | B |";
        let blocks = MarkdownParser::parse(md);
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].block_type, BlockType::TableBlock { rows: 1, cols: 2 });
        let data = TableParser::parse(&blocks[0].content).unwrap();
        assert_eq!(data.headers, vec!["H1", "H2"]);
        assert_eq!(data.rows, vec![vec!["A", "B"]]);
    }

    #[test]
    fn test_parse_latex() {
        let blocks = MarkdownParser::parse("$$\nx^2 + y^2 = z^2\n$$");
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].block_type, BlockType::LatexBlock);
    }

    #[test]
    fn test_code_block_renderer() {
        let lines = CodeBlockRenderer::highlight("fn main() {}", Some("rust"));
        assert_eq!(lines.len(), 1);
        assert!(lines[0].tokens.iter().any(|t| t.token_type == TokenType::Keyword && t.text == "fn"));
    }

    #[test]
    fn test_latex_renderer() {
        let rendered = LatexRenderer::render("$$x^2 + y^2$$");
        assert!(rendered.is_display);
        assert!(!rendered.root.children.is_empty());
    }

    #[test]
    fn test_table_parser() {
        let md = "| Name | Age |\n| :--- | ---: |\n| Alice | 30 |";
        let data = TableParser::parse(md).unwrap();
        assert_eq!(data.headers, vec!["Name", "Age"]);
        assert_eq!(data.alignments, vec![TableAlignment::Left, TableAlignment::Right]);
        assert_eq!(data.rows, vec![vec!["Alice", "30"]]);
    }

    #[test]
    fn test_task_list_parser() {
        let content = "- [ ] pending\n- [x] done\n  - [ ] sub task";
        let items = TaskListParser::parse(content);
        assert_eq!(items.len(), 3);
        assert!(!items[0].checked);
        assert!(items[1].checked);
        assert_eq!(items[2].indent, 1);
    }

    #[test]
    fn test_create_and_get_block() {
        let mut editor = DefaultBlockEditor::new();
        let note_id = Uuid::new_v4();
        let block = editor.create_block(note_id, BlockType::Paragraph, "Hello".to_string(), 0).unwrap();
        assert_eq!(block.content, "Hello");
        let found = editor.get_block(&block.id).unwrap().unwrap();
        assert_eq!(found.content, "Hello");
    }

    #[test]
    fn test_update_block() {
        let mut editor = DefaultBlockEditor::new();
        let note_id = Uuid::new_v4();
        let block = editor.create_block(note_id, BlockType::Paragraph, "Hello".to_string(), 0).unwrap();
        editor.update_block(&block.id, "World".to_string()).unwrap();
        let found = editor.get_block(&block.id).unwrap().unwrap();
        assert_eq!(found.content, "World");
    }

    #[test]
    fn test_delete_block() {
        let mut editor = DefaultBlockEditor::new();
        let note_id = Uuid::new_v4();
        let block = editor.create_block(note_id, BlockType::Paragraph, "Hello".to_string(), 0).unwrap();
        editor.delete_block(&block.id).unwrap();
        let found = editor.get_block(&block.id).unwrap();
        assert!(found.is_none());
    }

    #[test]
    fn test_move_block() {
        let mut editor = DefaultBlockEditor::new();
        let note_id = Uuid::new_v4();
        let b1 = editor.create_block(note_id, BlockType::Paragraph, "First".to_string(), 0).unwrap();
        let _b2 = editor.create_block(note_id, BlockType::Paragraph, "Second".to_string(), 1).unwrap();
        editor.move_block(&b1.id, 1).unwrap();
        let blocks = editor.list_blocks(&note_id, None, None).unwrap();
        assert_eq!(blocks[0].content, "Second");
        assert_eq!(blocks[1].content, "First");
    }

    #[test]
    fn test_parse_markdown() {
        let mut editor = DefaultBlockEditor::new();
        let note_id = Uuid::new_v4();
        let md = "# Title\n\nParagraph text\n\n- item1\n- item2";
        let blocks = editor.parse_markdown(md, note_id).unwrap();
        assert_eq!(blocks.len(), 3);
        assert_eq!(blocks[0].block_type, BlockType::Heading { level: 1 });
        assert_eq!(blocks[1].block_type, BlockType::Paragraph);
        assert_eq!(blocks[2].block_type, BlockType::List { ordered: false });
    }
}
