use devnote_observe::{instrument, warn};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::Command;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum WorkflowError {
    #[error("git error: {0}")]
    GitError(String),
    #[error("io error: {0}")]
    IoError(#[from] std::io::Error),
    #[error("serialization error: {0}")]
    SerializationError(#[from] serde_json::Error),
    #[error("watch error: {0}")]
    WatchError(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitStatus {
    pub modified: Vec<String>,
    pub added: Vec<String>,
    pub deleted: Vec<String>,
    pub untracked: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitCommitInfo {
    pub hash: String,
    pub author: String,
    pub date: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitDiffEntry {
    pub file: String,
    pub status: String,
    pub additions: i64,
    pub deletions: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitBranchInfo {
    pub name: String,
    pub is_current: bool,
}

#[derive(Debug)]
pub struct GitManager {
    repo_path: PathBuf,
}

impl GitManager {
    pub fn new(repo_path: PathBuf) -> Self {
        Self { repo_path }
    }

    #[instrument]
    pub fn init_repo(&self) -> Result<(), WorkflowError> {
        let output = Command::new("git")
            .arg("init")
            .current_dir(&self.repo_path)
            .output()
            .map_err(|e| WorkflowError::GitError(e.to_string()))?;

        if !output.status.success() {
            return Err(WorkflowError::GitError(
                String::from_utf8_lossy(&output.stderr).to_string(),
            ));
        }
        Ok(())
    }

    #[instrument]
    pub fn commit(&self, message: &str) -> Result<(), WorkflowError> {
        let add_output = Command::new("git")
            .args(["add", "-A"])
            .current_dir(&self.repo_path)
            .output()
            .map_err(|e| WorkflowError::GitError(e.to_string()))?;

        if !add_output.status.success() {
            return Err(WorkflowError::GitError(
                String::from_utf8_lossy(&add_output.stderr).to_string(),
            ));
        }

        let commit_output = Command::new("git")
            .args(["commit", "-m", message])
            .current_dir(&self.repo_path)
            .output()
            .map_err(|e| WorkflowError::GitError(e.to_string()))?;

        if !commit_output.status.success() {
            let stderr = String::from_utf8_lossy(&commit_output.stderr).to_string();
            if stderr.contains("nothing to commit") {
                return Ok(());
            }
            return Err(WorkflowError::GitError(stderr));
        }
        Ok(())
    }

    pub fn log(&self, max_count: Option<usize>) -> Result<Vec<GitCommitInfo>, WorkflowError> {
        let mut args = vec!["log", "--pretty=format:%H|%an|%ai|%s"];
        if let Some(count) = max_count {
            args.push(format!("-{}", count).leak());
        }

        let output = Command::new("git")
            .args(&args)
            .current_dir(&self.repo_path)
            .output()
            .map_err(|e| WorkflowError::GitError(e.to_string()))?;

        if !output.status.success() {
            return Err(WorkflowError::GitError(
                String::from_utf8_lossy(&output.stderr).to_string(),
            ));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let commits = stdout
            .lines()
            .filter_map(|line| {
                let parts: Vec<&str> = line.splitn(4, '|').collect();
                if parts.len() == 4 {
                    Some(GitCommitInfo {
                        hash: parts[0].to_string(),
                        author: parts[1].to_string(),
                        date: parts[2].to_string(),
                        message: parts[3].to_string(),
                    })
                } else {
                    None
                }
            })
            .collect();
        Ok(commits)
    }

    pub fn diff(&self, commit_hash: Option<&str>) -> Result<Vec<GitDiffEntry>, WorkflowError> {
        let mut args = vec!["diff", "--stat"];
        if let Some(hash) = commit_hash {
            args.push(hash);
        }

        let output = Command::new("git")
            .args(&args)
            .current_dir(&self.repo_path)
            .output()
            .map_err(|e| WorkflowError::GitError(e.to_string()))?;

        if !output.status.success() {
            return Err(WorkflowError::GitError(
                String::from_utf8_lossy(&output.stderr).to_string(),
            ));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let entries = stdout
            .lines()
            .filter_map(|line| {
                let trimmed = line.trim();
                if trimmed.is_empty() || trimmed.starts_with('|') {
                    return None;
                }
                let parts: Vec<&str> = trimmed.split('|').collect();
                if parts.len() >= 2 {
                    let file = parts[0].trim().to_string();
                    let stats = parts[1].trim();
                    let mut additions = 0i64;
                    let mut deletions = 0i64;
                    for stat_part in stats.split(',') {
                        let s = stat_part.trim();
                        if s.ends_with('+') {
                            additions = s.trim_end_matches('+').trim().parse().unwrap_or(0);
                        } else if s.ends_with('-') {
                            deletions = s.trim_end_matches('-').trim().parse().unwrap_or(0);
                        }
                    }
                    Some(GitDiffEntry {
                        file,
                        status: "modified".to_string(),
                        additions,
                        deletions,
                    })
                } else {
                    None
                }
            })
            .collect();
        Ok(entries)
    }

    pub fn checkout(&self, reference: &str) -> Result<(), WorkflowError> {
        let output = Command::new("git")
            .args(["checkout", reference])
            .current_dir(&self.repo_path)
            .output()
            .map_err(|e| WorkflowError::GitError(e.to_string()))?;

        if !output.status.success() {
            return Err(WorkflowError::GitError(
                String::from_utf8_lossy(&output.stderr).to_string(),
            ));
        }
        Ok(())
    }

    pub fn branch(&self, name: Option<&str>) -> Result<Vec<GitBranchInfo>, WorkflowError> {
        if let Some(branch_name) = name {
            let output = Command::new("git")
                .args(["checkout", "-b", branch_name])
                .current_dir(&self.repo_path)
                .output()
                .map_err(|e| WorkflowError::GitError(e.to_string()))?;

            if !output.status.success() {
                return Err(WorkflowError::GitError(
                    String::from_utf8_lossy(&output.stderr).to_string(),
                ));
            }
        }

        let output = Command::new("git")
            .args(["branch"])
            .current_dir(&self.repo_path)
            .output()
            .map_err(|e| WorkflowError::GitError(e.to_string()))?;

        if !output.status.success() {
            return Err(WorkflowError::GitError(
                String::from_utf8_lossy(&output.stderr).to_string(),
            ));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let branches = stdout
            .lines()
            .map(|line| {
                let is_current = line.starts_with('*');
                let name = line.trim_start_matches('*').trim().to_string();
                GitBranchInfo {
                    name,
                    is_current,
                }
            })
            .collect();
        Ok(branches)
    }

    pub fn status(&self) -> Result<GitStatus, WorkflowError> {
        let output = Command::new("git")
            .args(["status", "--porcelain"])
            .current_dir(&self.repo_path)
            .output()
            .map_err(|e| WorkflowError::GitError(e.to_string()))?;

        if !output.status.success() {
            return Err(WorkflowError::GitError(
                String::from_utf8_lossy(&output.stderr).to_string(),
            ));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let mut git_status = GitStatus {
            modified: Vec::new(),
            added: Vec::new(),
            deleted: Vec::new(),
            untracked: Vec::new(),
        };

        for line in stdout.lines() {
            if line.len() < 4 {
                continue;
            }
            let status_code = &line[..2];
            let file_path = line[3..].to_string();

            match status_code.trim() {
                "M" | "MM" | "AM" => git_status.modified.push(file_path),
                "A" => git_status.added.push(file_path),
                "D" | "AD" => git_status.deleted.push(file_path),
                "??" => git_status.untracked.push(file_path),
                _ => {
                    if status_code.starts_with('M') {
                        git_status.modified.push(file_path);
                    } else if status_code.starts_with('A') {
                        git_status.added.push(file_path);
                    } else if status_code.starts_with('D') {
                        git_status.deleted.push(file_path);
                    }
                }
            }
        }

        Ok(git_status)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FileChangeKind {
    Create,
    Modify,
    Delete,
    Rename,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileChangeEvent {
    pub path: String,
    pub kind: FileChangeKind,
}

pub struct FileWatcher {
    watch_path: PathBuf,
}

impl FileWatcher {
    pub fn new(watch_path: PathBuf) -> Self {
        Self { watch_path }
    }

    pub async fn watch_directory<F>(&self, mut on_change: F) -> Result<(), WorkflowError>
    where
        F: FnMut(FileChangeEvent) + Send + 'static,
    {
        use notify::{Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};

        let path = self.watch_path.clone();
        let (tx, mut rx) = tokio::sync::mpsc::channel::<FileChangeEvent>(100);

        let watcher_path = path.clone();
        let mut watcher = RecommendedWatcher::new(
            move |res: Result<Event, notify::Error>| {
                if let Ok(event) = res {
                    let kind = match event.kind {
                        EventKind::Create(_) => FileChangeKind::Create,
                        EventKind::Modify(notify::event::ModifyKind::Name(_)) => {
                            FileChangeKind::Rename
                        }
                        EventKind::Modify(_) => FileChangeKind::Modify,
                        EventKind::Remove(_) => FileChangeKind::Delete,
                        _ => return,
                    };
                    for path in event.paths {
                        let file_event = FileChangeEvent {
                            path: path.to_string_lossy().to_string(),
                            kind,
                        };
                        let _ = tx.blocking_send(file_event);
                    }
                }
            },
            Config::default(),
        )
        .map_err(|e| WorkflowError::WatchError(e.to_string()))?;

        watcher
            .watch(&watcher_path, RecursiveMode::Recursive)
            .map_err(|e| WorkflowError::WatchError(e.to_string()))?;

        tokio::spawn(async move {
            while let Some(event) = rx.recv().await {
                on_change(event);
            }
            let _ = watcher;
        });

        Ok(())
    }
}

pub struct EditorSync {
    watch_path: PathBuf,
}

impl EditorSync {
    pub fn new(watch_path: PathBuf) -> Self {
        Self { watch_path }
    }

    pub async fn watch_external_edits<F>(&self, on_change: F) -> Result<(), WorkflowError>
    where
        F: FnMut(FileChangeEvent) + Send + 'static,
    {
        let watcher = FileWatcher::new(self.watch_path.clone());
        watcher.watch_directory(on_change).await
    }

    pub fn apply_changes(&self, changes: &[FileChangeEvent]) -> Result<(), WorkflowError> {
        for change in changes {
            match change.kind {
                FileChangeKind::Create | FileChangeKind::Modify => {}
                FileChangeKind::Delete => {}
                FileChangeKind::Rename => {}
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitHubConfig {
    pub token: String,
    pub repo: String,
    pub owner: String,
}

pub struct GitHubClient {
    #[allow(dead_code)]
    config: GitHubConfig,
}

impl GitHubClient {
    pub fn new(config: GitHubConfig) -> Self {
        Self { config }
    }

    pub fn push_notes(&self) -> Result<(), WorkflowError> {
        Err(WorkflowError::GitError("GitHub push not implemented yet".to_string()))
    }

    pub fn pull_notes(&self) -> Result<(), WorkflowError> {
        Err(WorkflowError::GitError("GitHub pull not implemented yet".to_string()))
    }

    pub fn create_issue_link(&self, _note_id: &str, _issue_url: &str) -> Result<String, WorkflowError> {
        Err(WorkflowError::GitError("GitHub issue link not implemented yet".to_string()))
    }
}
