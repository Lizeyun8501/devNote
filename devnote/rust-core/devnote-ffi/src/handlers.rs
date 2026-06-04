use super::*;
use devnote_core::models::Folder;
use devnote_core::traits::NoteRepository;
use devnote_crypto::{CryptoConfig, CryptoEngine, DefaultCryptoEngine};
use devnote_database::{DatabaseEngine, ViewType};
use devnote_database::formula::eval_formula;
use devnote_editor::{BlockEditor, BlockType, DefaultBlockEditor};
use devnote_flashcard::FlashcardEngine;
use devnote_format::{FormatExporter, FormatImporter, HtmlExporter, MarkdownExporter, MarkdownImporter, ObsidianImporter, ImportFormat, ExportFormat};
use devnote_graph::GraphEngine;
use devnote_object::ObjectEngine;
use devnote_persistence::SqliteNoteRepository;
use devnote_search::SearchEngine;
use devnote_sync::{ClientSyncEngine, SyncEngine};
use devnote_canvas::{CanvasEngine, LayoutType};
use devnote_crdt::{merge_documents, CRDTDocument, Operation};
use lazy_static::lazy_static;
use parking_lot::Mutex;
use serde::Deserialize;
use std::collections::HashMap;
use std::path::Path;
use std::sync::RwLock;
use uuid::Uuid;

type EventHandler = Box<dyn Fn(Option<&str>) -> DispatchResponse + Send + Sync>;

lazy_static! {
    static ref EVENT_REGISTRY: RwLock<HashMap<String, EventHandler>> =
        RwLock::new(HashMap::new());

    static ref NOTE_REPO: Mutex<Option<SqliteNoteRepository>> = Mutex::new(None);
    static ref BLOCK_EDITOR: Mutex<Option<DefaultBlockEditor>> = Mutex::new(None);
    static ref SEARCH_ENGINE: Mutex<Option<devnote_search::SqliteSearchEngine>> = Mutex::new(None);
    static ref CRYPTO_ENGINE: DefaultCryptoEngine =
        DefaultCryptoEngine::new(CryptoConfig::default());
    static ref SYNC_ENGINE: Mutex<Option<ClientSyncEngine>> = Mutex::new(None);
    static ref CANVAS_ENGINE: Mutex<Option<CanvasEngine>> = Mutex::new(None);
    static ref DATABASE_ENGINE: Mutex<Option<devnote_database::SqliteDatabaseEngine>> = Mutex::new(None);
    static ref OBJECT_ENGINE: Mutex<Option<devnote_object::SqliteObjectEngine>> = Mutex::new(None);
    static ref GRAPH_ENGINE: Mutex<Option<devnote_graph::SqliteGraphEngine>> = Mutex::new(None);
    static ref FLASHCARD_ENGINE: Mutex<Option<devnote_flashcard::SqliteFlashcardEngine>> = Mutex::new(None);
    static ref CRDT_DOCS: Mutex<HashMap<String, CRDTDocument>> = Mutex::new(HashMap::new());
}

pub fn register_handler(event: &str, handler: EventHandler) {
    EVENT_REGISTRY
        .write()
        .unwrap()
        .insert(event.to_string(), handler);
}

pub fn handle_dispatch(event: &str, payload: Option<&str>) -> DispatchResponse {
    let registry = EVENT_REGISTRY.read().unwrap();
    match registry.get(event) {
        Some(handler) => handler(payload),
        None => DispatchResponse::error(
            FFIErrorCode::NotFound,
            &format!("Unknown event: {}", event),
        ),
    }
}

pub fn register_all_handlers() {
    init_engines();

    register_note_handlers();
    register_folder_handlers();
    register_tag_handlers();
    register_editor_handlers();
    register_search_handlers();
    register_crypto_handlers();
    register_sync_handlers();
    register_format_handlers();
    register_canvas_handlers();
    register_database_handlers();
    register_object_handlers();
    register_graph_handlers();
    register_flashcard_handlers();
    register_crdt_handlers();
    register_plugin_handlers();
    register_p2p_handlers();
    register_system_handlers();
}

fn init_engines() {
    if let Ok(repo) = SqliteNoteRepository::in_memory() {
        *NOTE_REPO.lock() = Some(repo);
    }
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
}

// ── Helper functions ──────────────────────────────────────────────────────

