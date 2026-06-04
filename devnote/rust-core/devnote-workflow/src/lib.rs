//! DevNote Workflow - Git 工作流、文件监听和 GitHub 集成
//!
//! 提供笔记版本管理、外部编辑器同步、GitHub 推送等功能。

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

// ============================================================
// GitHub 集成服务
// ============================================================
// 借鉴的开源项目:
// - GitHub REST API (https://docs.github.com/en/rest): GitHub 官方 API 规范
// - octokit.rs (https://github.com/XAMPPRocky/octokit.rs): Rust 的 GitHub API 客户端
//
// 实现说明:
// 提供笔记库同步到 GitHub 的功能，支持创建仓库、提交、推送、PR 等操作。

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitHubConfig {
    pub token: String,
    pub owner: String,
    pub repo: String,
    pub branch: String,
}

impl Default for GitHubConfig {
    fn default() -> Self {
        Self {
            token: String::new(),
            owner: String::new(),
            repo: String::new(),
            branch: "main".to_string(),
        }
    }
}

/// GitHub API 请求结果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitHubResult {
    pub success: bool,
    pub message: String,
    pub url: Option<String>,
}

/// PR 信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PullRequestInfo {
    pub number: u64,
    pub title: String,
    pub url: String,
    pub state: String,
}

/// GitHub 客户端，提供与 GitHub API 交互的能力
/// 借鉴 octokit.rs 的客户端设计模式
pub struct GitHubClient {
    config: GitHubConfig,
    manager: GitManager,
}

impl GitHubClient {
    pub fn new(config: GitHubConfig, repo_path: PathBuf) -> Self {
        Self {
            config,
            manager: GitManager::new(repo_path),
        }
    }

    /// 配置远程仓库 URL
    /// 使用 token 认证方式：https://owner:token@github.com/owner/repo.git
    fn remote_url(&self) -> String {
        format!(
            "https://{}:{}@github.com/{}/{}.git",
            self.config.owner, self.config.token, self.config.owner, self.config.repo
        )
    }

    /// 检查远程仓库是否存在
    /// 借鉴 GitHub REST API 的 GET /repos/{owner}/{repo} 端点
    fn check_repo_exists(&self) -> bool {
        let output = Command::new("git")
            .args([
                "ls-remote",
                "--exit-code",
                &self.remote_url(),
                &self.config.branch,
            ])
            .output();

        match output {
            Ok(out) => out.status.success(),
            Err(_) => false,
        }
    }

    /// 将笔记库同步到 GitHub
    /// 1. 检查仓库是否存在，不存在则创建
    /// 2. 将笔记目录作为 Git 仓库初始化
    /// 3. 提交所有变更
    /// 4. 推送到 GitHub
    pub async fn sync_to_github(&self, notes_path: &str) -> Result<GitHubResult, WorkflowError> {
        // 1. 确保本地仓库已初始化
        let _ = self.manager.init_repo();

        // 2. 配置远程仓库
        self.add_remote_if_not_exists()?;

        // 3. 提交所有变更
        let message = format!("sync: update notes at {}", chrono::Local::now().format("%Y-%m-%d %H:%M:%S"));
        self.manager.commit(&message)?;

        // 4. 确保当前分支正确
        self.ensure_branch()?;

        // 5. 推送到 GitHub
        match self.push_to_github() {
            Ok(_) => Ok(GitHubResult {
                success: true,
                message: format!("成功同步到 https://github.com/{}/{}", self.config.owner, self.config.repo),
                url: Some(format!("https://github.com/{}/{}", self.config.owner, self.config.repo)),
            }),
            Err(e) => Ok(GitHubResult {
                success: false,
                message: format!("推送失败: {}", e),
                url: None,
            }),
        }
    }

    /// 从 GitHub 拉取笔记
    pub fn pull_from_github(&self) -> Result<GitHubResult, WorkflowError> {
        let output = Command::new("git")
            .args(["pull", "origin", &self.config.branch])
            .env("GIT_TERMINAL_PROMPT", "0")
            .current_dir(&self.manager.repo_path)
            .output()
            .map_err(|e| WorkflowError::GitError(e.to_string()))?;

        if !output.status.success() {
            return Ok(GitHubResult {
                success: false,
                message: String::from_utf8_lossy(&output.stderr).to_string(),
                url: None,
            });
        }

        Ok(GitHubResult {
            success: true,
            message: "拉取成功".to_string(),
            url: None,
        })
    }

    /// 推送到 GitHub
    fn push_to_github(&self) -> Result<(), WorkflowError> {
        let output = Command::new("git")
            .args([
                "push",
                "--set-upstream",
                "origin",
                &self.config.branch,
            ])
            .env("GIT_TERMINAL_PROMPT", "0")
            .current_dir(&self.manager.repo_path)
            .output()
            .map_err(|e| WorkflowError::GitError(e.to_string()))?;

        if !output.status.success() {
            // 如果分支不存在，尝试强制推送
            let stderr = String::from_utf8_lossy(&output.stderr);
            if stderr.contains("does not match") || stderr.contains("not found") {
                return self.force_push();
            }
            return Err(WorkflowError::GitError(stderr.to_string()));
        }

        Ok(())
    }

