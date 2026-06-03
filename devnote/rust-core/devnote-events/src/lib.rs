use serde::{Deserialize, Serialize};

// ── Event Types ──────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum NoteEvent {
    CreateNote,
    ReadNote,
    UpdateNote,
    DeleteNote,
    ListNotes,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum FolderEvent {
    CreateFolder,
    ReadFolder,
    UpdateFolder,
    DeleteFolder,
    ListFolders,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TagEvent {
    CreateTag,
    ReadTag,
    UpdateTag,
    DeleteTag,
    ListTags,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum EditorEvent {
    InsertBlock,
    UpdateBlock,
    DeleteBlock,
    LoadDocument,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum SearchEvent {
    SearchNotes,
    SearchContent,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum CryptoEvent {
    EncryptData,
    DecryptData,
    GenerateKey,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum SyncEvent {
    StartSync,
    GetSyncStatus,
    ResolveConflict,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum FormatEvent {
    ExportMarkdown,
    ExportHtml,
    ImportMarkdown,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum CanvasEvent {
    CreateNode,
    UpdateNode,
    DeleteNode,
    CreateEdge,
    DeleteEdge,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum DatabaseEvent {
    CreateTable,
    InsertRow,
    UpdateRow,
    DeleteRow,
    QueryTable,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ObjectEvent {
    CreateObject,
    ReadObject,
    UpdateObject,
    DeleteObject,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum GraphEvent {
    CreateNode,
    UpdateNode,
    DeleteNode,
    QueryPath,
    GetNeighbors,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum FlashcardEvent {
    CreateDeck,
    AddCard,
    ReviewCard,
    GetDueCards,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PluginEvent {
    LoadPlugin,
    UnloadPlugin,
    ExecuteCommand,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum P2PEvent {
    ConnectPeer,
    DisconnectPeer,
    SendMessage,
    BroadcastMessage,
}

// ── Dispatch Types ───────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DispatchRequest {
    pub event: String,
    pub payload: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DispatchResponse {
    pub code: i32,
    pub message: String,
    pub data: Option<String>,
}

impl DispatchResponse {
    pub fn success(data: &str) -> Self {
        Self {
            code: 0,
            message: "ok".to_string(),
            data: Some(data.to_string()),
        }
    }

    pub fn error(code: i32, message: &str) -> Self {
        Self {
            code,
            message: message.to_string(),
            data: None,
        }
    }
}