fn parse_payload<T: serde::de::DeserializeOwned>(payload: Option<&str>) -> Result<T, DispatchResponse> {
    let p = match payload {
        Some(p) => p,
        None => return Err(DispatchResponse::error(FFIErrorCode::InvalidArgument, "Missing payload")),
    };
    serde_json::from_str(p)
        .map_err(|e| DispatchResponse::error(FFIErrorCode::InvalidArgument, &e.to_string()))
}

fn serialize_result<T: serde::Serialize>(result: anyhow::Result<T>) -> DispatchResponse {
    match result {
        Ok(data) => match serde_json::to_string(&data) {
            Ok(json) => DispatchResponse::success(&json),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        },
        Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
    }
}

fn parse_uuid(s: &str) -> Result<Uuid, DispatchResponse> {
    Uuid::parse_str(s)
        .map_err(|e| DispatchResponse::error(FFIErrorCode::InvalidArgument, &format!("Invalid UUID: {}", e)))
}

// ── Note handlers ─────────────────────────────────────────────────────────

fn register_note_handlers() {
    register_handler("NoteEvent.CreateNote", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            title: String,
            content: String,
            folder_id: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let folder_id = match parse_uuid(&req.folder_id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let guard = NOTE_REPO.lock();
        let repo = match guard.as_ref() {
            Some(r) => r,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Persistence engine not initialized"),
        };
        serialize_result(repo.create_note(&req.title, &req.content, &folder_id))
    }));

    register_handler("NoteEvent.GetNote", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            id: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let id = match parse_uuid(&req.id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let guard = NOTE_REPO.lock();
        let repo = match guard.as_ref() {
            Some(r) => r,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Persistence engine not initialized"),
        };
        match repo.get_note(&id) {
            Ok(Some(note)) => serialize_result(Ok(note)),
            Ok(None) => DispatchResponse::error(FFIErrorCode::NotFound, "Note not found"),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));

    register_handler("NoteEvent.UpdateNote", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            id: String,
            title: String,
            content: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let id = match parse_uuid(&req.id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let guard = NOTE_REPO.lock();
        let repo = match guard.as_ref() {
            Some(r) => r,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Persistence engine not initialized"),
        };
        serialize_result(repo.update_note(&id, &req.title, &req.content))
    }));

    register_handler("NoteEvent.DeleteNote", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            id: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let id = match parse_uuid(&req.id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let guard = NOTE_REPO.lock();
        let repo = match guard.as_ref() {
            Some(r) => r,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Persistence engine not initialized"),
        };
        match repo.delete_note(&id) {
            Ok(()) => DispatchResponse::success("true"),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));

    register_handler("NoteEvent.ListNotes", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            folder_id: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let folder_id = match parse_uuid(&req.folder_id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let guard = NOTE_REPO.lock();
        let repo = match guard.as_ref() {
            Some(r) => r,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Persistence engine not initialized"),
        };
        serialize_result(repo.list_notes(&folder_id))
    }));
}

// ── Folder handlers ───────────────────────────────────────────────────────

