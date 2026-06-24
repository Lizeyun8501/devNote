//! DevNote FRB API —— 基于 flutter_rust_bridge v2 的类型安全 FFI 绑定
//!
//! ## 替换说明
//! 原实现：自研 C ABI FFI 桥接层（~2546 行 Dart + Rust），Event-Dispatch 模式
//! 替换为：flutter_rust_bridge v2 自动生成类型安全绑定
//!
//! ## FRB 优势
//! - **类型安全**：自动生成 Dart 绑定，消除双端 JSON schema 不一致
//! - **内存安全**：消除手写 malloc/free 和 catch_unwind
//! - **性能**：SSE 编解码器比 JSON 序列化快数倍
//! - **开发效率**：新增 Rust 函数只需 `flutter_rust_bridge_codegen generate`
//! - **高级特性**：支持 async/await、Stream、Result 类型
//!
//! 来源: https://pub.dev/packages/flutter_rust_bridge
//! 版本: v2.12.0
//! Flutter Favorite: ✅

use base64::Engine;
use devnote_core::traits::NoteRepository;
use devnote_crypto::{CryptoConfig, CryptoEngine, DefaultCryptoEngine};
use devnote_editor::{BlockEditor, BlockType, DefaultBlockEditor};
use devnote_flashcard::FlashcardEngine;
use devnote_extensions::format::{ExportFormat, FormatExporter, FormatImporter, HtmlExporter, ImportFormat, MarkdownExporter, MarkdownImporter, ObsidianImporter};
use devnote_graph::GraphEngine;
use devnote_object::ObjectEngine;
use devnote_persistence::SqliteNoteRepository;
use devnote_search::SearchEngine;
use devnote_sync::{ClientSyncEngine, SyncEngine};
use devnote_extensions::canvas::{CanvasEngine, LayoutType};
use devnote_crdt::{merge_documents, CRDTDocument, Operation};
use devnote_database::DatabaseEngine;
use devnote_database::formula::eval_formula;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use std::sync::LazyLock;
use uuid::Uuid;

// ── 全局引擎实例 ──────────────────────────────────────────────────────
// 所有引擎通过 LazyLock 延迟初始化，首次访问时自动填充。
// FRB 生成的 Dart 函数直接调用这些引擎实例，无需中间分发层。

pub(crate) static NOTE_REPO: LazyLock<Mutex<Option<SqliteNoteRepository>>> =
    LazyLock::new(|| Mutex::new(None));
pub(crate) static BLOCK_EDITOR: LazyLock<Mutex<Option<DefaultBlockEditor>>> =
    LazyLock::new(|| Mutex::new(None));
pub(crate) static SEARCH_ENGINE: LazyLock<Mutex<Option<devnote_search::SqliteSearchEngine>>> =
    LazyLock::new(|| Mutex::new(None));
pub(crate) static CRYPTO_ENGINE: LazyLock<DefaultCryptoEngine> =
    LazyLock::new(|| DefaultCryptoEngine::new(CryptoConfig::default()));
pub(crate) static SYNC_ENGINE: LazyLock<Mutex<Option<ClientSyncEngine>>> =
    LazyLock::new(|| Mutex::new(None));
pub(crate) static CANVAS_ENGINE: LazyLock<Mutex<Option<CanvasEngine>>> =
    LazyLock::new(|| Mutex::new(None));
pub(crate) static DATABASE_ENGINE: LazyLock<Mutex<Option<devnote_database::SqliteDatabaseEngine>>> =
    LazyLock::new(|| Mutex::new(None));
pub(crate) static OBJECT_ENGINE: LazyLock<Mutex<Option<devnote_object::SqliteObjectEngine>>> =
    LazyLock::new(|| Mutex::new(None));
pub(crate) static GRAPH_ENGINE: LazyLock<Mutex<Option<devnote_graph::SqliteGraphEngine>>> =
    LazyLock::new(|| Mutex::new(None));
pub(crate) static FLASHCARD_ENGINE: LazyLock<Mutex<Option<devnote_flashcard::SqliteFlashcardEngine>>> =
    LazyLock::new(|| Mutex::new(None));
pub(crate) static CRDT_DOCS: LazyLock<Mutex<HashMap<String, CRDTDocument>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

// ── FRB 数据类型 ──────────────────────────────────────────────────────
// FRB 自动将这些 Rust 结构体映射为 Dart 类，无需手写序列化代码

/// 版本信息 —— 替代原 FfiVersionInfo
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VersionInfo {
    pub api_version: u32,
    pub rust_version: String,
    pub compatible_min: u32,
    pub features: Vec<String>,
}

/// 健康检查结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthCheckResult {
    pub status: String,
    pub engines: HashMap<String, bool>,
}

/// 笔记数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NoteData {
    pub id: String,
    pub title: String,
    pub content: String,
    pub folder_id: String,
    pub is_pinned: bool,
    pub is_encrypted: bool,
    pub created_at: String,
    pub updated_at: String,
}

/// 文件夹数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FolderData {
    pub id: String,
    pub name: String,
    pub parent_id: Option<String>,
    pub sort_order: i32,
    pub created_at: String,
    pub updated_at: String,
}

/// 标签数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TagData {
    pub id: String,
    pub name: String,
    pub created_at: String,
}

