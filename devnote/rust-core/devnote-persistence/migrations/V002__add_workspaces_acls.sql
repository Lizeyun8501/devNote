-- V002: 工作区与资源 ACL 表结构
-- 提取自 devnote-persistence/src/lib.rs 中的 SCHEMA_V2 常量
-- 所有语句均使用 IF NOT EXISTS，确保幂等可重复执行

CREATE TABLE IF NOT EXISTS resource_acls (
    id TEXT PRIMARY KEY,
    resource_id TEXT NOT NULL,
    resource_type TEXT NOT NULL,
    user_id TEXT NOT NULL,
    permission TEXT NOT NULL,
    granted_by TEXT NOT NULL,
    granted_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_resource_acls_resource ON resource_acls(resource_id, resource_type);
CREATE INDEX IF NOT EXISTS idx_resource_acls_user ON resource_acls(user_id);

CREATE TABLE IF NOT EXISTS workspaces (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    owner_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_workspaces_owner ON workspaces(owner_id);

CREATE TABLE IF NOT EXISTS workspace_members (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    role TEXT NOT NULL,
    joined_at TEXT NOT NULL,
    FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_workspace_members_workspace ON workspace_members(workspace_id);
CREATE INDEX IF NOT EXISTS idx_workspace_members_user ON workspace_members(user_id);