fn register_folder_handlers() {
    register_handler("FolderEvent.CreateFolder", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            name: String,
            parent_id: Option<String>,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let parent_id = match req.parent_id {
            Some(ref s) => Some(match parse_uuid(s) { Ok(id) => id, Err(e) => return e }),
            None => None,
        };
        let guard = NOTE_REPO.lock();
        let repo = match guard.as_ref() {
            Some(r) => r,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Persistence engine not initialized"),
        };
        serialize_result(repo.create_folder(&req.name, parent_id.as_ref()))
    }));

    register_handler("FolderEvent.GetFolder", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            id: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let id = match parse_uuid(&req.id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let mut guard = NOTE_REPO.lock();
        let repo = match guard.as_mut() {
            Some(r) => r,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Persistence engine not initialized"),
        };
        match NoteRepository::get_folder(repo, &id) {
            Ok(Some(folder)) => serialize_result(Ok(folder)),
            Ok(None) => DispatchResponse::error(FFIErrorCode::NotFound, "Folder not found"),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));

    register_handler("FolderEvent.UpdateFolder", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            id: String,
            name: String,
            parent_id: Option<String>,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let id = match parse_uuid(&req.id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let parent_id = match req.parent_id {
            Some(ref s) => Some(match parse_uuid(s) { Ok(id) => id, Err(e) => return e }),
            None => None,
        };
        let mut guard = NOTE_REPO.lock();
        let repo = match guard.as_mut() {
            Some(r) => r,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Persistence engine not initialized"),
        };
        // Get existing folder first to preserve timestamps and sort_order
        let existing = match NoteRepository::get_folder(repo, &id) {
            Ok(Some(f)) => f,
            Ok(None) => return DispatchResponse::error(FFIErrorCode::NotFound, "Folder not found"),
            Err(e) => return DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        };
        let folder = Folder {
            id,
            name: req.name,
            parent_id,
            sort_order: existing.sort_order,
            created_at: existing.created_at,
            updated_at: chrono::Utc::now(),
        };
        serialize_result(NoteRepository::update_folder(repo, folder))
    }));

    register_handler("FolderEvent.DeleteFolder", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            id: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let id = match parse_uuid(&req.id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let mut guard = NOTE_REPO.lock();
        let repo = match guard.as_mut() {
            Some(r) => r,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Persistence engine not initialized"),
        };
        match NoteRepository::delete_folder(repo, &id) {
            Ok(()) => DispatchResponse::success("true"),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));

    register_handler("FolderEvent.ListFolders", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            parent_id: Option<String>,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let parent_id = match req.parent_id {
            Some(ref s) => Some(match parse_uuid(s) { Ok(id) => id, Err(e) => return e }),
            None => None,
        };
        let guard = NOTE_REPO.lock();
        let repo = match guard.as_ref() {
            Some(r) => r,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Persistence engine not initialized"),
        };
        serialize_result(repo.list_folders(parent_id.as_ref()))
    }));
}

// ── Tag handlers ──────────────────────────────────────────────────────────

fn register_tag_handlers() {
    register_handler("TagEvent.CreateTag", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            name: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let guard = NOTE_REPO.lock();
        let repo = match guard.as_ref() {
            Some(r) => r,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Persistence engine not initialized"),
        };
        serialize_result(repo.create_tag(&req.name))
    }));

    register_handler("TagEvent.ListTags", Box::new(|_payload| {
        let mut guard = NOTE_REPO.lock();
        let repo = match guard.as_mut() {
            Some(r) => r,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Persistence engine not initialized"),
        };
        serialize_result(NoteRepository::list_tags(repo))
    }));

    register_handler("TagEvent.DeleteTag", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            id: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let id = match parse_uuid(&req.id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let mut guard = NOTE_REPO.lock();
        let repo = match guard.as_mut() {
            Some(r) => r,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Persistence engine not initialized"),
        };
        match NoteRepository::delete_tag(repo, &id) {
            Ok(()) => DispatchResponse::success("true"),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));
}

// ── Editor handlers ───────────────────────────────────────────────────────

fn register_editor_handlers() {
    register_handler("EditorEvent.InsertBlock", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            note_id: String,
            block_type: BlockType,
            content: String,
            position: Option<usize>,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let note_id = match parse_uuid(&req.note_id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let position = req.position.unwrap_or(0);
        let mut guard = BLOCK_EDITOR.lock();
        let editor = match guard.as_mut() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Editor engine not initialized"),
        };
        serialize_result(editor.create_block(note_id, req.block_type, req.content, position))
    }));

    register_handler("EditorEvent.UpdateBlock", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            id: String,
            content: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let id = match parse_uuid(&req.id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let mut guard = BLOCK_EDITOR.lock();
        let editor = match guard.as_mut() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Editor engine not initialized"),
        };
        match editor.update_block(&id, req.content) {
            Ok(()) => DispatchResponse::success("true"),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));

    register_handler("EditorEvent.DeleteBlock", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            id: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let id = match parse_uuid(&req.id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let mut guard = BLOCK_EDITOR.lock();
        let editor = match guard.as_mut() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Editor engine not initialized"),
        };
        match editor.delete_block(&id) {
            Ok(()) => DispatchResponse::success("true"),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));

    register_handler("EditorEvent.GetBlocks", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            note_id: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let note_id = match parse_uuid(&req.note_id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let mut guard = BLOCK_EDITOR.lock();
        let editor = match guard.as_mut() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Editor engine not initialized"),
        };
        serialize_result(editor.list_blocks(&note_id))
    }));

    register_handler("EditorEvent.ParseMarkdown", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            content: String,
            note_id: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let note_id = match parse_uuid(&req.note_id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let mut guard = BLOCK_EDITOR.lock();
        let editor = match guard.as_mut() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Editor engine not initialized"),
        };
        serialize_result(editor.parse_markdown(&req.content, note_id))
    }));
}

