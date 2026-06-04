//! 笔记导入/导出格式支持 —— Markdown / HTML / Obsidian / Siyuan 等
//!
//! ## 借鉴的开源项目
//! - **pandoc** ([官网](https://pandoc.org/)): 借鉴其"通用文档模型 + 多种 reader/writer"的多格式转换设计
//!   - 定义 `FormatImporter` / `FormatExporter` 两类 trait，模仿 pandoc Reader/Writer 的多态模型
//!   - `ImportFormat` / `ExportFormat` 枚举对应 pandoc 的 input/output format 概念
//!   - 内部使用中间 `NoteData` 数据结构（标题/内容/标签/附件/时间戳），对应 pandoc 的 `Pandoc` AST
//! - **pulldown-cmark** ([GitHub](https://github.com/raphlinus/pulldown-cmark)): 借鉴其 Markdown 编解码思路
//!   - YAML / TOML Front Matter 解析（`parse_front_matter`）参照 pulldown-cmark 的 metadata block 解析
//!   - 标题 / 列表 / 引用 / 代码块等基础行级结构解析（`HtmlExporter::markdown_to_html`）借鉴
//!     pulldown-cmark 的事件驱动解析思路，本实现简化为"按行状态机"版本
//!   - `extract_attachments` 使用与 CommonMark 兼容的 `![alt](url)` 图片语法
//!
//! ## 实现说明
//! - `MarkdownImporter` / `ObsidianImporter` 是两种典型 Markdown 源：前者只识别 front matter，
//!   后者还会将 `[[wikilink]]` 转换为标准 Markdown 链接。
//! - `MarkdownExporter` / `HtmlExporter` 是输出端实现：导出时按 `folder_path` 重建目录结构。
//! - 借鉴思源 / Obsidian 等笔记生态的目录约定，附件统一放在 `attachments/` 子目录中。
//! - `parse_yaml_simple` 是极简的 YAML 解析实现（仅支持 `key: value` 与 `[a, b, c]` 数组），
//!   避免引入完整 YAML 依赖；在生产环境可替换为 `serde_yaml`。

use devnote_observe::{instrument, warn};
use std::fs;
use std::path::Path;
use serde::{Deserialize, Serialize};
use chrono::{DateTime, NaiveDate, TimeZone, Utc};
use anyhow::Result;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NoteData {
    pub title: String,
    pub content: String,
    pub folder_path: String,
    pub tags: Vec<String>,
    pub attachments: Vec<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum ImportFormat {
    Markdown,
    Html,
    Joplin,
    Obsidian,
    Siyuan,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum ExportFormat {
    Markdown,
    Html,
    Pdf,
}

pub trait FormatImporter: Send + Sync {
    fn import(&self, source_path: &Path, format: ImportFormat) -> Result<Vec<NoteData>>;
}

pub trait FormatExporter: Send + Sync {
    fn export(&self, notes: &[NoteData], target_path: &Path, format: ExportFormat) -> Result<()>;
}

fn parse_date(s: &str) -> Option<DateTime<Utc>> {
    if let Ok(dt) = DateTime::parse_from_rfc3339(s) {
        return Some(dt.to_utc());
    }
    if let Ok(date) = NaiveDate::parse_from_str(s, "%Y-%m-%d") {
        let dt = date.and_hms_opt(0, 0, 0)?;
        return Some(Utc.from_utc_datetime(&dt));
    }
    if let Ok(date) = NaiveDate::parse_from_str(s, "%Y/%m/%d") {
        let dt = date.and_hms_opt(0, 0, 0)?;
        return Some(Utc.from_utc_datetime(&dt));
    }
    None
}

fn parse_front_matter(content: &str) -> (Option<serde_json::Value>, &str) {
    if !content.starts_with("---") {
        return (None, content);
    }
    let rest = &content[3..];
    if let Some(end) = rest.find("\n---") {
        let yaml_content = &rest[..end];
        let body = &rest[end + 4..];
        let metadata = parse_yaml_simple(yaml_content);
        (Some(metadata), body.trim_start_matches('\n'))
    } else {
        (None, content)
    }
}

fn parse_yaml_simple(yaml: &str) -> serde_json::Value {
    let mut map = serde_json::Map::new();
    for line in yaml.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if let Some((key, value)) = line.split_once(':') {
            let key = key.trim().to_string();
            let value = value.trim();
            if value.is_empty() {
                continue;
            }
            if value.starts_with('[') && value.ends_with(']') {
                let items: Vec<serde_json::Value> = value[1..value.len() - 1]
                    .split(',')
                    .map(|s| {
                        serde_json::Value::String(
                            s.trim().trim_matches('"').trim_matches('\'').to_string(),
                        )
                    })
                    .collect();
                map.insert(key, serde_json::Value::Array(items));
            } else {
                let v = value.trim_matches('"').trim_matches('\'').to_string();
                map.insert(key, serde_json::Value::String(v));
            }
        }
    }
    serde_json::Value::Object(map)
}

fn extract_title_from_content(content: &str) -> String {
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("# ") {
            return trimmed[2..].trim().to_string();
        }
    }
    String::new()
}

