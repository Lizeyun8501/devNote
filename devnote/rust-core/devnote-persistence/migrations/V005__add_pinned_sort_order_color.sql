-- V005: 跨端数据模型对齐
-- P1 架构修复 (3.4): 统一迁移系统到 refinery，移除手动 SCHEMA_V1~V5 迁移
-- 为 notes 添加 is_pinned/is_encrypted 列（与 Rust Note 模型对齐）
-- 为 folders 添加 sort_order 列（与 Rust Folder 模型对齐）
-- 为 tags 添加 color 列（与 Rust Tag 模型对齐）

ALTER TABLE notes ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;
ALTER TABLE notes ADD COLUMN is_encrypted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE folders ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0;
ALTER TABLE tags ADD COLUMN color TEXT;