// ── Search handlers ───────────────────────────────────────────────────────

fn register_search_handlers() {
    register_handler("SearchEvent.Search", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            query: String,
            limit: Option<usize>,
            offset: Option<usize>,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let limit = req.limit.unwrap_or(50);
        let offset = req.offset.unwrap_or(0);
        let guard = SEARCH_ENGINE.lock();
        let engine = match guard.as_ref() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Search engine not initialized"),
        };
        serialize_result(engine.search(&req.query, limit, offset))
    }));

    register_handler("SearchEvent.SearchWithFilter", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            query: String,
            filter: devnote_search::SearchFilter,
            limit: Option<usize>,
            offset: Option<usize>,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let limit = req.limit.unwrap_or(50);
        let offset = req.offset.unwrap_or(0);
        let guard = SEARCH_ENGINE.lock();
        let engine = match guard.as_ref() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Search engine not initialized"),
        };
        serialize_result(engine.search_with_filter(&req.query, &req.filter, limit, offset))
    }));
}

// ── Crypto handlers ───────────────────────────────────────────────────────

fn register_crypto_handlers() {
    register_handler("CryptoEvent.Encrypt", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            plaintext_base64: String,
            key_base64: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let plaintext = match base64::engine::general_purpose::STANDARD.decode(&req.plaintext_base64) {
            Ok(d) => d,
            Err(e) => return DispatchResponse::error(FFIErrorCode::InvalidArgument, &format!("Invalid base64 plaintext: {}", e)),
        };
        let key = match base64::engine::general_purpose::STANDARD.decode(&req.key_base64) {
            Ok(d) => d,
            Err(e) => return DispatchResponse::error(FFIErrorCode::InvalidArgument, &format!("Invalid base64 key: {}", e)),
        };
        match CRYPTO_ENGINE.encrypt(&plaintext, &key) {
            Ok(ciphertext) => {
                let encoded = base64::engine::general_purpose::STANDARD.encode(&ciphertext);
                DispatchResponse::success(&serde_json::to_string(&encoded).unwrap_or_default())
            }
            Err(e) => DispatchResponse::error(FFIErrorCode::CryptoError, &e.to_string()),
        }
    }));

    register_handler("CryptoEvent.Decrypt", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            ciphertext_base64: String,
            key_base64: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let ciphertext = match base64::engine::general_purpose::STANDARD.decode(&req.ciphertext_base64) {
            Ok(d) => d,
            Err(e) => return DispatchResponse::error(FFIErrorCode::InvalidArgument, &format!("Invalid base64 ciphertext: {}", e)),
        };
        let key = match base64::engine::general_purpose::STANDARD.decode(&req.key_base64) {
            Ok(d) => d,
            Err(e) => return DispatchResponse::error(FFIErrorCode::InvalidArgument, &format!("Invalid base64 key: {}", e)),
        };
        match CRYPTO_ENGINE.decrypt(&ciphertext, &key) {
            Ok(plaintext) => {
                let encoded = base64::engine::general_purpose::STANDARD.encode(&plaintext);
                DispatchResponse::success(&serde_json::to_string(&encoded).unwrap_or_default())
            }
            Err(e) => DispatchResponse::error(FFIErrorCode::CryptoError, &e.to_string()),
        }
    }));

    register_handler("CryptoEvent.DeriveKey", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            password: String,
            salt_base64: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let salt = match base64::engine::general_purpose::STANDARD.decode(&req.salt_base64) {
            Ok(d) => d,
            Err(e) => return DispatchResponse::error(FFIErrorCode::InvalidArgument, &format!("Invalid base64 salt: {}", e)),
        };
        match CRYPTO_ENGINE.derive_key(&req.password, &salt) {
            Ok(key) => {
                let encoded = base64::engine::general_purpose::STANDARD.encode(&key);
                DispatchResponse::success(&serde_json::to_string(&encoded).unwrap_or_default())
            }
            Err(e) => DispatchResponse::error(FFIErrorCode::CryptoError, &e.to_string()),
        }
    }));
}

// ── Sync handlers ─────────────────────────────────────────────────────────

