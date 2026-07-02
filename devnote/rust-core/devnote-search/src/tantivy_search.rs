//! Tantivy 全文搜索引擎
//!
//! ## 借鉴的开源项目
//! - **Tantivy** ([https://github.com/quickwit-oss/tantivy](https://github.com/quickwit-oss/tantivy)): Rust 实现的全文搜索引擎
//! - **Lucene** ([https://lucene.apache.org/](https://lucene.apache.org/)): Tantivy 借鉴了 Lucene 的倒排索引设计
//!
//! ## 实现说明
//! Tantivy 提供比 SQLite FTS5 更高的检索性能，适合大规模笔记检索。
//! 与 tantivy 兼容的查询语法包括布尔查询、短语查询、通配符等。

use devnote_observe::info;
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};
use std::sync::{Arc, Mutex};
use std::path::Path;
use anyhow::{Context, Result};

// 引入统一 SearchEngine trait 及其关联类型，使 TantivySearchEngine 实现统一接口
use crate::{SearchEngine, SearchResult, SearchFilter};

use tantivy::schema::{
    IndexRecordOption, STORED, STRING, TEXT, Value, Schema, Field, INDEXED,
};
use tantivy::{
    Index, IndexSettings, IndexWriter, ReloadPolicy, TantivyDocument,
    DateTime as TantivyDateTime,
};
use tantivy::directory::MmapDirectory;
use tantivy::collector::TopDocs;
use tantivy::query::{BooleanQuery, Occur, QueryParser, TermQuery};

/// Tantivy 搜索结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TantivySearchResult {
    pub note_id: String,
    pub title: String,
    pub content_snippet: String,
    pub score: f32,
}

/// Tantivy 搜索引擎配置
#[derive(Debug, Clone)]
pub struct TantivyConfig {
    /// 索引存储路径
    pub index_path: String,
    /// 索引 Writer 内存预算（字节），默认 50MB
    pub writer_memory_bytes: usize,
}

impl Default for TantivyConfig {
    fn default() -> Self {
        Self {
            index_path: String::from("./tantivy_index"),
            writer_memory_bytes: 50_000_000, // 50MB
        }
    }
}

/// 缓存的 schema 字段集合。
///
/// P3 修复: 原实现每个方法内都执行 `self.schema.get_field("xxx").expect(...)`，
/// 既是潜在 panic 点又重复字符串查找。现于构造时一次性解析并缓存为具名字段。
struct CachedFields {
    note_id: Field,
    title: Field,
    content: Field,
    folder_id: Field,
    tags: Field,
    updated_at: Field,
}

/// Tantivy 全文搜索引擎
///
/// ## 借鉴的开源项目
/// - **Tantivy** ([官方仓库](https://github.com/quickwit-oss/tantivy)):
///   借鉴其 Schema 定义、IndexWriter 批量写入、QueryParser 查询解析机制
/// - **Lucene** ([官网](https://lucene.apache.org/)):
///   借鉴其倒排索引（Inverted Index）设计思想，Tantivy 本身就是受 Lucene 启发而构建
///
/// ## 架构说明
/// - Schema 定义了 note_id(STRING)、title(TEXT)、content(TEXT) 三个核心字段
/// - title 字段使用默认分词器，content 字段使用简易分词器
/// - 使用 Arc<Mutex<>> 包装 Index 和 IndexWriter 实现线程安全访问
pub struct TantivySearchEngine {
    index: Arc<Mutex<Index>>,
    schema: Schema,
    /// P3 修复: 缓存的字段句柄，避免每次调用重复字符串查找
    fields: CachedFields,
    writer: Arc<Mutex<IndexWriter>>,
    config: TantivyConfig,
}

