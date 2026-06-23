-- DevNote sync-server 初始 schema
-- 统一采用 sqlx + golang-migrate 管理迁移版本

CREATE TABLE IF NOT EXISTS users (
    id            TEXT PRIMARY KEY,
    username      TEXT NOT NULL UNIQUE,
    password      TEXT NOT NULL DEFAULT '',
    srp_salt      BLOB,
    srp_verifier  BLOB,
    srp_enabled   INTEGER NOT NULL DEFAULT 0,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at    DATETIME
);

CREATE TABLE IF NOT EXISTS devices (
    id             TEXT PRIMARY KEY,
    user_id        TEXT NOT NULL,
    device_name    TEXT NOT NULL DEFAULT '',
    device_type    TEXT NOT NULL DEFAULT '',
    last_sync_at   DATETIME,
    last_sync_ver  INTEGER NOT NULL DEFAULT 0,
    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at     DATETIME
);

CREATE TABLE IF NOT EXISTS sync_records (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL,
    device_id   TEXT NOT NULL DEFAULT '',
    note_id     TEXT NOT NULL,
    action      TEXT NOT NULL DEFAULT 'update',
    version     INTEGER NOT NULL,
    timestamp   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    payload     TEXT NOT NULL DEFAULT '',
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at  DATETIME
);

CREATE TABLE IF NOT EXISTS note_snapshots (
    id          TEXT PRIMARY KEY,
    note_id     TEXT NOT NULL,
    user_id     TEXT NOT NULL,
    version     INTEGER NOT NULL,
    content     TEXT NOT NULL DEFAULT '',
    checksum    TEXT NOT NULL DEFAULT '',
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at  DATETIME
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL,
    token       TEXT NOT NULL UNIQUE,
    expires_at  DATETIME NOT NULL,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked     INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS shared_notes (
    id             TEXT PRIMARY KEY,
    user_id        TEXT NOT NULL,
    note_id        TEXT NOT NULL,
    share_token    TEXT NOT NULL UNIQUE,
    title          TEXT NOT NULL DEFAULT '',
    content        TEXT NOT NULL DEFAULT '',
    password_hash  TEXT NOT NULL DEFAULT '',
    has_password   INTEGER NOT NULL DEFAULT 0,
    expires_at     DATETIME,
    view_count     INTEGER NOT NULL DEFAULT 0,
    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at     DATETIME
);

CREATE TABLE IF NOT EXISTS user_email_aliases (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL,
    alias       TEXT NOT NULL UNIQUE,
    email_addr  TEXT NOT NULL UNIQUE,
    active      INTEGER NOT NULL DEFAULT 1,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices(user_id);
CREATE INDEX IF NOT EXISTS idx_sync_records_user_id ON sync_records(user_id);
CREATE INDEX IF NOT EXISTS idx_sync_records_version ON sync_records(version);
CREATE INDEX IF NOT EXISTS idx_note_snapshots_note_id ON note_snapshots(note_id);
CREATE INDEX IF NOT EXISTS idx_note_snapshots_user_id ON note_snapshots(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_shared_notes_user_id ON shared_notes(user_id);
CREATE INDEX IF NOT EXISTS idx_shared_notes_share_token ON shared_notes(share_token);
CREATE INDEX IF NOT EXISTS idx_user_email_aliases_user_id ON user_email_aliases(user_id);
CREATE INDEX IF NOT EXISTS idx_user_email_aliases_email_addr ON user_email_aliases(email_addr);