fn register_sync_handlers() {
    register_handler("SyncEvent.PushChanges", Box::new(|_payload| {
        let mut guard = SYNC_ENGINE.lock();
        let engine = match guard.as_mut() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Sync engine not initialized"),
        };
        serialize_result(engine.push_changes().map_err(|e| anyhow::anyhow!(e)))
    }));

    register_handler("SyncEvent.PullChanges", Box::new(|_payload| {
        let mut guard = SYNC_ENGINE.lock();
        let engine = match guard.as_mut() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Sync engine not initialized"),
        };
        serialize_result(engine.pull_changes().map_err(|e| anyhow::anyhow!(e)))
    }));

    register_handler("SyncEvent.GetStatus", Box::new(|_payload| {
        let guard = SYNC_ENGINE.lock();
        let engine = match guard.as_ref() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Sync engine not initialized"),
        };
        let status = engine.get_status();
        serialize_result(Ok(status))
    }));
}

// ── Format handlers ───────────────────────────────────────────────────────

fn register_format_handlers() {
    register_handler("FormatEvent.ImportMarkdown", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            path: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let importer = MarkdownImporter::new();
        serialize_result(importer.import(Path::new(&req.path), ImportFormat::Markdown))
    }));

    register_handler("FormatEvent.ImportObsidian", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            path: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let importer = ObsidianImporter::new();
        serialize_result(importer.import(Path::new(&req.path), ImportFormat::Obsidian))
    }));

    register_handler("FormatEvent.ExportMarkdown", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            notes: Vec<devnote_format::NoteData>,
            path: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let exporter = MarkdownExporter::new();
        match exporter.export(&req.notes, Path::new(&req.path), ExportFormat::Markdown) {
            Ok(()) => DispatchResponse::success("true"),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));

    register_handler("FormatEvent.ExportHtml", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            notes: Vec<devnote_format::NoteData>,
            path: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let exporter = HtmlExporter::new();
        match exporter.export(&req.notes, Path::new(&req.path), ExportFormat::Html) {
            Ok(()) => DispatchResponse::success("true"),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));
}

// ── Canvas handlers ───────────────────────────────────────────────────────

fn register_canvas_handlers() {
    register_handler("CanvasEvent.AddNode", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            canvas_id: String,
            node: devnote_canvas::CanvasNode,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let mut guard = CANVAS_ENGINE.lock();
        let engine = match guard.as_mut() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Canvas engine not initialized"),
        };
        match engine.add_node(&req.canvas_id, req.node) {
            Ok(()) => DispatchResponse::success("true"),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));

    register_handler("CanvasEvent.RemoveNode", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            canvas_id: String,
            node_id: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let mut guard = CANVAS_ENGINE.lock();
        let engine = match guard.as_mut() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Canvas engine not initialized"),
        };
        match engine.remove_node(&req.canvas_id, &req.node_id) {
            Ok(()) => DispatchResponse::success("true"),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));

    register_handler("CanvasEvent.AddEdge", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            canvas_id: String,
            edge: devnote_canvas::CanvasEdge,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let mut guard = CANVAS_ENGINE.lock();
        let engine = match guard.as_mut() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Canvas engine not initialized"),
        };
        match engine.add_edge(&req.canvas_id, req.edge) {
            Ok(()) => DispatchResponse::success("true"),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));

    register_handler("CanvasEvent.AutoLayout", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            canvas_id: String,
            layout_type: LayoutType,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let mut guard = CANVAS_ENGINE.lock();
        let engine = match guard.as_mut() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Canvas engine not initialized"),
        };
        match engine.auto_layout(&req.canvas_id, req.layout_type) {
            Ok(()) => DispatchResponse::success("true"),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));

    register_handler("CanvasEvent.SaveJson", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            canvas_id: String,
            path: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let guard = CANVAS_ENGINE.lock();
        let engine = match guard.as_ref() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Canvas engine not initialized"),
        };
        match engine.save_canvas(&req.canvas_id, &req.path) {
            Ok(()) => DispatchResponse::success("true"),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));

    register_handler("CanvasEvent.LoadJson", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            path: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let mut guard = CANVAS_ENGINE.lock();
        let engine = match guard.as_mut() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Canvas engine not initialized"),
        };
        serialize_result(engine.load_canvas(&req.path).map_err(|e| anyhow::anyhow!(e)))
    }));
}

// ── Database handlers ─────────────────────────────────────────────────────

