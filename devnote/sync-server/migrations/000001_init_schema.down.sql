-- 回滚 sync-server 初始 schema

DROP INDEX IF EXISTS idx_user_email_aliases_email_addr;
DROP INDEX IF EXISTS idx_user_email_aliases_user_id;
DROP INDEX IF EXISTS idx_shared_notes_share_token;
DROP INDEX IF EXISTS idx_shared_notes_user_id;
DROP INDEX IF EXISTS idx_refresh_tokens_user_id;
DROP INDEX IF EXISTS idx_note_snapshots_user_id;
DROP INDEX IF EXISTS idx_note_snapshots_note_id;
DROP INDEX IF EXISTS idx_sync_records_version;
DROP INDEX IF EXISTS idx_sync_records_user_id;
DROP INDEX IF EXISTS idx_devices_user_id;

DROP TABLE IF EXISTS user_email_aliases;
DROP TABLE IF EXISTS shared_notes;
DROP TABLE IF EXISTS refresh_tokens;
DROP TABLE IF EXISTS note_snapshots;
DROP TABLE IF EXISTS sync_records;
DROP TABLE IF EXISTS devices;
DROP TABLE IF EXISTS users;