fn extract_attachments(content: &str) -> Vec<String> {
    let mut attachments = Vec::new();
    for line in content.lines() {
        let mut start = 0;
        while let Some(pos) = line[start..].find("![") {
            let remaining = &line[start + pos + 2..];
            if let Some(end) = remaining.find(']') {
                if let Some(_url_start) = remaining[end..].find('(') {
                    let url_part = &remaining[end + 1..];
                    if let Some(url_end) = url_part.find(')') {
                        let url = &url_part[..url_end];
                        if !url.starts_with("http") && !url.is_empty() {
                            attachments.push(url.to_string());
                        }
                    }
                }
            }
            start += pos + 2;
        }
    }
    attachments
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

#[derive(Debug)]
pub struct MarkdownImporter;

impl MarkdownImporter {
    pub fn new() -> Self {
        Self
    }

    fn parse_markdown_file(path: &Path, base_path: &Path) -> Result<NoteData> {
        let content = fs::read_to_string(path)?;
        let (front_matter, body) = parse_front_matter(&content);

        let title = front_matter
            .as_ref()
            .and_then(|fm| fm.get("title"))
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
            .unwrap_or_else(|| {
                let from_heading = extract_title_from_content(body);
                if from_heading.is_empty() {
                    path.file_stem()
                        .and_then(|s| s.to_str())
                        .unwrap_or("Untitled")
                        .to_string()
                } else {
                    from_heading
                }
            });

        let tags = front_matter
            .as_ref()
            .and_then(|fm| fm.get("tags"))
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(|s| s.to_string()))
                    .collect()
            })
            .unwrap_or_default();

        let created_at = front_matter
            .as_ref()
            .and_then(|fm| fm.get("date"))
            .or_else(|| front_matter.as_ref().and_then(|fm| fm.get("created")))
            .and_then(|v| v.as_str())
            .and_then(parse_date)
            .unwrap_or_else(Utc::now);

        let updated_at = front_matter
            .as_ref()
            .and_then(|fm| fm.get("updated"))
            .and_then(|v| v.as_str())
            .and_then(parse_date)
            .unwrap_or_else(|| created_at);

        let folder_path = path
            .parent()
            .and_then(|p| p.strip_prefix(base_path).ok())
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_default();

        let attachments = extract_attachments(body);

        Ok(NoteData {
            title,
            content: body.to_string(),
            folder_path,
            tags,
            attachments,
            created_at,
            updated_at,
        })
    }

    fn collect_markdown_files(dir: &Path, base_path: &Path) -> Result<Vec<NoteData>> {
        let mut notes = Vec::new();
        if dir.is_dir() {
            for entry in fs::read_dir(dir)? {
                let entry = entry?;
                let path = entry.path();
                if path.is_dir() {
                    notes.extend(Self::collect_markdown_files(&path, base_path)?);
                } else if path.extension().and_then(|e| e.to_str()) == Some("md") {
                    notes.push(Self::parse_markdown_file(&path, base_path)?);
                }
            }
        }
        Ok(notes)
    }
}

impl Default for MarkdownImporter {
    fn default() -> Self {
        Self::new()
    }
}

impl FormatImporter for MarkdownImporter {
    #[instrument]
    fn import(&self, source_path: &Path, _format: ImportFormat) -> Result<Vec<NoteData>> {
        if source_path.is_file() {
            let parent = source_path.parent().unwrap_or(source_path);
            Ok(vec![Self::parse_markdown_file(source_path, parent)?])
        } else {
            Self::collect_markdown_files(source_path, source_path)
        }
    }
}

pub struct ObsidianImporter;

impl ObsidianImporter {
    pub fn new() -> Self {
        Self
    }