fn register_database_handlers() {
    register_handler("DatabaseEvent.CreateDatabase", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            name: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let guard = DATABASE_ENGINE.lock();
        let engine = match guard.as_ref() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Database engine not initialized"),
        };
        match engine.create_database(&req.name) {
            Ok(db) => serialize_result(Ok(db)),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));

    register_handler("DatabaseEvent.AddView", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            db_id: String,
            name: String,
            view_type: ViewType,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let db_id = match parse_uuid(&req.db_id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let guard = DATABASE_ENGINE.lock();
        let engine = match guard.as_ref() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Database engine not initialized"),
        };
        match engine.add_view(&db_id, &req.name, req.view_type) {
            Ok(view) => serialize_result(Ok(view)),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));

    register_handler("DatabaseEvent.QueryRows", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            db_id: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let db_id = match parse_uuid(&req.db_id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let guard = DATABASE_ENGINE.lock();
        let engine = match guard.as_ref() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Database engine not initialized"),
        };
        match engine.get_rows(&db_id) {
            Ok(rows) => serialize_result(Ok(rows)),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));

    register_handler("DatabaseEvent.EvaluateFormula", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            formula: String,
            row_values: HashMap<String, serde_json::Value>,
            all_rows: Vec<HashMap<String, serde_json::Value>>,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        match eval_formula(&req.formula, &req.row_values, &req.all_rows) {
            Ok(value) => DispatchResponse::success(&serde_json::to_string(&value).unwrap_or_default()),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e),
        }
    }));
}

// ── Object handlers ───────────────────────────────────────────────────────

fn register_object_handlers() {
    register_handler("ObjectEvent.CreateObjectType", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            name: String,
            icon: String,
            properties: Vec<devnote_object::ObjectProperty>,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let guard = OBJECT_ENGINE.lock();
        let engine = match guard.as_ref() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Object engine not initialized"),
        };
        serialize_result(engine.create_object_type(&req.name, &req.icon, req.properties).map_err(|e| anyhow::anyhow!(e)))
    }));

    register_handler("ObjectEvent.CreateObject", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            type_id: String,
            properties: serde_json::Value,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let type_id = match parse_uuid(&req.type_id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let guard = OBJECT_ENGINE.lock();
        let engine = match guard.as_ref() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Object engine not initialized"),
        };
        serialize_result(engine.create_object(&type_id, req.properties).map_err(|e| anyhow::anyhow!(e)))
    }));

    register_handler("ObjectEvent.GetObject", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            id: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let id = match parse_uuid(&req.id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let guard = OBJECT_ENGINE.lock();
        let engine = match guard.as_ref() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Object engine not initialized"),
        };
        match engine.get_object(&id) {
            Ok(obj) => serialize_result(Ok(obj)),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));
}

// ── Graph handlers ────────────────────────────────────────────────────────

