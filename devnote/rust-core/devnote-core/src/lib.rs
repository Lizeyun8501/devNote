
//! DevNote 核心业务逻辑层 —— 定义所有核心数据类型、业务模型和领域服务
//! 遵循 DDD（领域驱动设计）分层架构，提供笔记(Note)、文件夹(Folder)、标签(Tag)等核心实体

pub mod models;
pub mod traits;

pub use devnote_editor::{Block, BlockType, BlockEditor, DefaultBlockEditor, MarkdownParser};
pub use devnote_crypto::{CryptoEngine, CryptoError};
pub use devnote_search::{SearchEngine, SearchResult, SearchFilter, DateRange, Highlight, SqliteSearchEngine};
pub use devnote_crdt::{CRDTDocument, Operation, HLC, VectorClock, BlockCRDT, TextCRDT, ConflictInfo, ConflictType, CRDTError};
pub use devnote_events::{NoteEvent, FolderEvent, TagEvent, EditorEvent, SearchEvent, CryptoEvent, SyncEvent, FormatEvent, CanvasEvent, DatabaseEvent, ObjectEvent, GraphEvent, FlashcardEvent, PluginEvent, P2PEvent, DispatchRequest, DispatchResponse};
pub use devnote_sync::{SyncEngine, SyncError, SyncInfo, SyncStatus, ClientSyncEngine, LocalState, RemoteChanges, MergeResult};
pub use devnote_object::{Object, ObjectEngine, SqliteObjectEngine, ObjectError};
pub use models::{Permission, ResourceACL, Workspace, WorkspaceMember, check_permission, FeatureFlag, FeatureFlagKey};