    fn convert_wikilinks(content: &str) -> String {
        let mut result = content.to_string();
        loop {
            if let Some(start) = result.find("[[") {
                if let Some(end) = result[start + 2..].find("]]") {
                    let inner = &result[start + 2..start + 2 + end];
                    let (link, display) = if let Some(pipe) = inner.find('|') {
                        (&inner[..pipe], &inner[pipe + 1..])
                    } else {
                        (inner, inner)
                    };
                    let replacement = format!("[{}]({}.md)", display, link);
                    result.replace_range(start..start + 2 + end + 2, &replacement);
                } else {
                    break;
                }
            } else {
                break;
            }
        }
        result
    }

    fn collect_vault_files(dir: &Path, base_path: &Path) -> Result<Vec<NoteData>> {
        let mut notes = Vec::new();
        if dir.is_dir() {
            for entry in fs::read_dir(dir)? {
                let entry = entry?;
                let path = entry.path();
                let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
                if name == ".obsidian" {
                    continue;
                }
                if path.is_dir() {
                    notes.extend(Self::collect_vault_files(&path, base_path)?);
                } else if path.extension().and_then(|e| e.to_str()) == Some("md") {
                    let content = fs::read_to_string(&path)?;
                    let converted = Self::convert_wikilinks(&content);
                    let (front_matter, body) = parse_front_matter(&converted);

                    let title = front_matter
                        .as_ref()
                        .and_then(|fm| fm.get("title"))
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string())
                        .unwrap_or_else(|| {
                            let from_heading = extract_title_from_content(body);
                            if from_heading.is_empty() {
                                path.file_stem()
                                    .and_then(|s| s.to_str())
                                    .unwrap_or("Untitled")
                                    .to_string()
                            } else {
                                from_heading
                            }
                        });

                    let tags = front_matter
                        .as_ref()
                        .and_then(|fm| fm.get("tags"))
                        .and_then(|v| v.as_array())
                        .map(|arr| {
                            arr.iter()
                                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                                .collect()
                        })
                        .unwrap_or_default();

                    let folder_path = path
                        .parent()
                        .and_then(|p| p.strip_prefix(base_path).ok())
                        .map(|p| p.to_string_lossy().to_string())
                        .unwrap_or_default();

                    let attachments = extract_attachments(body);

                    let created_at = front_matter
                        .as_ref()
                        .and_then(|fm| fm.get("date"))
                        .or_else(|| front_matter.as_ref().and_then(|fm| fm.get("created")))
                        .and_then(|v| v.as_str())
                        .and_then(parse_date)
                        .unwrap_or_else(Utc::now);

                    let updated_at = front_matter
                        .as_ref()
                        .and_then(|fm| fm.get("updated"))
                        .and_then(|v| v.as_str())
                        .and_then(parse_date)
                        .unwrap_or_else(|| created_at);

                    notes.push(NoteData {
                        title,
                        content: body.to_string(),
                        folder_path,
                        tags,
                        attachments,
                        created_at,
                        updated_at,
                    });
                }
            }
        }
        Ok(notes)
    }
}

impl Default for ObsidianImporter {
    fn default() -> Self {
        Self::new()
    }
}

impl FormatImporter for ObsidianImporter {
    fn import(&self, source_path: &Path, _format: ImportFormat) -> Result<Vec<NoteData>> {
        Self::collect_vault_files(source_path, source_path)
    }
}

#[derive(Debug)]
pub struct MarkdownExporter;

impl MarkdownExporter {
    pub fn new() -> Self {
        Self
    }

    fn generate_front_matter(note: &NoteData) -> String {
        let mut front = String::from("---\n");
        front.push_str(&format!("title: \"{}\"\n", note.title));
        if !note.tags.is_empty() {
            front.push_str("tags:\n");
            for tag in &note.tags {
                front.push_str(&format!("  - \"{}\"\n", tag));
            }
        }
        front.push_str(&format!(
            "created: {}\n",
            note.created_at.format("%Y-%m-%dT%H:%M:%SZ")
        ));
        front.push_str(&format!(
            "updated: {}\n",
            note.updated_at.format("%Y-%m-%dT%H:%M:%SZ")
        ));
        front.push_str("---\n");
        front
    }
}

impl Default for MarkdownExporter {
    fn default() -> Self {
        Self::new()
    }
}