fn register_graph_handlers() {
    register_handler("GraphEvent.BuildGraph", Box::new(|payload| {
        #[derive(Deserialize)]
        struct NoteInput {
            id: String,
            title: String,
            tags: Vec<String>,
            created_at: String,
            updated_at: String,
        }
        #[derive(Deserialize)]
        struct Req {
            notes: Vec<NoteInput>,
            folder_relations: Vec<(String, String)>,
            tag_relations: Vec<(String, String)>,
            reference_relations: Vec<(String, String)>,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let notes: Vec<(Uuid, String, Vec<String>, chrono::DateTime<chrono::Utc>, chrono::DateTime<chrono::Utc>)> = match req.notes.into_iter().map(|n| {
            let id = Uuid::parse_str(&n.id).map_err(|e| format!("{}", e))?;
            let created_at = n.created_at.parse().map_err(|e: chrono::ParseError| format!("{}", e))?;
            let updated_at = n.updated_at.parse().map_err(|e: chrono::ParseError| format!("{}", e))?;
            Ok((id, n.title, n.tags, created_at, updated_at))
        }).collect::<Result<Vec<_>, String>>() {
            Ok(n) => n,
            Err(e) => return DispatchResponse::error(FFIErrorCode::InvalidArgument, &e),
        };
        let folder_relations: Vec<(Uuid, Uuid)> = match req.folder_relations.into_iter().map(|(s, t)| {
            let sid = Uuid::parse_str(&s).map_err(|e| format!("{}", e))?;
            let tid = Uuid::parse_str(&t).map_err(|e| format!("{}", e))?;
            Ok((sid, tid))
        }).collect::<Result<Vec<_>, String>>() {
            Ok(r) => r,
            Err(e) => return DispatchResponse::error(FFIErrorCode::InvalidArgument, &e),
        };
        let tag_relations: Vec<(Uuid, String)> = req.tag_relations.into_iter().map(|(s, t)| {
            let sid = Uuid::parse_str(&s).unwrap_or(Uuid::nil());
            (sid, t)
        }).collect();
        let reference_relations: Vec<(Uuid, Uuid)> = match req.reference_relations.into_iter().map(|(s, t)| {
            let sid = Uuid::parse_str(&s).map_err(|e| format!("{}", e))?;
            let tid = Uuid::parse_str(&t).map_err(|e| format!("{}", e))?;
            Ok((sid, tid))
        }).collect::<Result<Vec<_>, String>>() {
            Ok(r) => r,
            Err(e) => return DispatchResponse::error(FFIErrorCode::InvalidArgument, &e),
        };
        let guard = GRAPH_ENGINE.lock();
        let engine = match guard.as_ref() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Graph engine not initialized"),
        };
        serialize_result(engine.build_graph(&notes, &folder_relations, &tag_relations, &reference_relations).map_err(|e| anyhow::anyhow!(e)))
    }));

    register_handler("GraphEvent.CalculateCentrality", Box::new(|_payload| {
        let guard = GRAPH_ENGINE.lock();
        let engine = match guard.as_ref() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Graph engine not initialized"),
        };
        serialize_result(engine.calculate_centrality().map_err(|e| anyhow::anyhow!(e)))
    }));

    register_handler("GraphEvent.DetectClusters", Box::new(|_payload| {
        let guard = GRAPH_ENGINE.lock();
        let engine = match guard.as_ref() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Graph engine not initialized"),
        };
        serialize_result(engine.detect_clusters().map_err(|e| anyhow::anyhow!(e)))
    }));
}

// ── Flashcard handlers ────────────────────────────────────────────────────

fn register_flashcard_handlers() {
    register_handler("FlashcardEvent.CreateDeck", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            name: String,
            description: String,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let guard = FLASHCARD_ENGINE.lock();
        let engine = match guard.as_ref() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Flashcard engine not initialized"),
        };
        serialize_result(engine.create_deck(&req.name, &req.description).map_err(|e| anyhow::anyhow!(e)))
    }));

    register_handler("FlashcardEvent.ReviewCard", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            flashcard_id: String,
            quality: u8,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let flashcard_id = match parse_uuid(&req.flashcard_id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let mut guard = FLASHCARD_ENGINE.lock();
        let engine = match guard.as_mut() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Flashcard engine not initialized"),
        };
        match engine.review_flashcard(&flashcard_id, req.quality) {
            Ok(record) => serialize_result(Ok(record)),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));

    register_handler("FlashcardEvent.GetDueCards", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            deck_id: String,
            limit: Option<usize>,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let deck_id = match parse_uuid(&req.deck_id) {
            Ok(id) => id,
            Err(e) => return e,
        };
        let limit = req.limit.unwrap_or(50);
        let guard = FLASHCARD_ENGINE.lock();
        let engine = match guard.as_ref() {
            Some(e) => e,
            None => return DispatchResponse::error(FFIErrorCode::NotConnected, "Flashcard engine not initialized"),
        };
        match engine.get_due_cards(&deck_id, limit) {
            Ok(cards) => serialize_result(Ok(cards)),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));
}

// ── CRDT handlers ────────────────────────────────────────────────────────

fn register_crdt_handlers() {
    // FFI dispatch 路由 —— 借鉴 AppFlowy 的 Event-Dispatch 模式，将 Flutter 事件路由到 Rust 业务 handler
    register_handler("CRDTEvent.Merge", Box::new(|payload| {
        #[derive(Deserialize)]
        struct Req {
            doc_id: String,
            device_id: String,
            remote_ops: Vec<Operation>,
        }
        let req = match parse_payload::<Req>(payload) {
            Ok(r) => r,
            Err(e) => return e,
        };
        let mut docs = CRDT_DOCS.lock();
        let doc = docs.entry(req.doc_id.clone())
            .or_insert_with(|| CRDTDocument::new(req.doc_id, req.device_id));
        match merge_documents(doc, req.remote_ops) {
            Ok(applied) => serialize_result(Ok(applied)),
            Err(e) => DispatchResponse::error(FFIErrorCode::InternalError, &e.to_string()),
        }
    }));
}

