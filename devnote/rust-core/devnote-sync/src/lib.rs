use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use thiserror::Error;

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
}

pub trait SyncEngine: Send + Sync {
    fn sync(&mut self) -> Result<SyncInfo, SyncError>;
    fn get_status(&self) -> SyncStatus;
    fn resolve_conflict(&mut self, use_remote: bool) -> Result<(), SyncError>;
    fn push_changes(&mut self) -> Result<SyncInfo, SyncError>;
    fn pull_changes(&mut self) -> Result<SyncInfo, SyncError>;
}
