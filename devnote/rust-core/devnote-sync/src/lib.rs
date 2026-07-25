//! 同步引擎 —— 实现增量同步和断点续传
//! 借鉴 Joplin 的同步协议设计：delta sync + 事务回滚
//!
//! 借鉴 Joplin 的同步协议设计
//! 来源: https://github.com/laurent22/joplin
//! 借鉴内容: 增量同步(delta sync)机制、事务回滚保护、冲突检测与手动解决流程

use serde::{Deserialize, Serialize};
use devnote_observe::{info, instrument, warn};
use chrono::{DateTime, Utc};
use thiserror::Error;
use devnote_crdt::{
    CRDTDocument, Operation, ConflictInfo,
    detect_conflicts, merge_documents,
};
use rusqlite::Connection;
use std::sync::Mutex;
use std::collections::{HashSet, VecDeque};
use sha2::{Sha256, Digest};
use subtle::ConstantTimeEq;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum SyncStatus {
    Idle,
    Syncing,
    Synced,
    Conflict,
    Error(String),
    Offline,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncInfo {
    pub status: SyncStatus,
    pub last_synced_at: Option<DateTime<Utc>>,
    pub pending_changes: u64,
    pub server_version: Option<u64>,
    pub local_version: u64,
    // 借鉴 Anytype 内容寻址方案：每个同步数据包附加 SHA-256 哈希进行完整性校验
    pub content_hash: Option<String>,
}

#[derive(Debug, Error)]
pub enum SyncError {
    #[error("network error: {0}")]
    NetworkError(String),
    #[error("conflict detected")]
    Conflict,
    #[error("authentication failed")]
    AuthFailed,
    #[error("server error: {0}")]
    ServerError(String),
    #[error("local error: {0}")]
    LocalError(String),
    #[error("crdt error: {0}")]
    CRDTError(String),
    #[error("database error: {0}")]
    DatabaseError(String),
    /// 修复(P1): 新增 NotImplemented 变体，用于标记尚未接入真实传输层的 stub 方法。
    /// 原实现中 sync_inner/push_changes_inner/pull_changes_inner 返回 Ok(SyncInfo)
    /// 但实际无任何网络调用，导致上层误认为同步成功。
    #[error("not implemented: {0}")]
    NotImplemented(String),
}

impl From<devnote_crdt::CRDTError> for SyncError {
    fn from(err: devnote_crdt::CRDTError) -> Self {
        SyncError::CRDTError(err.to_string())
    }
}

impl From<rusqlite::Error> for SyncError {
    fn from(err: rusqlite::Error) -> Self {
        SyncError::DatabaseError(err.to_string())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalState {
    pub document: CRDTDocument,
    pub last_synced_at: Option<DateTime<Utc>>,
    pub pending_operations: Vec<Operation>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteChanges {
    pub operations: Vec<Operation>,
    pub server_version: u64,
    // 借鉴 Anytype 内容寻址方案：每个同步数据包附加 SHA-256 哈希进行完整性校验
    pub content_hash: Option<String>,
}

/// 同步操作幂等键 —— 防止同一操作因网络重试被多次提交
/// 借鉴 Stripe API 的 Idempotency-Key 设计模式
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncOperation {
    pub idempotency_key: String,  // UUID v4，唯一标识每次同步操作
    pub operation: Operation,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MergeResult {
    pub applied_operations: Vec<Operation>,
    pub conflicts: Vec<ConflictInfo>,
    pub has_conflicts: bool,
}

/// 内容寻址：计算 SHA-256 哈希
pub fn compute_content_hash(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    format!("{:x}", hasher.finalize())
}

/// 内容寻址：验证哈希
/// P1 修复: 改用常量时间比较，避免通过响应时间推断哈希前缀的时序侧信道。
/// 与 devnote-crypto 中的密码/哈希验证保持一致（使用 subtle::ConstantTimeEq）。
pub fn verify_content_hash(data: &[u8], expected_hash: &str) -> bool {
    let computed = compute_content_hash(data);
    // 长度不同时仍走常量时间路径：先比较长度，再对公共前缀做常量时间比较
    if computed.len() != expected_hash.len() {
        return false;
    }
    bool::from(computed.as_bytes().ct_eq(expected_hash.as_bytes()))
}

lazy_static::lazy_static! {
    // P1 修复 (R2): 原实现满 10000 时 keys.clear() 全量清空，导致所有已处理键重新可处理，
    // 幂等性失效。改为 FIFO 有界淘汰：超过容量时按插入顺序淘汰最旧的 20%，而非清空全部。
    // 注：进程重启仍会丢失（in-memory），但同步引擎本身使用 open_in_memory 数据库，
    // 重启后状态本就重置，此处保证运行期内幂等性即可。
    static ref PROCESSED_KEYS: Mutex<IdempotencyCache> = Mutex::new(IdempotencyCache::new(10000));
}

/// 有界 FIFO 幂等缓存，淘汰最旧条目而非全量清空
struct IdempotencyCache {
    keys: HashSet<String>,
    order: VecDeque<String>,
    capacity: usize,
}

impl IdempotencyCache {
    fn new(capacity: usize) -> Self {
        Self {
            keys: HashSet::with_capacity(capacity),
            order: VecDeque::with_capacity(capacity),
            capacity,
        }
    }

    /// 若 key 已存在返回 false；否则插入，并在超容量时 FIFO 淘汰最旧的 20%。
    fn insert(&mut self, key: String) -> bool {
        if !self.keys.insert(key.clone()) {
            return false;
        }
        self.order.push_back(key);
        if self.keys.len() > self.capacity {
            let evict = self.capacity / 5; // 淘汰 20%
            for _ in 0..evict.max(1) {
                if let Some(old) = self.order.pop_front() {
                    self.keys.remove(&old);
                }
            }
        }
        true
    }

    fn contains(&self, key: &str) -> bool {
        self.keys.contains(key)
    }
}

/// 检查幂等键是否已处理，防止重复提交
pub fn check_idempotency(key: &str) -> bool {
    let mut cache = PROCESSED_KEYS
        .lock()
        .expect("PROCESSED_KEYS mutex poisoned");
    if cache.contains(key) {
        return false; // Already processed
    }
    cache.insert(key.to_string());
    true
}

pub trait SyncEngine: Send + Sync {
    fn sync(&mut self) -> Result<SyncInfo, SyncError>;
    fn get_status(&self) -> SyncStatus;
    fn resolve_conflict(&mut self, use_remote: bool) -> Result<(), SyncError>;
    fn push_changes(&mut self) -> Result<SyncInfo, SyncError>;
    fn pull_changes(&mut self) -> Result<SyncInfo, SyncError>;
}

#[derive(Debug)]
pub struct ClientSyncEngine {
    pub device_id: String,
    pub local_state: LocalState,
    pub status: SyncStatus,
    pub conflicts: Vec<ConflictInfo>,
    db: Mutex<Connection>,
}

impl ClientSyncEngine {
    pub fn new(document_id: String, device_id: String) -> Self {
        let db = Connection::open_in_memory()
            .expect("Failed to open in-memory database");

        db.execute(
            "CREATE TABLE IF NOT EXISTS sync_state (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )",
            [],
        ).expect("Failed to create sync_state table");

        db.execute(
            "CREATE TABLE IF NOT EXISTS operations (
                id TEXT PRIMARY KEY,
                data TEXT NOT NULL
            )",
            [],
        ).expect("Failed to create operations table");

        Self {
            device_id: device_id.clone(),
            local_state: LocalState {
                document: CRDTDocument::new(document_id, device_id),
                last_synced_at: None,
                pending_operations: Vec::new(),
            },
            status: SyncStatus::Idle,
            conflicts: Vec::new(),
            db: Mutex::new(db),
        }
    }

    #[instrument(skip(self, remote_changes))]
    pub fn merge_with_crdt(
        &mut self,
        remote_changes: RemoteChanges,
    ) -> Result<MergeResult, SyncError> {
        let conflicts = detect_conflicts(&self.local_state.document, &remote_changes.operations);

        let applied = merge_documents(
            &mut self.local_state.document,
            remote_changes.operations.clone(),
        )?;

        self.local_state.pending_operations.retain(|local_op| {
            !remote_changes.operations.iter().any(|remote_op| {
                remote_op.id() == local_op.id()
            })
        });

        let has_conflicts = !conflicts.is_empty();
        if has_conflicts {
            self.status = SyncStatus::Conflict;
            self.conflicts = conflicts.clone();
        } else {
            self.status = SyncStatus::Synced;
            self.conflicts.clear();
        }

        self.local_state.last_synced_at = Some(Utc::now());

        Ok(MergeResult {
            applied_operations: applied,
            conflicts,
            has_conflicts,
        })
    }

    pub fn get_pending_operations(&self) -> &[Operation] {
        &self.local_state.pending_operations
    }

    pub fn record_operation(&mut self, op: Operation) {
        self.local_state.pending_operations.push(op);
        if self.status == SyncStatus::Synced || self.status == SyncStatus::Idle {
            self.status = SyncStatus::Idle;
        }
    }

    pub fn resolve_conflict_manual(
        &mut self,
        block_id: &str,
        use_remote: bool,
    ) -> Result<(), SyncError> {
        let conflict = self.conflicts.iter().find(|c| c.block_id == block_id)
            .ok_or_else(|| SyncError::LocalError(format!("no conflict for block {}", block_id)))?;

        let content = if use_remote {
            conflict.remote_content.clone()
        } else {
            conflict.local_content.clone()
        };

        self.local_state.document.replace_block(
            block_id.to_string(),
            conflict.local_content.clone(),
            content,
        ).map_err(|e| SyncError::LocalError(format!("failed to apply conflict resolution: {}", e)))?;

        self.conflicts.retain(|c| c.block_id != block_id);
        if self.conflicts.is_empty() {
            self.status = SyncStatus::Synced;
        }

        Ok(())
    }

    /// 修复(P1): 原实现返回 Ok(SyncInfo) 但无任何网络调用，导致上层误认为同步成功。
    /// 改为返回 Err(NotImplemented)，调用方可明确区分"同步成功"与"功能未接入"。
    /// TODO: 接入 devnote-grpc / devnote-websocket 实现真实同步逻辑后移除此 stub。
    // P1 修复 (R3): 改为 &self 以便调用方持锁期间可调用，避免事务跨两次锁获取。
    fn sync_inner(&self) -> Result<SyncInfo, SyncError> {
        info!("sync: stub called with {} pending changes (not implemented)", self.local_state.pending_operations.len());
        Err(SyncError::NotImplemented(
            "sync_inner: network transport not yet integrated".to_string(),
        ))
    }

    /// 修复(P1): 同上，原 stub 返回 Ok 假成功，改为显式 NotImplemented。
    fn push_changes_inner(&self) -> Result<SyncInfo, SyncError> {
        info!("push_changes: stub called with {} pending operations (not implemented)", self.local_state.pending_operations.len());
        Err(SyncError::NotImplemented(
            "push_changes_inner: network transport not yet integrated".to_string(),
        ))
    }

    /// 修复(P1): 同上，原 stub 返回 Ok 假成功，改为显式 NotImplemented。
    fn pull_changes_inner(&self) -> Result<SyncInfo, SyncError> {
        info!("pull_changes: stub called, local_version={} (not implemented)", self.local_state.document.hlc.logical);
        Err(SyncError::NotImplemented(
            "pull_changes_inner: network transport not yet integrated".to_string(),
        ))
    }
}

impl SyncEngine for ClientSyncEngine {
    #[instrument]
    fn sync(&mut self) -> Result<SyncInfo, SyncError> {
        // P1 修复 (R3): 原 BEGIN/COMMIT 跨两次 lock()，drop(db) 与重新 lock 之间其他线程
        // 可能交错操作同一连接，破坏事务隔离。改为单次持锁贯穿整个事务。
        let db = self.db.lock().map_err(|e| SyncError::DatabaseError(e.to_string()))?;
        db.execute("BEGIN TRANSACTION", [])?;
        let result = self.sync_inner();
        match result {
            Ok(info) => {
                db.execute("COMMIT", [])?;
                Ok(info)
            }
            Err(e) => {
                db.execute("ROLLBACK", [])?;
                Err(e)
            }
        }
    }

    fn get_status(&self) -> SyncStatus {
        self.status.clone()
    }

    fn resolve_conflict(&mut self, use_remote: bool) -> Result<(), SyncError> {
        if self.conflicts.is_empty() {
            return Err(SyncError::LocalError("no conflicts to resolve".to_string()));
        }

        let block_ids: Vec<String> = self.conflicts.iter().map(|c| c.block_id.clone()).collect();
        for block_id in block_ids {
            self.resolve_conflict_manual(&block_id, use_remote)?;
        }

        Ok(())
    }

    #[instrument]
    fn push_changes(&mut self) -> Result<SyncInfo, SyncError> {
        // P1 修复 (R3): 单次持锁贯穿事务，避免交错。
        let db = self.db.lock().map_err(|e| SyncError::DatabaseError(e.to_string()))?;
        db.execute("BEGIN TRANSACTION", [])?;
        let result = self.push_changes_inner();
        match result {
            Ok(info) => {
                db.execute("COMMIT", [])?;
                Ok(info)
            }
            Err(e) => {
                db.execute("ROLLBACK", [])?;
                Err(e)
            }
        }
    }

    #[instrument]
    fn pull_changes(&mut self) -> Result<SyncInfo, SyncError> {
        // P1 修复 (R3): 单次持锁贯穿事务，避免交错。
        let db = self.db.lock().map_err(|e| SyncError::DatabaseError(e.to_string()))?;
        db.execute("BEGIN TRANSACTION", [])?;
        let result = self.pull_changes_inner();
        match result {
            Ok(info) => {
                db.execute("COMMIT", [])?;
                Ok(info)
            }
            Err(e) => {
                db.execute("ROLLBACK", [])?;
                Err(e)
            }
        }
    }
}
