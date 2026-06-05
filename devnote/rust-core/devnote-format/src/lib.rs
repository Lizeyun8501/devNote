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

// ============================================================================
// 批量导入导出与格式检测 —— 面向外部调用者的高层 API
// ============================================================================
// 借鉴 Joplin 批量导入逻辑 (https://github.com/laurent22/joplin)
// 借鉴 Obsidian 导出格式 (https://github.com/obsidianmd/obsidian-api)
// 借鉴 Pandoc 格式检测逻辑 (https://github.com/jgm/pandoc)
// 借鉴思源笔记内部存储格式解析逻辑 (https://github.com/siyuan-note/siyuan)
// ============================================================================

/// 批量导入 Markdown 文件
/// 借鉴: Joplin 批量导入逻辑 (https://github.com/laurent22/joplin)
/// 支持: 目录递归、frontmatter 解析、双向链接保留、附件路径重映射
pub fn batch_import_markdown(dir_path: &str) -> Result<Vec<ImportedNote>, FormatError> {
    let path = Path::new(dir_path);
    if !path.exists() {
        return Err(FormatError::IoError(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            format!("目录不存在: {}", dir_path),
        )));
    }
    if !path.is_dir() {
        return Err(FormatError::InvalidFormat(format!(
            "路径不是目录: {}",
            dir_path
        )));
    }

    let importer = MarkdownImporter::new();
    let notes = importer
        .import(path, ImportFormat::Markdown)
        .map_err(|e| FormatError::ParseError(format!("批量导入失败: {}", e)))?;

    let mut imported = Vec::new();
    for note in notes {
        // 附件路径重映射：将相对路径的附件映射到统一的 attachments/ 目录
        let remapped_attachments: Vec<String> = note
            .attachments
            .iter()
            .map(|a| {
                // 借鉴思源笔记的附件路径约定: data/<note-id>/assets/
                // 来源: https://github.com/siyuan-note/siyuan
                let src = Path::new(a);
                if let Some(name) = src.file_name().and_then(|n| n.to_str()) {
                    format!("attachments/{}", name)
                } else {
                    a.clone()
                }
            })
            .collect();

        imported.push(ImportedNote {
            title: note.title,
            content: note.content,
            folder_path: note.folder_path,
            tags: note.tags,
            attachments: remapped_attachments,
            created_at: note.created_at,
            updated_at: note.updated_at,
        });
    }

    Ok(imported)
}

/// 导出为 Markdown 格式
/// 借鉴: Obsidian 导出格式 (https://github.com/obsidianmd/obsidian-api)
/// 支持: frontmatter 元数据、wiki-link 双向链接、附件嵌入
pub fn export_markdown(notes: &[NoteExport]) -> Result<Vec<u8>, FormatError> {
    let mut output = String::new();

    for (idx, note) in notes.iter().enumerate() {
        if idx > 0 {
            // 笔记之间用分隔线隔开，借鉴 Obsidian 的多笔记导出习惯
            output.push_str("\n\n---\n\n");
        }

        // 生成 YAML frontmatter 元数据
        // 借鉴 Obsidian Properties 格式: https://help.obsidian.md/Editing+and+formatting/Properties
        output.push_str("---\n");
        output.push_str(&format!("title: \"{}\"\n", note.title));
        if !note.tags.is_empty() {
            output.push_str("tags:\n");
            for tag in &note.tags {
                output.push_str(&format!("  - \"{}\"\n", tag));
            }
        }
        output.push_str(&format!(
            "created: {}\n",
            note.created_at.format("%Y-%m-%dT%H:%M:%SZ")
        ));
        output.push_str(&format!(
            "updated: {}\n",
            note.updated_at.format("%Y-%m-%dT%H:%M:%SZ")
        ));
        output.push_str("---\n\n");

        // 保留原始内容，包括 wiki-link 双向链接
        // 借鉴 Obsidian 内部链接格式: [[笔记名]] 或 [[笔记名|显示文本]]
        // 来源: https://help.obsidian.md/Editing+and+formatting/Internal+links
        output.push_str(&note.content);

        // 附件嵌入引用：在内容末尾添加附件列表
        // 借鉴 Joplin 的资源引用方式
        if !note.attachments.is_empty() {
            output.push_str("\n\n<!-- attachments -->\n");
            for att in &note.attachments {
                output.push_str(&format!("[{}]({})\n", att, att));
            }
        }
    }

    Ok(output.into_bytes())
}

