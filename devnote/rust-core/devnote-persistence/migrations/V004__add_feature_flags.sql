-- V004: 功能开关表结构
-- 提取自 devnote-persistence/src/lib.rs 中的 SCHEMA_V4 常量
-- 所有语句均使用 IF NOT EXISTS，确保幂等可重复执行

CREATE TABLE IF NOT EXISTS feature_flags (
    key TEXT PRIMARY KEY,
    enabled INTEGER NOT NULL DEFAULT 0,
    description TEXT NOT NULL DEFAULT '',
    updated_at INTEGER NOT NULL
);