/// 块数据
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlockData {
    pub id: String,
    pub note_id: String,
    pub block_type: String,
    pub content: String,
    pub position: i32,
    pub created_at: String,
    pub updated_at: String,
}

/// 搜索结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    pub note_id: String,
    pub title: String,
    pub snippet: String,
    pub score: f64,
}

/// 同步状态
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncStatusData {
    pub status: String,
    pub last_synced: Option<String>,
    pub pending_changes: u64,
}

/// CRDT 合并结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MergeResult {
    pub applied_count: usize,
    pub conflicts: Vec<String>,
}

/// 数据库视图类型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseViewData {
    pub id: String,
    pub name: String,
    pub view_type: String,
}

// ── FRB 导出函数 ──────────────────────────────────────────────────────
// 每个函数对应原 handlers.rs 中的一个或多个事件处理器
// FRB 会自动为这些函数生成 Dart 绑定

/// 初始化所有引擎 —— 替代原 devnote_init + register_all_handlers
/// FRB 自动生成 Dart: `Future<void> initEngines()`
///
/// P0 修复: 原实现使用 `in_memory()`，FFI 模式下数据重启全部丢失。
/// 现改为文件持久化，数据库路径通过参数传入，与 Dart 端共享 `devnote.db`。
pub fn init_engines(db_path: String) -> Result<(), String> {
    let repo = SqliteNoteRepository::init(&db_path)
        .map_err(|e| format!("Failed to init persistence: {}", e))?;
    *NOTE_REPO.lock() = Some(repo);
    *BLOCK_EDITOR.lock() = Some(DefaultBlockEditor::new());
    if let Ok(engine) = devnote_search::SqliteSearchEngine::in_memory() {
        *SEARCH_ENGINE.lock() = Some(engine);
    }
    *SYNC_ENGINE.lock() = Some(ClientSyncEngine::new(
        "default-doc".to_string(),
        "default-device".to_string(),
    ));
    *CANVAS_ENGINE.lock() = Some(CanvasEngine::new());
    if let Ok(engine) = devnote_database::SqliteDatabaseEngine::in_memory() {
        *DATABASE_ENGINE.lock() = Some(engine);
    }
    if let Ok(engine) = devnote_object::SqliteObjectEngine::in_memory() {
        *OBJECT_ENGINE.lock() = Some(engine);
    }
    if let Ok(engine) = devnote_graph::SqliteGraphEngine::in_memory() {
        *GRAPH_ENGINE.lock() = Some(engine);
    }
    if let Ok(engine) = devnote_flashcard::SqliteFlashcardEngine::in_memory() {
        *FLASHCARD_ENGINE.lock() = Some(engine);
    }
    Ok(())
}

/// 版本协商 —— 替代原 SystemEvent.GetVersion
pub fn get_version() -> VersionInfo {
    VersionInfo {
        api_version: 1,
        rust_version: env!("CARGO_PKG_VERSION").to_string(),
        compatible_min: 1,
        features: vec![
            "sqlite_persistence".to_string(),
            "sqlite_fts5_search".to_string(),
            "xchacha20_poly1305".to_string(),
            "argon2id".to_string(),
            "bip39_recovery".to_string(),
            "wasm_plugin_sandbox".to_string(),
            "obsidian_import".to_string(),
            "markdown_render".to_string(),
        ],
    }
}

/// 健康检查 —— 替代原 SystemEvent.HealthCheck
pub fn health_check() -> HealthCheckResult {
    let mut engines = HashMap::new();
    engines.insert("persistence".to_string(), NOTE_REPO.lock().is_some());
    engines.insert("editor".to_string(), BLOCK_EDITOR.lock().is_some());
    engines.insert("search".to_string(), SEARCH_ENGINE.lock().is_some());
    engines.insert("crypto".to_string(), true);
    engines.insert("sync".to_string(), SYNC_ENGINE.lock().is_some());
    engines.insert("database".to_string(), DATABASE_ENGINE.lock().is_some());
    engines.insert("object".to_string(), OBJECT_ENGINE.lock().is_some());
    engines.insert("graph".to_string(), GRAPH_ENGINE.lock().is_some());
    engines.insert("canvas".to_string(), CANVAS_ENGINE.lock().is_some());
    engines.insert("format".to_string(), true);
    engines.insert("crdt".to_string(), true);
    engines.insert("flashcard".to_string(), FLASHCARD_ENGINE.lock().is_some());
    HealthCheckResult { status: "ok".to_string(), engines }
}

// ── 笔记 API ──────────────────────────────────────────────────────────

/// 从 Note 的 blocks 中提取纯文本内容
fn extract_content(note: &devnote_core::models::Note) -> String {
    note.blocks.iter()
        .map(|b| b.content.clone())
        .collect::<Vec<_>>()
        .join("\n")
}

fn note_to_data(note: &devnote_core::models::Note) -> NoteData {
    NoteData {
        id: note.id.to_string(),
        title: note.title.clone(),
        content: extract_content(note),
        folder_id: note.folder_id.to_string(),
        is_pinned: note.is_pinned,
        is_encrypted: note.is_encrypted,
        created_at: note.created_at.to_rfc3339(),
        updated_at: note.updated_at.to_rfc3339(),
    }
}