impl FormatExporter for MarkdownExporter {
    #[instrument]
    fn export(&self, notes: &[NoteData], target_path: &Path, _format: ExportFormat) -> Result<()> {
        fs::create_dir_all(target_path)?;
        for note in notes {
            let note_dir = if note.folder_path.is_empty() {
                target_path.to_path_buf()
            } else {
                target_path.join(&note.folder_path)
            };
            fs::create_dir_all(&note_dir)?;

            let front_matter = Self::generate_front_matter(note);
            let file_content = format!("{}{}", front_matter, note.content);

            let safe_filename = note.title.replace('/', "_").replace('\\', "_");
            let file_path = note_dir.join(format!("{}.md", safe_filename));
            fs::write(&file_path, file_content)?;

            for attachment in &note.attachments {
                let attachment_name = Path::new(attachment)
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or("attachment");
                let attachment_dir = note_dir.join("attachments");
                fs::create_dir_all(&attachment_dir)?;
                let src = Path::new(attachment);
                if src.exists() {
                    fs::copy(src, attachment_dir.join(attachment_name))?;
                }
            }
        }
        Ok(())
    }
}

pub struct HtmlExporter;

impl HtmlExporter {
    pub fn new() -> Self {
        Self
    }

    fn markdown_to_html(content: &str) -> String {
        let mut html = String::new();
        let mut in_code_block = false;
        let mut in_list = false;

        for line in content.lines() {
            if line.starts_with("```") {
                if in_code_block {
                    html.push_str("</code></pre>\n");
                    in_code_block = false;
                } else {
                    html.push_str("<pre><code>");
                    in_code_block = true;
                }
                continue;
            }
            if in_code_block {
                html.push_str(&html_escape(line));
                html.push('\n');
                continue;
            }
            if line.starts_with("# ") {
                if in_list {
                    html.push_str("</ul>\n");
                    in_list = false;
                }
                html.push_str(&format!("<h1>{}</h1>\n", &line[2..]));
            } else if line.starts_with("## ") {
                if in_list {
                    html.push_str("</ul>\n");
                    in_list = false;
                }
                html.push_str(&format!("<h2>{}</h2>\n", &line[3..]));
            } else if line.starts_with("### ") {
                if in_list {
                    html.push_str("</ul>\n");
                    in_list = false;
                }
                html.push_str(&format!("<h3>{}</h3>\n", &line[4..]));
            } else if line.starts_with("- ") || line.starts_with("* ") {
                if !in_list {
                    html.push_str("<ul>\n");
                    in_list = true;
                }
                html.push_str(&format!("<li>{}</li>\n", &line[2..]));
            } else if line.starts_with("> ") {
                if in_list {
                    html.push_str("</ul>\n");
                    in_list = false;
                }
                html.push_str(&format!(
                    "<blockquote>{}</blockquote>\n",
                    &line[2..]
                ));
            } else if !line.trim().is_empty() {
                if in_list {
                    html.push_str("</ul>\n");
                    in_list = false;
                }
                html.push_str(&format!("<p>{}</p>\n", line));
            }
        }
        if in_list {
            html.push_str("</ul>\n");
        }
        html
    }

    fn generate_html(note: &NoteData) -> String {
        let body = Self::markdown_to_html(&note.content);
        format!(
            r#"<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>{}</title>
<style>
body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; line-height: 1.6; color: #333; }}
h1, h2, h3 {{ color: #1a1a1a; }}
pre {{ background: #f5f5f5; padding: 16px; border-radius: 4px; overflow-x: auto; }}
code {{ font-family: 'SF Mono', Consolas, monospace; font-size: 14px; }}
blockquote {{ border-left: 4px solid #ddd; margin: 0; padding: 0 16px; color: #666; }}
img {{ max-width: 100%; }}
</style>
</head>
<body>
{}
</body>
</html>"#,
            html_escape(&note.title),
            body
        )
    }
}

impl Default for HtmlExporter {
    fn default() -> Self {
        Self::new()
    }
}

impl FormatExporter for HtmlExporter {
    fn export(&self, notes: &[NoteData], target_path: &Path, _format: ExportFormat) -> Result<()> {
        fs::create_dir_all(target_path)?;
        for note in notes {
            let note_dir = if note.folder_path.is_empty() {
                target_path.to_path_buf()
            } else {
                target_path.join(&note.folder_path)
            };
            fs::create_dir_all(&note_dir)?;

            let html = Self::generate_html(note);
            let safe_filename = note.title.replace('/', "_").replace('\\', "_");
            let file_path = note_dir.join(format!("{}.html", safe_filename));
            fs::write(&file_path, html)?;

            for attachment in &note.attachments {
                let attachment_name = Path::new(attachment)
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or("attachment");
                let attachment_dir = note_dir.join("attachments");
                fs::create_dir_all(&attachment_dir)?;
                let src = Path::new(attachment);
                if src.exists() {
                    fs::copy(src, attachment_dir.join(attachment_name))?;
                }
            }
        }
        Ok(())
    }
}