// ── Plugin handlers (stub — requires complex runtime setup) ───────────────

fn register_plugin_handlers() {
    register_handler("PluginEvent.LoadPlugin", Box::new(|_payload| {
        DispatchResponse::error(FFIErrorCode::NotImplemented, "Plugin system runs in Dart-side PluginManager (WASM sandbox); not available via FFI")
    }));

    register_handler("PluginEvent.ExecutePlugin", Box::new(|_payload| {
        DispatchResponse::error(FFIErrorCode::NotImplemented, "Plugin system runs in Dart-side PluginManager (WASM sandbox); not available via FFI")
    }));

    register_handler("PluginEvent.UnloadPlugin", Box::new(|_payload| {
        DispatchResponse::error(FFIErrorCode::NotImplemented, "Plugin system runs in Dart-side PluginManager (WASM sandbox); not available via FFI")
    }));
}

// ── P2P handlers (stub — requires async runtime) ──────────────────────────

fn register_p2p_handlers() {
    register_handler("P2PEvent.Start", Box::new(|_payload| {
        DispatchResponse::error(FFIErrorCode::NotImplemented, "P2P system runs in dedicated devnote-p2p crate (libp2p async runtime); not available via FFI")
    }));

    register_handler("P2PEvent.ConnectPeer", Box::new(|_payload| {
        DispatchResponse::error(FFIErrorCode::NotImplemented, "P2P system runs in dedicated devnote-p2p crate (libp2p async runtime); not available via FFI")
    }));

    register_handler("P2PEvent.SendData", Box::new(|_payload| {
        DispatchResponse::error(FFIErrorCode::NotImplemented, "P2P system runs in dedicated devnote-p2p crate (libp2p async runtime); not available via FFI")
    }));
}

// ── System handlers (FFI 版本协商 + 健康检查) ────────────────────────────
// 借鉴 AppFlowy 的 FFI 版本协商机制
// 来源: https://github.com/AppFlowy-IO/AppFlowy
// 借鉴内容: SystemEvent.GetVersion / SystemEvent.HealthCheck 事件名规范
//         + { api_version, rust_version, features[] } 的 JSON 返回结构
//
// Dart 端在 FFI 初始化后必须先调 GetVersion 协商协议版本，
// 防止 native 库与 UI 版本不匹配导致 dispatch 路由失败

/// FFI 协议版本 —— 与 Dart 端 lib/core/bridge/ffi_bridge.dart 的 kFFIApiVersion 严格一致
/// 协议变更时必须同步 +1 并在 migration_notes.md 中记录
pub const FFI_API_VERSION: u32 = 1;

fn register_system_handlers() {
    register_handler("SystemEvent.GetVersion", Box::new(|_payload| {
        let version_info = serde_json::json!({
            "api_version": FFI_API_VERSION,
            "rust_version": env!("CARGO_PKG_VERSION"),
            "compatible_min": 1u32,
            "features": [
                "sqlite_persistence",
                "sqlite_fts5_search",
                "xchacha20_poly1305",
                "argon2id",
                "bip39_recovery",
                "wasm_plugin_sandbox",
                "obsidian_import",
                "markdown_render",
            ],
            "build": {
                "target": std::env::consts::ARCH,
                "os": std::env::consts::OS,
            },
        });
        DispatchResponse::success(&version_info.to_string())
    }));

    register_handler("SystemEvent.HealthCheck", Box::new(|_payload| {
        let health = serde_json::json!({
            "status": "ok",
            "engines": {
                "persistence": NOTE_REPO.lock().is_some(),
                "editor": BLOCK_EDITOR.lock().is_some(),
                "search": SEARCH_ENGINE.lock().is_some(),
                "crypto": true,
                "sync": SYNC_ENGINE.lock().is_some(),
                "database": DATABASE_ENGINE.lock().is_some(),
                "object": OBJECT_ENGINE.lock().is_some(),
                "graph": GRAPH_ENGINE.lock().is_some(),
                "canvas": CANVAS_ENGINE.lock().is_some(),
                "format": true,
                "crdt": true,
                "flashcard": FLASHCARD_ENGINE.lock().is_some(),
            }
        });
        DispatchResponse::success(&health.to_string())
    }));
}