impl TantivySearchEngine {
    /// 创建新的 Tantivy 搜索引擎实例
    ///
    /// 如果索引目录不存在则创建，并初始化 Schema
    pub fn new(config: TantivyConfig) -> Result<Self> {
        let schema = Self::build_schema();
        let index = Self::open_or_create_index(&config.index_path, &schema)?;
        let writer = index
            .writer(config.writer_memory_bytes)
            .context("Failed to create index writer")?;

        // P3 修复: 构造时一次性解析字段，后续直接引用缓存句柄
        let fields = CachedFields {
            note_id: schema.get_field("note_id").context("schema field 'note_id' missing")?,
            title: schema.get_field("title").context("schema field 'title' missing")?,
            content: schema.get_field("content").context("schema field 'content' missing")?,
            folder_id: schema.get_field("folder_id").context("schema field 'folder_id' missing")?,
            tags: schema.get_field("tags").context("schema field 'tags' missing")?,
            updated_at: schema.get_field("updated_at").context("schema field 'updated_at' missing")?,
        };

        let config_path = config.index_path.clone();
        let engine = Self {
            index: Arc::new(Mutex::new(index)),
            schema,
            fields,
            writer: Arc::new(Mutex::new(writer)),
            config,
        };

        info!("TantivySearchEngine initialized at {}", config_path);
        Ok(engine)
    }

    /// 构建 Tantivy Schema
    ///
    /// 借鉴 Lucene 的字段设计：
    /// - note_id: STRING 类型，用于精确匹配
    /// - title: TEXT 类型，全文索引 + 存储原始值
    /// - content: TEXT 类型，全文索引 + 存储原始值
    /// - folder_id: STRING 类型，用于分类过滤
    /// - tags: 多值 STRING 类型，用于标签过滤
    /// - updated_at: FAST 类型，用于日期范围过滤
    fn build_schema() -> Schema {
        let mut builder = tantivy::schema::Schema::builder();

        // note_id: 字符串字段，精确匹配
        builder.add_text_field("note_id", STRING | STORED);
        // title: 文本字段，全文检索
        builder.add_text_field("title", TEXT | STORED);
        // content: 文本字段，全文检索
        builder.add_text_field("content", TEXT | STORED);
        // folder_id: 字符串字段，分类过滤
        builder.add_text_field("folder_id", STRING | STORED);
        // tags: 多值字符串字段
        builder.add_text_field("tags", STRING | STORED);
        // updated_at: 快速字段，范围过滤
        builder.add_date_field(
            "updated_at",
            tantivy::schema::DateOptions::from(INDEXED)
                .set_stored()
                .set_fast(),
        );

        builder.build()
    }

    /// 打开已有索引或创建新索引
    fn open_or_create_index(index_path: &str, schema: &Schema) -> Result<Index> {
        let path = Path::new(index_path);

        // 确保目录存在
        if !path.exists() {
            std::fs::create_dir_all(path).context("Failed to create index directory")?;
        }

        let dir = MmapDirectory::open(path).context("Failed to open mmap directory")?;

        // 尝试打开已有索引，失败则创建新索引
        match Index::open(dir.clone()) {
            Ok(index) => {
                info!("Opened existing tantivy index at {}", index_path);
                Ok(index)
            }
            Err(_) => {
                let index = Index::create(dir, schema.clone(), IndexSettings::default())
                    .context("Failed to create tantivy index")?;
                info!("Created new tantivy index at {}", index_path);
                Ok(index)
            }
        }
    }