/// 创建笔记 —— 替代原 NoteEvent.CreateNote
pub fn create_note(title: String, content: String, folder_id: String) -> Result<NoteData, String> {
    let fid = Uuid::parse_str(&folder_id).map_err(|e| e.to_string())?;
    let mut guard = NOTE_REPO.lock();
    let repo = guard.as_mut().ok_or("Persistence engine not initialized")?;
    let note = devnote_core::models::Note::new(title, fid);
    let note = repo.create_note(note).map_err(|e| e.to_string())?;
    Ok(note_to_data(&note))
}

/// 获取笔记 —— 替代原 NoteEvent.GetNote
pub fn get_note(id: String) -> Result<Option<NoteData>, String> {
    let uid = Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let guard = NOTE_REPO.lock();
    let repo = guard.as_ref().ok_or("Persistence engine not initialized")?;
    match repo.get_note(&uid) {
        Ok(Some(note)) => Ok(Some(note_to_data(&note))),
        Ok(None) => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

/// 更新笔记 —— 替代原 NoteEvent.UpdateNote
pub fn update_note(id: String, title: String, content: String) -> Result<NoteData, String> {
    let uid = Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let mut guard = NOTE_REPO.lock();
    let repo = guard.as_mut().ok_or("Persistence engine not initialized")?;
    let mut note = repo.get_note(&uid).map_err(|e| e.to_string())?
        .ok_or("Note not found")?;
    note.title = title;
    let note = repo.update_note(note).map_err(|e| e.to_string())?;
    Ok(note_to_data(&note))
}

/// 删除笔记 —— 替代原 NoteEvent.DeleteNote
pub fn delete_note(id: String) -> Result<(), String> {
    let uid = Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let mut guard = NOTE_REPO.lock();
    let repo = guard.as_mut().ok_or("Persistence engine not initialized")?;
    repo.delete_note(&uid).map_err(|e| e.to_string())
}

/// 列出笔记 —— 替代原 NoteEvent.ListNotes
pub fn list_notes(folder_id: String) -> Result<Vec<NoteData>, String> {
    let fid = Uuid::parse_str(&folder_id).map_err(|e| e.to_string())?;
    let guard = NOTE_REPO.lock();
    let repo = guard.as_ref().ok_or("Persistence engine not initialized")?;
    let notes = repo.list_notes(&fid).map_err(|e| e.to_string())?;
    Ok(notes.iter().map(|n| note_to_data(n)).collect())
}

// ── 文件夹 API ────────────────────────────────────────────────────────

/// 创建文件夹 —— 替代原 FolderEvent.CreateFolder
pub fn create_folder(name: String, parent_id: Option<String>) -> Result<FolderData, String> {
    let pid = parent_id.map(|s| Uuid::parse_str(&s)).transpose().map_err(|e| e.to_string())?;
    let guard = NOTE_REPO.lock();
    let repo = guard.as_ref().ok_or("Persistence engine not initialized")?;
    let folder = repo.create_folder(&name, pid.as_ref()).map_err(|e| e.to_string())?;
    Ok(FolderData {
        id: folder.id.to_string(),
        name: folder.name,
        parent_id: folder.parent_id.map(|id| id.to_string()),
        sort_order: folder.sort_order,
        created_at: folder.created_at.to_rfc3339(),
        updated_at: folder.updated_at.to_rfc3339(),
    })
}

/// 列出文件夹 —— 替代原 FolderEvent.ListFolders
pub fn list_folders(parent_id: Option<String>) -> Result<Vec<FolderData>, String> {
    let pid = parent_id.map(|s| Uuid::parse_str(&s)).transpose().map_err(|e| e.to_string())?;
    let guard = NOTE_REPO.lock();
    let repo = guard.as_ref().ok_or("Persistence engine not initialized")?;
    let folders = repo.list_folders(pid.as_ref()).map_err(|e| e.to_string())?;
    Ok(folders.into_iter().map(|f| FolderData {
        id: f.id.to_string(),
        name: f.name,
        parent_id: f.parent_id.map(|id| id.to_string()),
        sort_order: f.sort_order,
        created_at: f.created_at.to_rfc3339(),
        updated_at: f.updated_at.to_rfc3339(),
    }).collect())
}

/// 删除文件夹 —— 替代原 FolderEvent.DeleteFolder
pub fn delete_folder(id: String) -> Result<(), String> {
    let uid = Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let mut guard = NOTE_REPO.lock();
    let repo = guard.as_mut().ok_or("Persistence engine not initialized")?;
    NoteRepository::delete_folder(repo, &uid).map_err(|e| e.to_string())
}

/// 获取文件夹 —— 替代原 FolderEvent.GetFolder
pub fn get_folder(id: String) -> Result<Option<FolderData>, String> {
    let uid = Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let mut guard = NOTE_REPO.lock();
    let repo = guard.as_mut().ok_or("Persistence engine not initialized")?;
    match NoteRepository::get_folder(repo, &uid) {
        Ok(Some(folder)) => Ok(Some(FolderData {
            id: folder.id.to_string(),
            name: folder.name,
            parent_id: folder.parent_id.map(|id| id.to_string()),
            sort_order: folder.sort_order,
            created_at: folder.created_at.to_rfc3339(),
            updated_at: folder.updated_at.to_rfc3339(),
        })),
        Ok(None) => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

/// 更新文件夹 —— 替代原 FolderEvent.UpdateFolder
pub fn update_folder(id: String, name: String, parent_id: Option<String>, sort_order: Option<i32>) -> Result<FolderData, String> {
    let uid = Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let pid = parent_id.map(|s| Uuid::parse_str(&s)).transpose().map_err(|e| e.to_string())?;
    let mut guard = NOTE_REPO.lock();
    let repo = guard.as_mut().ok_or("Persistence engine not initialized")?;
    let existing = NoteRepository::get_folder(repo, &uid)
        .map_err(|e| e.to_string())?
        .ok_or("Folder not found")?;
    let sort_order = sort_order.unwrap_or(existing.sort_order);
    let folder = devnote_core::models::Folder {
        id: uid,
        name,
        parent_id: pid,
        sort_order,
        created_at: existing.created_at,
        updated_at: chrono::Utc::now(),
    };
    let folder = NoteRepository::update_folder(repo, folder).map_err(|e| e.to_string())?;
    Ok(FolderData {
        id: folder.id.to_string(),
        name: folder.name,
        parent_id: folder.parent_id.map(|id| id.to_string()),
        sort_order: folder.sort_order,
        created_at: folder.created_at.to_rfc3339(),
        updated_at: folder.updated_at.to_rfc3339(),
    })
}

// ── 标签 API ──────────────────────────────────────────────────────────

/// 创建标签 —— 替代原 TagEvent.CreateTag
pub fn create_tag(name: String) -> Result<TagData, String> {
    let guard = NOTE_REPO.lock();
    let repo = guard.as_ref().ok_or("Persistence engine not initialized")?;
    let tag = repo.create_tag(&name).map_err(|e| e.to_string())?;
    Ok(TagData {
        id: tag.id.to_string(),
        name: tag.name,
        created_at: tag.created_at.to_rfc3339(),
    })
}

/// 列出标签 —— 替代原 TagEvent.ListTags
pub fn list_tags() -> Result<Vec<TagData>, String> {
    let mut guard = NOTE_REPO.lock();
    let repo = guard.as_mut().ok_or("Persistence engine not initialized")?;
    let tags = NoteRepository::list_tags(repo).map_err(|e| e.to_string())?;
    Ok(tags.into_iter().map(|t| TagData {
        id: t.id.to_string(),
        name: t.name,
        created_at: t.created_at.to_rfc3339(),
    }).collect())
}

/// 删除标签 —— 替代原 TagEvent.DeleteTag
pub fn delete_tag(id: String) -> Result<(), String> {
    let uid = Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let mut guard = NOTE_REPO.lock();
    let repo = guard.as_mut().ok_or("Persistence engine not initialized")?;
    NoteRepository::delete_tag(repo, &uid).map_err(|e| e.to_string())
}

// ── 编辑器 API ────────────────────────────────────────────────────────

/// 插入块 —— 替代原 EditorEvent.InsertBlock
pub fn insert_block(note_id: String, block_type: String, content: String, position: Option<usize>) -> Result<BlockData, String> {
    let nid = Uuid::parse_str(&note_id).map_err(|e| e.to_string())?;
    let bt: BlockType = serde_json::from_value(serde_json::Value::String(block_type))
        .map_err(|e| e.to_string())?;
    let mut guard = BLOCK_EDITOR.lock();
    let editor = guard.as_mut().ok_or("Editor engine not initialized")?;
    let pos = position.unwrap_or(0);
    let block = editor.create_block(nid, bt, content, pos).map_err(|e| e.to_string())?;
    Ok(BlockData {
        id: block.id.to_string(),
        note_id: block.note_id.to_string(),
        block_type: format!("{:?}", block.block_type),
        content: block.content,
        position: block.position as i32,
        created_at: block.created_at.to_rfc3339(),
        updated_at: block.updated_at.to_rfc3339(),
    })
}

/// 更新块 —— 替代原 EditorEvent.UpdateBlock
pub fn update_block(id: String, content: String) -> Result<(), String> {
    let uid = Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let mut guard = BLOCK_EDITOR.lock();
    let editor = guard.as_mut().ok_or("Editor engine not initialized")?;
    editor.update_block(&uid, content).map_err(|e| e.to_string())
}

/// 删除块 —— 替代原 EditorEvent.DeleteBlock
pub fn delete_block(id: String) -> Result<(), String> {
    let uid = Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    let mut guard = BLOCK_EDITOR.lock();
    let editor = guard.as_mut().ok_or("Editor engine not initialized")?;
    editor.delete_block(&uid).map_err(|e| e.to_string())
}

/// 获取笔记的所有块 —— 替代原 EditorEvent.GetBlocks
pub fn get_blocks(note_id: String) -> Result<Vec<BlockData>, String> {
    let nid = Uuid::parse_str(&note_id).map_err(|e| e.to_string())?;
    let mut guard = BLOCK_EDITOR.lock();
    let editor = guard.as_mut().ok_or("Editor engine not initialized")?;
    let blocks = editor.list_blocks(&nid, None, None).map_err(|e| e.to_string())?;
    Ok(blocks.into_iter().map(|b| BlockData {
        id: b.id.to_string(),
        note_id: b.note_id.to_string(),
        block_type: format!("{:?}", b.block_type),
        content: b.content,
        position: b.position as i32,
        created_at: b.created_at.to_rfc3339(),
        updated_at: b.updated_at.to_rfc3339(),
    }).collect())
}

// ── 搜索 API ──────────────────────────────────────────────────────────

/// 搜索笔记 —— 替代原 SearchEvent.Search
pub fn search_notes(query: String, limit: Option<usize>, offset: Option<usize>) -> Result<Vec<SearchResult>, String> {
    let lim = limit.unwrap_or(50);
    let off = offset.unwrap_or(0);
    let guard = SEARCH_ENGINE.lock();
    let engine = guard.as_ref().ok_or("Search engine not initialized")?;
    let results = engine.search(&query, lim, off).map_err(|e| e.to_string())?;
    Ok(results.into_iter().map(|r| SearchResult {
        note_id: r.note_id.to_string(),
        title: r.title,
        snippet: r.snippet,
        score: r.score,
    }).collect())
}

// ── 加密 API ──────────────────────────────────────────────────────────

/// 加密数据 —— 替代原 CryptoEvent.Encrypt
pub fn encrypt(plaintext_base64: String, key_base64: String) -> Result<String, String> {
    let plaintext = base64::engine::general_purpose::STANDARD.decode(&plaintext_base64)
        .map_err(|e| format!("Invalid base64 plaintext: {}", e))?;
    let key = base64::engine::general_purpose::STANDARD.decode(&key_base64)
        .map_err(|e| format!("Invalid base64 key: {}", e))?;
    let ciphertext = CRYPTO_ENGINE.encrypt(&plaintext, &key).map_err(|e| e.to_string())?;
    Ok(base64::engine::general_purpose::STANDARD.encode(&ciphertext))
}

/// 解密数据 —— 替代原 CryptoEvent.Decrypt
pub fn decrypt(ciphertext_base64: String, key_base64: String) -> Result<String, String> {
    let ciphertext = base64::engine::general_purpose::STANDARD.decode(&ciphertext_base64)
        .map_err(|e| format!("Invalid base64 ciphertext: {}", e))?;
    let key = base64::engine::general_purpose::STANDARD.decode(&key_base64)
        .map_err(|e| format!("Invalid base64 key: {}", e))?;
    let plaintext = CRYPTO_ENGINE.decrypt(&ciphertext, &key).map_err(|e| e.to_string())?;
    Ok(base64::engine::general_purpose::STANDARD.encode(&plaintext))
}

/// 派生密钥 —— 替代原 CryptoEvent.DeriveKey
pub fn derive_key(password: String, salt_base64: String) -> Result<String, String> {
    let salt = base64::engine::general_purpose::STANDARD.decode(&salt_base64)
        .map_err(|e| format!("Invalid base64 salt: {}", e))?;
    let key = CRYPTO_ENGINE.derive_key(&password, &salt).map_err(|e| e.to_string())?;
    Ok(base64::engine::general_purpose::STANDARD.encode(&key))
}

// ── 同步 API ──────────────────────────────────────────────────────────

/// 推送变更 —— 替代原 SyncEvent.PushChanges
pub fn push_changes() -> Result<SyncStatusData, String> {
    let mut guard = SYNC_ENGINE.lock();
    let engine = guard.as_mut().ok_or("Sync engine not initialized")?;
    let info = engine.push_changes().map_err(|e| e.to_string())?;
    Ok(SyncStatusData {
        status: format!("{:?}", info.status),
        last_synced: info.last_synced_at.map(|t| t.to_rfc3339()),
        pending_changes: info.pending_changes,
    })
}

/// 拉取变更 —— 替代原 SyncEvent.PullChanges
pub fn pull_changes() -> Result<SyncStatusData, String> {
    let mut guard = SYNC_ENGINE.lock();
    let engine = guard.as_mut().ok_or("Sync engine not initialized")?;
    let info = engine.pull_changes().map_err(|e| e.to_string())?;
    Ok(SyncStatusData {
        status: format!("{:?}", info.status),
        last_synced: info.last_synced_at.map(|t| t.to_rfc3339()),
        pending_changes: info.pending_changes,
    })
}

/// 获取同步状态 —— 替代原 SyncEvent.GetStatus
pub fn get_sync_status() -> Result<SyncStatusData, String> {
    let guard = SYNC_ENGINE.lock();
    let engine = guard.as_ref().ok_or("Sync engine not initialized")?;
    let status = engine.get_status();
    Ok(SyncStatusData {
        status: format!("{:?}", status),
        last_synced: None,
        pending_changes: 0,
    })
}

// ── Canvas API ────────────────────────────────────────────────────────

/// 添加画布节点 —— 替代原 CanvasEvent.AddNode
pub fn canvas_add_node(canvas_id: String, node_json: String) -> Result<(), String> {
    let node: devnote_extensions::canvas::CanvasNode = serde_json::from_str(&node_json)
        .map_err(|e| e.to_string())?;
    let mut guard = CANVAS_ENGINE.lock();
    let engine = guard.as_mut().ok_or("Canvas engine not initialized")?;
    engine.add_node(&canvas_id, node).map_err(|e| e.to_string())
}

/// 移除画布节点 —— 替代原 CanvasEvent.RemoveNode
pub fn canvas_remove_node(canvas_id: String, node_id: String) -> Result<(), String> {
    let mut guard = CANVAS_ENGINE.lock();
    let engine = guard.as_mut().ok_or("Canvas engine not initialized")?;
    engine.remove_node(&canvas_id, &node_id).map_err(|e| e.to_string())
}

/// 画布自动布局 —— 替代原 CanvasEvent.AutoLayout
pub fn canvas_auto_layout(canvas_id: String, layout_type: String) -> Result<(), String> {
    let lt: LayoutType = serde_json::from_value(serde_json::Value::String(layout_type))
        .map_err(|e| e.to_string())?;
    let mut guard = CANVAS_ENGINE.lock();
    let engine = guard.as_mut().ok_or("Canvas engine not initialized")?;
    engine.auto_layout(&canvas_id, lt).map_err(|e| e.to_string())
}

/// 添加画布边 —— 替代原 CanvasEvent.AddEdge
pub fn canvas_add_edge(canvas_id: String, edge_json: String) -> Result<(), String> {
    let edge: devnote_extensions::canvas::CanvasEdge = serde_json::from_str(&edge_json)
        .map_err(|e| e.to_string())?;
    let mut guard = CANVAS_ENGINE.lock();
    let engine = guard.as_mut().ok_or("Canvas engine not initialized")?;
    engine.add_edge(&canvas_id, edge).map_err(|e| e.to_string())
}

/// 保存画布为 JSON —— 替代原 CanvasEvent.SaveJson
pub fn canvas_save_canvas(canvas_id: String, path: String) -> Result<(), String> {
    let guard = CANVAS_ENGINE.lock();
    let engine = guard.as_ref().ok_or("Canvas engine not initialized")?;
    engine.save_canvas(&canvas_id, &path).map_err(|e| e.to_string())
}

/// 从 JSON 加载画布 —— 替代原 CanvasEvent.LoadJson
pub fn canvas_load_canvas(path: String) -> Result<String, String> {
    let mut guard = CANVAS_ENGINE.lock();
    let engine = guard.as_mut().ok_or("Canvas engine not initialized")?;
    let canvas = engine.load_canvas(&path).map_err(|e| e.to_string())?;
    Ok(serde_json::to_string(&canvas).unwrap_or_default())
}

// ── 数据库 API ────────────────────────────────────────────────────────

/// 创建数据库 —— 替代原 DatabaseEvent.CreateDatabase
pub fn create_database(name: String) -> Result<String, String> {
    let guard = DATABASE_ENGINE.lock();
    let engine = guard.as_ref().ok_or("Database engine not initialized")?;
    match engine.create_database(&name) {
        Ok(db) => Ok(serde_json::to_string(&db).unwrap_or_default()),
        Err(e) => Err(e.to_string()),
    }
}

/// 评估公式 —— 替代原 DatabaseEvent.EvaluateFormula
///
/// 返回 JSON 序列化的结果字符串，避免 FRB 对 serde_json::Value 的 opaque 类型处理。
/// 调用方可用 dart:convert jsonDecode 解析。
pub fn evaluate_formula(formula: String, row_values: String, all_rows: String) -> Result<String, String> {
    let rv: HashMap<String, serde_json::Value> = serde_json::from_str(&row_values)
        .map_err(|e| e.to_string())?;
    let ar: Vec<HashMap<String, serde_json::Value>> = serde_json::from_str(&all_rows)
        .map_err(|e| e.to_string())?;
    let result = eval_formula(&formula, &rv, &ar).map_err(|e| e)?;
    serde_json::to_string(&result).map_err(|e| e.to_string())
}

/// 添加数据库视图 —— 替代原 DatabaseEvent.AddView
pub fn database_add_view(db_id: String, name: String, view_type: String) -> Result<String, String> {
    let did = Uuid::parse_str(&db_id).map_err(|e| e.to_string())?;
    let vt: devnote_database::ViewType = serde_json::from_value(serde_json::Value::String(view_type))
        .map_err(|e| e.to_string())?;
    let guard = DATABASE_ENGINE.lock();
    let engine = guard.as_ref().ok_or("Database engine not initialized")?;
    match engine.add_view(&did, &name, vt) {
        Ok(view) => Ok(serde_json::to_string(&view).unwrap_or_default()),
        Err(e) => Err(e.to_string()),
    }
}

/// 查询数据库行 —— 替代原 DatabaseEvent.QueryRows
pub fn database_query_rows(db_id: String) -> Result<String, String> {
    let did = Uuid::parse_str(&db_id).map_err(|e| e.to_string())?;
    let guard = DATABASE_ENGINE.lock();
    let engine = guard.as_ref().ok_or("Database engine not initialized")?;
    match engine.get_rows(&did) {
        Ok(rows) => Ok(serde_json::to_string(&rows).unwrap_or_default()),
        Err(e) => Err(e.to_string()),
    }
}

// ── 图谱 API ──────────────────────────────────────────────────────────

/// 计算中心性 —— 替代原 GraphEvent.CalculateCentrality
pub fn calculate_centrality() -> Result<String, String> {
    let guard = GRAPH_ENGINE.lock();
    let engine = guard.as_ref().ok_or("Graph engine not initialized")?;
    let result = engine.calculate_centrality().map_err(|e| e.to_string())?;
    Ok(serde_json::to_string(&result).unwrap_or_default())
}

/// 检测聚类 —— 替代原 GraphEvent.DetectClusters
pub fn detect_clusters() -> Result<String, String> {
    let guard = GRAPH_ENGINE.lock();
    let engine = guard.as_ref().ok_or("Graph engine not initialized")?;
    let result = engine.detect_clusters().map_err(|e| e.to_string())?;
    Ok(serde_json::to_string(&result).unwrap_or_default())
}

// ── 闪卡 API ──────────────────────────────────────────────────────────

/// 创建卡组 —— 替代原 FlashcardEvent.CreateDeck
pub fn create_deck(name: String, description: String) -> Result<String, String> {
    let guard = FLASHCARD_ENGINE.lock();
    let engine = guard.as_ref().ok_or("Flashcard engine not initialized")?;
    let deck = engine.create_deck(&name, &description).map_err(|e| e.to_string())?;
    Ok(serde_json::to_string(&deck).unwrap_or_default())
}

/// 复习卡片 —— 替代原 FlashcardEvent.ReviewCard
pub fn review_flashcard(flashcard_id: String, quality: u8) -> Result<String, String> {
    let fid = Uuid::parse_str(&flashcard_id).map_err(|e| e.to_string())?;
    let mut guard = FLASHCARD_ENGINE.lock();
    let engine = guard.as_mut().ok_or("Flashcard engine not initialized")?;
    let record = engine.review_flashcard(&fid, quality).map_err(|e| e.to_string())?;
    Ok(serde_json::to_string(&record).unwrap_or_default())
}

/// 获取待复习卡片 —— 替代原 FlashcardEvent.GetDueCards
pub fn get_due_cards(deck_id: String, limit: Option<usize>) -> Result<String, String> {
    let did = Uuid::parse_str(&deck_id).map_err(|e| e.to_string())?;
    let lim = limit.unwrap_or(50);
    let guard = FLASHCARD_ENGINE.lock();
    let engine = guard.as_ref().ok_or("Flashcard engine not initialized")?;
    let cards = engine.get_due_cards(&did, lim).map_err(|e| e.to_string())?;
    Ok(serde_json::to_string(&cards).unwrap_or_default())
}

// ── CRDT API ──────────────────────────────────────────────────────────

/// CRDT 合并 —— 替代原 CRDTEvent.Merge
pub fn crdt_merge(doc_id: String, device_id: String, remote_ops_json: String) -> Result<MergeResult, String> {
    let ops: Vec<Operation> = serde_json::from_str(&remote_ops_json).map_err(|e| e.to_string())?;
    let mut docs = CRDT_DOCS.lock();
    let doc = docs.entry(doc_id.clone())
        .or_insert_with(|| CRDTDocument::new(doc_id, device_id));
    let applied = merge_documents(doc, ops).map_err(|e| e.to_string())?;
    Ok(MergeResult {
        applied_count: applied.len(),
        conflicts: applied.iter().filter_map(|op| {
            if matches!(op, Operation::Replace { .. }) {
                Some(format!("{:?}", op))
            } else {
                None
            }
        }).collect(),
    })
}

// ── 格式 API ──────────────────────────────────────────────────────────

/// 导入 Markdown —— 替代原 FormatEvent.ImportMarkdown
pub fn import_markdown(path: String) -> Result<String, String> {
    let importer = MarkdownImporter::new();
    let result = importer.import(Path::new(&path), ImportFormat::Markdown)
        .map_err(|e| e.to_string())?;
    Ok(serde_json::to_string(&result).unwrap_or_default())
}

/// 导出 Markdown —— 替代原 FormatEvent.ExportMarkdown
pub fn export_markdown(notes_json: String, path: String) -> Result<(), String> {
    let notes: Vec<devnote_extensions::format::NoteData> = serde_json::from_str(&notes_json)
        .map_err(|e| e.to_string())?;
    let exporter = MarkdownExporter::new();
    exporter.export(&notes, Path::new(&path), ExportFormat::Markdown)
        .map_err(|e| e.to_string())
}

// ── 语音转文字 API ────────────────────────────────────────────────────

/// 语音转文字结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscribeResultFfi {
    pub text: String,
    pub duration_ms: u64,
    pub segments: Vec<TranscriptSegmentFfi>,
}

/// 转写片段（带时间戳）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptSegmentFfi {
    pub text: String,
    pub start_ms: u64,
    pub end_ms: u64,
}

/// 语音转文字 —— 集成 whisper-rs 进行本地语音转文字
///
/// 当前为接口框架，实际转写逻辑待 whisper-rs 集成后实现。
/// 调用方应捕获返回的 Err 并降级为平台原生 API。
pub fn transcribe_audio(audio_base64: String, lang: String) -> Result<TranscribeResultFfi, String> {
    let _ = audio_base64;
    let _ = lang;
    Err("Speech-to-text is not yet available. Whisper model integration pending.".to_string())
}

// ── OCR API ──────────────────────────────────────────────────────────
// P0-2: OCR 文字识别 + 图片搜索
// 基于 devnote-ocr crate（ocrs 纯 Rust OCR 引擎），识别图片中的文字并纳入全文搜索索引

/// OCR 识别结果（FFI 传输结构）—— FRB 自动生成对应 Dart 类
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OcrResultFfi {
    pub text: String,
    pub lines: Vec<String>,
    pub confidence: f32,
}

/// OCR 识别图片中的文字 —— 替代原 OcrEvent.Recognize
/// image_base64: base64 编码的图片数据（支持 PNG/JPEG/WebP）
/// 返回识别出的全文
pub fn ocr_recognize_image(image_base64: String) -> Result<String, String> {
    let mut engine = devnote_extensions::ocr::OcrEngine::new();
    let result = engine.recognize_from_base64(&image_base64)
        .map_err(|e| e.to_string())?;
    Ok(result.text)
}

/// OCR 识别并返回结构化结果（含按行分割与置信度）
pub fn ocr_recognize_image_detailed(image_base64: String) -> Result<OcrResultFfi, String> {
    let mut engine = devnote_extensions::ocr::OcrEngine::new();
    let result = engine.recognize_from_base64(&image_base64)
        .map_err(|e| e.to_string())?;
    Ok(OcrResultFfi {
        text: result.text,
        lines: result.lines,
        confidence: result.confidence,
    })
}

/// 将 OCR 识别文本纳入笔记的全文搜索索引 —— 替代原 OcrEvent.IndexImage
/// 将 OCR 文本追加到笔记现有内容后重新索引，使图片中的文字可被全文检索
pub fn index_ocr_text(note_id: String, ocr_text: String) -> Result<(), String> {
    let uid = Uuid::parse_str(&note_id).map_err(|e| e.to_string())?;
    let note = {
        let guard = NOTE_REPO.lock();
        let repo = guard.as_ref().ok_or("Persistence engine not initialized")?;
        repo.get_note(&uid).map_err(|e| e.to_string())?
            .ok_or("Note not found")?
    };
    let mut content = extract_content(&note);
    if !ocr_text.is_empty() {
        if !content.is_empty() {
            content.push('\n');
        }
        content.push_str("[OCR] ");
        content.push_str(&ocr_text);
    }
    let sguard = SEARCH_ENGINE.lock();
    let engine = sguard.as_ref().ok_or("Search engine not initialized")?;
    engine.index_note_with_meta(&note.id, &note.title, &content, &note.folder_id, &[], &note.updated_at)
        .map_err(|e| e.to_string())
}

// ── Vault 保险库 API ──────────────────────────────────────────────────
// P1-7: Vault 保险库（敏感笔记二次加密）
// 对标 Notesnook 的 Vault 功能：使用独立密码对敏感笔记进行二次加密

/// Vault 加密数据（FFI 传输结构）—— FRB 自动生成对应 Dart 类
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultEncryptedDataFfi {
    pub ciphertext: String,
    pub salt: String,
    pub nonce: String,
    pub memory_cost: u32,
    pub time_cost: u32,
    pub parallelism: u32,
}

/// Vault 加密 —— 使用用户密码对明文进行加密
/// 采用 Argon2id 密钥派生 + XChaCha20-Poly1305 加密
pub fn vault_encrypt(password: String, plaintext: String) -> Result<VaultEncryptedDataFfi, String> {
    let result = devnote_crypto::vault_encrypt(&password, &plaintext)
        .map_err(|e| e.to_string())?;
    Ok(VaultEncryptedDataFfi {
        ciphertext: result.ciphertext,
        salt: result.salt,
        nonce: result.nonce,
        memory_cost: result.memory_cost,
        time_cost: result.time_cost,
        parallelism: result.parallelism,
    })
}

/// Vault 解密 —— 使用用户密码对密文进行解密
pub fn vault_decrypt(password: String, encrypted: VaultEncryptedDataFfi) -> Result<String, String> {
    let encrypted_data = devnote_crypto::VaultEncryptedData {
        ciphertext: encrypted.ciphertext,
        salt: encrypted.salt,
        nonce: encrypted.nonce,
        memory_cost: encrypted.memory_cost,
        time_cost: encrypted.time_cost,
        parallelism: encrypted.parallelism,
    };
    devnote_crypto::vault_decrypt(&password, &encrypted_data)
        .map_err(|e| e.to_string())
}

/// 验证 Vault 密码 —— 通过尝试解密测试向量验证密码是否正确
pub fn vault_verify_password(password: String, encrypted: VaultEncryptedDataFfi) -> bool {
    let encrypted_data = devnote_crypto::VaultEncryptedData {
        ciphertext: encrypted.ciphertext,
        salt: encrypted.salt,
        nonce: encrypted.nonce,
        memory_cost: encrypted.memory_cost,
        time_cost: encrypted.time_cost,
        parallelism: encrypted.parallelism,
    };
    devnote_crypto::vault_verify_password(&password, &encrypted_data)
}

// ── 手写公式识别 API ─────────────────────────────────────────────────
// P2-9: 基于 devnote-math-ink crate 的手写 LaTeX 公式识别
// 替代原 C ABI: math_ink_recognize / math_ink_free_result

/// 手写笔触点
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InkStrokeFfi {
    pub points: Vec<(f32, f32)>,
    pub pressure: f32,
    pub timestamp: u64,
}

/// 手写公式识别结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MathRecognitionResultFfi {
    pub latex: String,
    pub confidence: f32,
    pub alternatives: Vec<String>,
}

/// 识别手写公式 —— 替代原 C ABI math_ink_recognize
///
/// 输入 JSON 序列化的笔触列表，返回 LaTeX 识别结果。
pub fn math_ink_recognize(strokes_json: String) -> Result<MathRecognitionResultFfi, String> {
    let strokes: Vec<devnote_extensions::math_ink::InkStroke> = serde_json::from_str(&strokes_json)
        .map_err(|e| e.to_string())?;
    let recognizer = devnote_extensions::math_ink::MathInkRecognizer::new();
    let result = recognizer.recognize(strokes);
    Ok(MathRecognitionResultFfi {
        latex: result.latex,
        confidence: result.confidence,
        alternatives: result.alternatives,
    })
}