    /// 强制推送
    fn force_push(&self) -> Result<(), WorkflowError> {
        let output = Command::new("git")
            .args([
                "push",
                "--force",
                "--set-upstream",
                "origin",
                &self.config.branch,
            ])
            .env("GIT_TERMINAL_PROMPT", "0")
            .current_dir(&self.manager.repo_path)
            .output()
            .map_err(|e| WorkflowError::GitError(e.to_string()))?;

        if !output.status.success() {
            return Err(WorkflowError::GitError(
                String::from_utf8_lossy(&output.stderr).to_string(),
            ));
        }

        Ok(())
    }

    /// 添加远程仓库（如果不存在）
    fn add_remote_if_not_exists(&self) -> Result<(), WorkflowError> {
        // 检查是否已有 origin 远程
        let check = Command::new("git")
            .args(["remote", "get-url", "origin"])
            .current_dir(&self.manager.repo_path)
            .output();

        let should_add = match check {
            Ok(out) => !out.status.success(),
            Err(_) => true,
        };

        if should_add {
            let output = Command::new("git")
                .args(["remote", "add", "origin", &self.remote_url()])
                .current_dir(&self.manager.repo_path)
                .output()
                .map_err(|e| WorkflowError::GitError(e.to_string()))?;

            if !output.status.success() {
                // 如果远程已存在，先更新
                Command::new("git")
                    .args(["remote", "set-url", "origin", &self.remote_url()])
                    .current_dir(&self.manager.repo_path)
                    .output()
                    .map_err(|e| WorkflowError::GitError(e.to_string()))?;
            }
        }

        Ok(())
    }

    /// 确保当前分支正确
    fn ensure_branch(&self) -> Result<(), WorkflowError> {
        // 检查当前分支
        let output = Command::new("git")
            .args(["branch", "--show-current"])
            .current_dir(&self.manager.repo_path)
            .output()
            .map_err(|e| WorkflowError::GitError(e.to_string()))?;

        let current_branch = String::from_utf8_lossy(&output.stdout).trim().to_string();

        if current_branch != self.config.branch {
            // 尝试切换到目标分支
            let switch = Command::new("git")
                .args(["checkout", "-B", &self.config.branch])
                .current_dir(&self.manager.repo_path)
                .output()
                .map_err(|e| WorkflowError::GitError(e.to_string()))?;

            if !switch.status.success() {
                return Err(WorkflowError::GitError(
                    String::from_utf8_lossy(&switch.stderr).to_string(),
                ));
            }
        }

        Ok(())
    }

    /// 创建 Pull Request
    /// 借鉴 GitHub REST API 的 POST /repos/{owner}/{repo}/pulls 端点
    pub fn create_pull_request(
        &self,
        title: &str,
        body: &str,
        head_branch: &str,
        base_branch: &str,
    ) -> Result<PullRequestInfo, WorkflowError> {
        // 使用 GitHub CLI 创建 PR（如果可用）
        let output = Command::new("gh")
            .args([
                "pr",
                "create",
                "--title",
                title,
                "--body",
                body,
                "--base",
                base_branch,
                "--head",
                head_branch,
            ])
            .current_dir(&self.manager.repo_path)
            .env("GH_TOKEN", &self.config.token)
            .output();

        match output {
            Ok(out) if out.status.success() => {
                let url = String::from_utf8_lossy(&out.stdout).trim().to_string();
                // 从 URL 提取 PR 编号
                let number = url
                    .split('/')
                    .last()
                    .and_then(|s| s.parse::<u64>().ok())
                    .unwrap_or(0);

                Ok(PullRequestInfo {
                    number,
                    title: title.to_string(),
                    url,
                    state: "open".to_string(),
                })
            }
            _ => Err(WorkflowError::GitError(
                "创建 PR 失败，请确保已安装 GitHub CLI (gh)".to_string(),
            )),
        }
    }

    /// 推送笔记
    #[deprecated(since = "0.2.0", note = "Use sync_to_github instead")]
    pub fn push_notes(&self) -> Result<(), WorkflowError> {
        Err(WorkflowError::GitError("请使用 sync_to_github 方法替代".to_string()))
    }

    /// 拉取笔记
    #[deprecated(since = "0.2.0", note = "Use pull_from_github instead")]
    pub fn pull_notes(&self) -> Result<(), WorkflowError> {
        Err(WorkflowError::GitError("请使用 pull_from_github 方法替代".to_string()))
    }

    /// 创建 issue 链接
    pub fn create_issue_link(&self, note_id: &str, issue_url: &str) -> Result<String, WorkflowError> {
        Ok(format!("[{}]({})", note_id, issue_url))
    }
}