    /// 索引笔记（借鉴 Tantivy 的文档写入机制）
    pub fn index_note(
        &self,
        note_id: &Uuid,
        title: &str,
        content: &str,
        folder_id: &Uuid,
        tags: &[String],
        updated_at: &DateTime<Utc>,
    ) -> Result<()> {
        // P2 修复: 锁中毒改返回错误而非 panic，避免单次 panic 导致整个搜索子系统永久不可用
        let mut writer = self.writer.lock().map_err(|e| anyhow::anyhow!("index writer mutex poisoned: {}", e))?;

        // P3 修复: 使用构造时缓存的字段句柄，消除重复字符串查找与 expect panic 点
        let note_id_field = self.fields.note_id;
        let title_field = self.fields.title;
        let content_field = self.fields.content;
        let folder_id_field = self.fields.folder_id;
        let tags_field = self.fields.tags;
        let updated_at_field = self.fields.updated_at;

        // 先删除旧文档（如果存在）
        let delete_term = tantivy::Term::from_field_text(
            note_id_field,
            &note_id.to_string(),
        );
        writer.delete_term(delete_term);

        // 添加新文档（借鉴 Tantivy 的 TantivyDocument 机制）
        let mut doc = TantivyDocument::default();
        doc.add_text(note_id_field, note_id.to_string());
        doc.add_text(title_field, title);
        doc.add_text(content_field, content);
        doc.add_text(folder_id_field, folder_id.to_string());
        for tag in tags {
            doc.add_text(tags_field, tag.as_str());
        }
        doc.add_date(updated_at_field, TantivyDateTime::from_timestamp_secs(updated_at.timestamp()));

        writer.add_document(doc)?;
        writer.commit()?;

        info!("Indexed note {} with title '{}'", note_id, title);
        Ok(())
    }

    /// 索引笔记（简单版本，不包含元数据）
    pub fn index_note_simple(&self, note_id: &Uuid, title: &str, content: &str) -> Result<()> {
        let now = Utc::now();
        let folder_id = Uuid::nil();
        self.index_note(note_id, title, content, &folder_id, &[], &now)
    }

    /// 删除笔记索引
    pub fn remove_note(&self, note_id: &Uuid) -> Result<()> {
        // P2 修复: 锁中毒改返回错误而非 panic
        let mut writer = self.writer.lock().map_err(|e| anyhow::anyhow!("index writer mutex poisoned: {}", e))?;

        let note_id_field = self.fields.note_id;
        let delete_term = tantivy::Term::from_field_text(
            note_id_field,
            &note_id.to_string(),
        );
        writer.delete_term(delete_term);
        writer.commit()?;

        info!("Removed note {} from index", note_id);
        Ok(())
    }

    /// 执行全文搜索
    ///
    /// 借鉴 Tantivy 的 QueryParser 机制：
    /// - 支持多字段搜索：title 和 content 同时进行
    /// - 支持布尔查询：+term1 term2（必须包含 term1，可选包含 term2）
    /// - 支持短语查询："exact phrase"
    /// - 支持通配符：term*
    pub fn search(&self, query: &str, limit: usize) -> Result<Vec<TantivySearchResult>> {
        if query.trim().is_empty() {
            return Ok(Vec::new());
        }

        // P2 修复: 锁中毒改返回错误而非 panic
        let index = self.index.lock().map_err(|e| anyhow::anyhow!("index mutex poisoned: {}", e))?;
        let reader = index
            .reader_builder()
            .reload_policy(ReloadPolicy::Manual)
            .try_into()?;
        let searcher = reader.searcher();

        let title_field = self.fields.title;
        let content_field = self.fields.content;

        // 使用 QueryParser 解析查询（借鉴 Tantivy 的默认解析器）
        let query_parser = QueryParser::for_index(
            &index,
            vec![title_field, content_field],
        );
        let parsed_query = query_parser.parse_query(query)?;

        // 使用 TopDocs 获取最高分的前 N 个结果（借鉴 Lucene 的 TopDocsCollector）
        let top_docs = TopDocs::with_limit(limit);
        let results = searcher.search(&parsed_query, &top_docs)?;

        let note_id_field = self.fields.note_id;
        let title_field = self.fields.title;
        let content_field = self.fields.content;

        let mut search_results = Vec::new();
        for (_score, doc_address) in results {
            let doc: TantivyDocument = searcher.doc(doc_address)?;

            let note_id = doc
                .get_first(note_id_field)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            let title = doc
                .get_first(title_field)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            // 生成内容摘要（取前 200 字符）
            let content = doc
                .get_first(content_field)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let snippet = if content.len() > 200 {
                format!("{}...", &content[..200])
            } else {
                content
            };

            search_results.push(TantivySearchResult {
                note_id,
                title,
                content_snippet: snippet,
                score: _score,
            });
        }

        info!("Tantivy search for '{}' returned {} results", query, search_results.len());
        Ok(search_results)
    }

