//! DevNote 事件系统 —— 定义所有跨层通信的事件类型
//! 每个事件枚举对应一个业务域，用于 Flutter UI → Rust 核心引擎的事件分发
//!
//! 借鉴 AppFlowy 的 Event-Dispatch 模式
//! 来源: https://github.com/AppFlowy-IO/AppFlowy
//! 借鉴内容: 领域事件枚举 + DispatchRequest/Response 的请求-响应模式

use serde::{Deserialize, Serialize};

// ── Event Types ──────────────────────────────────────────────────────────────

/// 笔记事件 —— 笔记的 CRUD 操作事件
/// CreateNote: 创建新笔记
/// ReadNote: 读取单个笔记详情
/// UpdateNote: 更新笔记内容或标题
/// DeleteNote: 删除笔记（软删除）
/// ListNotes: 列出某个文件夹下的所有笔记
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum NoteEvent {
    CreateNote,
    ReadNote,
    UpdateNote,
    DeleteNote,
    ListNotes,
}

/// 文件夹事件 —— 文件夹树形结构的 CRUD 操作
/// CreateFolder: 创建子文件夹
/// ReadFolder: 读取文件夹信息
/// UpdateFolder: 重命名或移动文件夹
/// DeleteFolder: 删除文件夹及其子内容
/// ListFolders: 列出子文件夹
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum FolderEvent {
    CreateFolder,
    ReadFolder,
    UpdateFolder,
    DeleteFolder,
    ListFolders,
}

/// 标签事件 —— 扁平标签的 CRUD 操作
/// CreateTag: 创建新标签
/// ReadTag: 读取标签详情
/// UpdateTag: 更新标签名称或颜色
/// DeleteTag: 删除标签
/// ListTags: 列出所有标签
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum TagEvent {
    CreateTag,
    ReadTag,
    UpdateTag,
    DeleteTag,
    ListTags,
}

/// 编辑器事件 —— 块级别的内容编辑操作
/// InsertBlock: 在指定位置插入一个内容块
/// UpdateBlock: 更新某个块的内容
/// DeleteBlock: 删除某个块
/// LoadDocument: 加载整个文档的所有块
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum EditorEvent {
    InsertBlock,
    UpdateBlock,
    DeleteBlock,
    LoadDocument,
}

/// 搜索事件 —— 全文检索操作
/// SearchNotes: 按标题搜索笔记
/// SearchContent: 按内容全文搜索笔记
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum SearchEvent {
    SearchNotes,
    SearchContent,
}

/// 加密事件 —— 数据加密解密操作
/// EncryptData: 使用 XChaCha20-Poly1305 加密数据
/// DecryptData: 解密已加密的数据
/// GenerateKey: 生成新的 Argon2id 派生密钥
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum CryptoEvent {
    EncryptData,
    DecryptData,
    GenerateKey,
}

/// 同步事件 —— 多设备数据同步操作
/// StartSync: 启动全量或增量同步
/// GetSyncStatus: 查询当前同步状态
/// ResolveConflict: 手动解决同步冲突
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum SyncEvent {
    StartSync,
    GetSyncStatus,
    ResolveConflict,
}

/// 格式转换事件 —— 笔记导入导出操作
/// ExportMarkdown: 导出为 Markdown 文件
/// ExportHtml: 导出为 HTML 文件
/// ImportMarkdown: 从 Markdown 文件导入
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum FormatEvent {
    ExportMarkdown,
    ExportHtml,
    ImportMarkdown,
}

/// 画布事件 —— 白板/画布节点的 CRUD 操作
/// CreateNode: 创建画布节点（文本/形状/图片等）
/// UpdateNode: 更新画布节点属性
/// DeleteNode: 删除画布节点
/// CreateEdge: 创建节点之间的连线
/// DeleteEdge: 删除节点连线
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum CanvasEvent {
    CreateNode,
    UpdateNode,
    DeleteNode,
    CreateEdge,
    DeleteEdge,
}

/// 数据库事件 —— 类 Airtable 表格数据库操作
/// CreateTable: 创建数据表
/// InsertRow: 插入一行数据
/// UpdateRow: 更新一行数据
/// DeleteRow: 删除一行数据
/// QueryTable: 查询数据表（支持过滤和排序）
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum DatabaseEvent {
    CreateTable,
    InsertRow,
    UpdateRow,
    DeleteRow,
    QueryTable,
}

/// 对象事件 —— 对象化数据模型的 CRUD 操作（借鉴 Anytype）
/// CreateObject: 创建自定义对象
/// ReadObject: 读取对象详情
/// UpdateObject: 更新对象属性
/// DeleteObject: 删除对象
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ObjectEvent {
    CreateObject,
    ReadObject,
    UpdateObject,
    DeleteObject,
}

/// 知识图谱事件 —— 图谱节点的查询和管理
/// CreateNode: 创建图谱节点
/// UpdateNode: 更新图谱节点
/// DeleteNode: 删除图谱节点
/// QueryPath: 查询两点之间的最短路径
/// GetNeighbors: 获取节点的邻接节点
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum GraphEvent {
    CreateNode,
    UpdateNode,
    DeleteNode,
    QueryPath,
    GetNeighbors,
}

/// 闪卡事件 —— 间隔重复学习操作
/// CreateDeck: 创建闪卡牌组
/// AddCard: 添加闪卡
/// ReviewCard: 复习一张闪卡
/// GetDueCards: 获取待复习的闪卡列表
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum FlashcardEvent {
    CreateDeck,
    AddCard,
    ReviewCard,
    GetDueCards,
}

/// 插件事件 —— 插件生命周期管理
/// LoadPlugin: 加载 WASM 插件
/// UnloadPlugin: 卸载插件
/// ExecuteCommand: 执行插件命令
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PluginEvent {
    LoadPlugin,
    UnloadPlugin,
    ExecuteCommand,
}

/// P2P 事件 —— 点对点通信操作
/// ConnectPeer: 连接到对等节点
/// DisconnectPeer: 断开对等节点连接
/// SendMessage: 发送点对点消息
/// BroadcastMessage: 向所有已连接节点广播消息
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
