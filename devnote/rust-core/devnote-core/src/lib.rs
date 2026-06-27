
//! DevNote 核心业务逻辑层 —— 定义所有核心数据类型、业务模型和领域服务
//! 遵循 DDD（领域驱动设计）分层架构，提供笔记(Note)、文件夹(Folder)、标签(Tag)等核心实体

pub mod models;
pub mod traits;

// P1 修复 (R6): 移除对下层实现 crate 的 `pub use` 重导出。
// 原实现重新导出 editor/crypto/search/sync/crdt/object 的全部公开 API，导致
// 依赖 devnote-core 的低层 crate（如 devnote-persistence）传递依赖 sync/search/crdt，
// 违反 ADR-003 五层架构（持久化层不应依赖同步/搜索层）。
// 现仅保留 devnote-core 自身定义的 models/traits 公开项；需要下层类型的调用方
// （如 devnote-ffi）应直接依赖对应 crate。
pub use models::{Permission, ResourceACL, Workspace, WorkspaceMember, check_permission, FeatureFlag, FeatureFlagKey};