    /// 带过滤条件的搜索
    ///
    /// 借鉴 Tantivy 的 BooleanQuery 机制：
    /// 将全文查询与过滤条件组合为 MUST 和 FILTER 子句
    pub fn search_with_filter(
        &self,
        query: &str,
        folder_id: Option<&Uuid>,
        tags: &[String],
        limit: usize,
    ) -> Result<Vec<TantivySearchResult>> {
        if query.trim().is_empty() && folder_id.is_none() && tags.is_empty() {
            return Ok(Vec::new());
        }

        let index = self.index.lock().map_err(|e| anyhow::anyhow!("index mutex poisoned: {}", e))?;
        let reader = index
            .reader_builder()
            .reload_policy(ReloadPolicy::Manual)
            .try_into()?;
        let searcher = reader.searcher();

        let mut subqueries: Vec<(Occur, Box<dyn tantivy::query::Query>)> = Vec::new();

        // 全文查询子句
        if !query.trim().is_empty() {
            let title_field = self.fields.title;
            let content_field = self.fields.content;
            let query_parser = QueryParser::for_index(
                &index,
                vec![title_field, content_field],
            );
            let parsed_query = query_parser.parse_query(query)?;
            subqueries.push((Occur::Must, parsed_query));
        }

        // 文件夹过滤（借鉴 Tantivy 的 TermQuery 精确匹配）
        if let Some(fid) = folder_id {
            let folder_id_field = self.fields.folder_id;
            let term_query = TermQuery::new(
                tantivy::Term::from_field_text(folder_id_field, &fid.to_string()),
                IndexRecordOption::Basic,
            );
            subqueries.push((Occur::Must, Box::new(term_query)));
        }

        // 标签过滤
        for tag in tags {
            let tags_field = self.fields.tags;
            let term_query = TermQuery::new(
                tantivy::Term::from_field_text(tags_field, tag),
                IndexRecordOption::Basic,
            );
            subqueries.push((Occur::Must, Box::new(term_query)));
        }

        let boolean_query = BooleanQuery::new(subqueries);
        let top_docs = TopDocs::with_limit(limit);
        let results = searcher.search(&boolean_query, &top_docs)?;

        let note_id_field = self.fields.note_id;
        let title_field = self.fields.title;
        let content_field = self.fields.content;

        let mut search_results = Vec::new();
        for (_score, doc_address) in results {
            let doc: TantivyDocument = searcher.doc(doc_address)?;

            let note_id = doc
                .get_first(note_id_field)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            let title = doc
                .get_first(title_field)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            let content = doc
                .get_first(content_field)
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let snippet = if content.len() > 200 {
                format!("{}...", &content[..200])
            } else {
                content
            };

            search_results.push(TantivySearchResult {
                note_id,
                title,
                content_snippet: snippet,
                score: _score,
            });
        }

        Ok(search_results)
    }

    /// 重建索引
    ///
    /// 删除现有索引并重新创建（借鉴 Tantivy 的索引重建机制）
    pub fn rebuild_index(&self) -> Result<()> {
        // 清空索引目录
        let path = Path::new(&self.config.index_path);
        if path.exists() {
            std::fs::remove_dir_all(path).context("Failed to remove old index")?;
        }
        std::fs::create_dir_all(path).context("Failed to recreate index directory")?;

        let new_index = Self::open_or_create_index(&self.config.index_path, &self.schema)?;
        let new_writer = new_index
            .writer(self.config.writer_memory_bytes)
            .context("Failed to create new index writer")?;

        // 替换现有的 index 和 writer
        {
            let mut index_guard = self.index.lock().map_err(|e| anyhow::anyhow!("index mutex poisoned during rebuild: {}", e))?;
            *index_guard = new_index;
        }
        {
            let mut writer_guard = self.writer.lock().map_err(|e| anyhow::anyhow!("writer mutex poisoned during rebuild: {}", e))?;
            *writer_guard = new_writer;
        }

        info!("Rebuilt tantivy index at {}", self.config.index_path);
        Ok(())
    }