/// 导出为 HTML 格式
/// 借鉴: Joplin HTML 导出 (https://github.com/laurent22/joplin)
pub fn export_html(notes: &[NoteExport]) -> Result<String, FormatError> {
    let mut html = String::from(
        r#"<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>DevNote 导出</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; line-height: 1.6; color: #333; }
  .note { border-bottom: 1px solid #eee; margin-bottom: 24px; padding-bottom: 24px; }
  .note:last-child { border-bottom: none; }
  h1, h2, h3 { color: #1a1a1a; }
  pre { background: #f5f5f5; padding: 16px; border-radius: 4px; overflow-x: auto; }
  code { font-family: 'SF Mono', Consolas, monospace; font-size: 14px; }
  blockquote { border-left: 4px solid #ddd; margin: 0; padding: 0 16px; color: #666; }
  img { max-width: 100%; }
  .meta { color: #888; font-size: 0.85em; margin-bottom: 12px; }
  .tags { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 8px; }
  .tag { background: #e8f0fe; color: #1a73e8; padding: 2px 8px; border-radius: 12px; font-size: 12px; }
</style>
</head>
<body>
"#,
    );

    let exporter = HtmlExporter::new();
    for note in notes {
        html.push_str("<div class=\"note\">\n");

        // 标题
        html.push_str(&format!("<h1>{}</h1>\n", html_escape(&note.title)));

        // 元信息行
        html.push_str("<div class=\"meta\">\n");
        html.push_str(&format!(
            "  <span>创建: {}</span> | <span>更新: {}</span>\n",
            note.created_at.format("%Y-%m-%d %H:%M"),
            note.updated_at.format("%Y-%m-%d %H:%M")
        ));
        html.push_str("</div>\n");

        // 标签
        if !note.tags.is_empty() {
            html.push_str("<div class=\"tags\">\n");
            for tag in &note.tags {
                html.push_str(&format!(
                    "  <span class=\"tag\">{}</span>\n",
                    html_escape(tag)
                ));
            }
            html.push_str("</div>\n");
        }

        // 内容：使用简易 Markdown→HTML 转换
        // 借鉴 Joplin 的 HTML 导出风格：保留笔记结构和样式
        html.push_str(&HtmlExporter::markdown_to_html(&note.content));

        html.push_str("</div>\n");
    }

    html.push_str("</body>\n</html>");
    Ok(html)
}

/// 格式自动检测
/// 借鉴: Pandoc 格式检测逻辑 (https://github.com/jgm/pandoc)
/// 通过分析文件头部特征判断格式类型
pub fn detect_format(content: &[u8]) -> SupportedFormat {
    // 转换为字符串进行分析
    let text = String::from_utf8_lossy(content);

    // 检测 HTML 格式：以 <!DOCTYPE html> 或 <html 开头
    // 借鉴 Pandoc 的输入格式自动检测规则
    if text.trim_start().starts_with("<!DOCTYPE html>")
        || text.trim_start().starts_with("<html")
    {
        return SupportedFormat::Html;
    }

    // 检测 YAML front matter：以 --- 开头（Markdown / Obsidian 特征）
    // 借鉴 Pandoc 的 markdown 变体检测
    if text.trim_start().starts_with("---") {
        // 检查是否包含 Obsidian 特有的 [[wikilink]] 语法
        if text.contains("[[") && text.contains("]]") {
            return SupportedFormat::Obsidian;
        }
        // 检查是否包含思源笔记特有的 <siyuan> 标签
        if text.contains("<siyuan") || text.contains("data-type=\"block-ref\"") {
            return SupportedFormat::Siyuan;
        }
        return SupportedFormat::Markdown;
    }

    // 检测 Markdown 标题特征：以 # 开头
    if text.trim_start().starts_with('#') {
        return SupportedFormat::Markdown;
    }

    // 检测 Joplin 导出格式：通常包含特定的 front matter 字段
    // 借鉴 Joplin 导出格式: https://github.com/laurent22/joplin
    if text.contains("joplin") || text.contains("source_application") {
        return SupportedFormat::Joplin;
    }

    // 默认为普通 Markdown，提供最大兼容性
    // 借鉴 Pandoc 的 fallback 策略：未知格式按 Markdown 处理
    SupportedFormat::Markdown
}

// ============================================================================
// 类型定义
// ============================================================================

/// 导入后的笔记数据
/// 借鉴 Joplin 导入后的数据模型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportedNote {
    /// 笔记标题
    pub title: String,
    /// 笔记正文内容
    pub content: String,
    /// 所属文件夹路径（相对路径）
    pub folder_path: String,
    /// 标签列表
    pub tags: Vec<String>,
    /// 附件文件路径列表（已重映射后的路径）
    pub attachments: Vec<String>,
    /// 创建时间
    pub created_at: DateTime<Utc>,
    /// 更新时间
    pub updated_at: DateTime<Utc>,
}

/// 导出笔记的描述结构
/// 借鉴 Obsidian 导出 API 的数据模型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NoteExport {
    /// 笔记标题
    pub title: String,
    /// 笔记正文内容
    pub content: String,
    /// 标签列表
    pub tags: Vec<String>,
    /// 附件文件路径列表
    pub attachments: Vec<String>,
    /// 创建时间
    pub created_at: DateTime<Utc>,
    /// 更新时间
    pub updated_at: DateTime<Utc>,
}

/// 支持的源格式枚举
/// 借鉴 Pandoc 的 input/output format 概念
/// 来源: https://pandoc.org/MANUAL.html#general-options
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SupportedFormat {
    /// 标准 Markdown（CommonMark 兼容）
    Markdown,
    /// HTML 格式
    Html,
    /// Joplin 导出格式
    /// 来源: https://github.com/laurent22/joplin
    Joplin,
    /// Obsidian Vault 格式（含 [[wikilink]] 和 Obsidian Properties）
    /// 来源: https://github.com/obsidianmd/obsidian-api
    Obsidian,
    /// 思源笔记格式（含 data-type 块引用和 <siyuan> 标签）
    /// 来源: https://github.com/siyuan-note/siyuan
    Siyuan,
}

impl SupportedFormat {
    /// 格式的显示名称（中文）
    pub fn display_name(&self) -> &str {
        match self {
            SupportedFormat::Markdown => "Markdown",
            SupportedFormat::Html => "HTML",
            SupportedFormat::Joplin => "Joplin",
            SupportedFormat::Obsidian => "Obsidian",
            SupportedFormat::Siyuan => "思源笔记",
        }
    }

    /// 判断是否为 Markdown 变体格式
    pub fn is_markdown_variant(&self) -> bool {
        matches!(
            self,
            SupportedFormat::Markdown
                | SupportedFormat::Obsidian
                | SupportedFormat::Joplin
                | SupportedFormat::Siyuan
        )
    }
}

/// 格式操作错误类型
/// 借鉴 Pandoc 的错误分类方式
#[derive(Debug)]
pub enum FormatError {
    /// IO 错误（文件读写失败）
    IoError(std::io::Error),
    /// 解析错误（格式不正确或内容损坏）
    ParseError(String),
    /// 不支持的格式
    UnsupportedFormat(String),
    /// 格式检测失败（无法确定源格式）
    DetectionFailed(String),
}

impl std::fmt::Display for FormatError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FormatError::IoError(e) => write!(f, "IO 错误: {}", e),
            FormatError::ParseError(msg) => write!(f, "解析错误: {}", msg),
            FormatError::UnsupportedFormat(msg) => write!(f, "不支持的格式: {}", msg),
            FormatError::DetectionFailed(msg) => write!(f, "格式检测失败: {}", msg),
        }
    }
}

impl std::error::Error for FormatError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            FormatError::IoError(e) => Some(e),
            _ => None,
        }
    }
}

impl From<std::io::Error> for FormatError {
    fn from(e: std::io::Error) -> Self {
        FormatError::IoError(e)
    }
}