    /// 获取索引中的文档数量
    pub fn num_docs(&self) -> Result<u64> {
        let index = self.index.lock().map_err(|e| anyhow::anyhow!("index mutex poisoned in num_docs: {}", e))?;
        let reader = index
            .reader_builder()
            .reload_policy(ReloadPolicy::Manual)
            .try_into()?;
        let searcher = reader.searcher();
        Ok(searcher.num_docs())
    }

    /// 将 TantivySearchResult 转换为统一的 SearchResult 类型
    /// Tantivy 不提供高亮信息，highlights 字段留空
    fn convert_result(r: TantivySearchResult) -> SearchResult {
        // 解析 note_id 字符串为 Uuid，解析失败时使用 nil UUID 兜底
        let note_id = Uuid::parse_str(&r.note_id).unwrap_or_else(|_| Uuid::nil());
        SearchResult {
            note_id,
            title: r.title,
            snippet: r.content_snippet,
            highlights: Vec::new(),
            score: r.score as f64,
        }
    }
}

// ── SearchEngine trait 实现 ──────────────────────────────────────────
// 将 TantivySearchEngine 的固有方法适配到统一的 SearchEngine trait 接口。
// TantivySearchEngine 的固有方法签名与 trait 不完全一致（如 search 缺少 offset
// 参数、返回 TantivySearchResult 而非 SearchResult），此处通过适配层桥接。
// 注意: 在 trait impl 内部调用同名固有方法时，必须使用全限定语法
// TantivySearchEngine::method_name(self, ...) 避免递归调用 trait 方法自身。
impl SearchEngine for TantivySearchEngine {
    fn index_note(&mut self, note_id: &Uuid, title: &str, content: &str) -> anyhow::Result<()> {
        // 委托给 index_note_simple（不带元数据的简单索引版本）
        TantivySearchEngine::index_note_simple(self, note_id, title, content)
    }

    fn index_note_with_meta(
        &mut self,
        note_id: &Uuid,
        title: &str,
        content: &str,
        folder_id: &Uuid,
        tags: &[String],
        updated_at: &DateTime<Utc>,
    ) -> anyhow::Result<()> {
        // 委托给 TantivySearchEngine 的固有 index_note 方法（含完整元数据）
        TantivySearchEngine::index_note(self, note_id, title, content, folder_id, tags, updated_at)
    }

    fn remove_note(&mut self, note_id: &Uuid) -> anyhow::Result<()> {
        TantivySearchEngine::remove_note(self, note_id)
    }

    fn search(&self, query: &str, limit: usize, offset: usize) -> anyhow::Result<Vec<SearchResult>> {
        // 注意: Tantivy 当前固有实现不支持 offset 参数，此处暂忽略
        // 未来可通过 TopDocs::with_limit(limit).and_offset(offset) 支持
        let _ = offset;
        let tantivy_results = TantivySearchEngine::search(self, query, limit)?;
        Ok(tantivy_results.into_iter().map(Self::convert_result).collect())
    }

    fn search_with_filter(
        &self,
        query: &str,
        filter: &SearchFilter,
        limit: usize,
        offset: usize,
    ) -> anyhow::Result<Vec<SearchResult>> {
        // 注意: Tantivy 当前固有实现不支持 offset 与 date_range 过滤，此处暂忽略
        let _ = offset;
        // 将统一 SearchFilter 转换为 TantivySearchEngine::search_with_filter 的参数
        let tantivy_results = TantivySearchEngine::search_with_filter(
            self,
            query,
            filter.folder_id.as_ref(),
            &filter.tags,
            limit,
        )?;
        Ok(tantivy_results.into_iter().map(Self::convert_result).collect())
    }

    fn rebuild_index(&mut self) -> anyhow::Result<()> {
        TantivySearchEngine::rebuild_index(self)
    }
}
