# ADR 004: SQLite 作为持久化层

| 属性 | 值 |
|------|------|
| **标题** | 使用 SQLite 作为主要持久化层 |
| **状态** | Accepted |
| **日期** | 2025-02-10 |
| **决策者** | DevNote 核心架构团队 |

## 上下文

DevNote 作为本地优先的笔记应用，需要一个可靠的本地存储方案来持久化笔记、文件夹、标签、用户设置、同步状态等数据。

### 存储需求

1. **关系型数据**：笔记与文件夹（层级关系）、笔记与标签（多对多）、笔记与附件（一对多）。
2. **全文搜索**：笔记内容需要支持全文检索、高亮显示。
3. **事务支持**：同步操作需要原子性，确保数据一致性。
4. **跨平台**：同一份数据文件在桌面和移动端兼容。
5. **零运维**：不需要外部数据库服务，嵌入式数据库即可。

### 备选方案

| 方案 | 优势 | 劣势 |
|------|------|------|
| **SQLite** | 嵌入式、零配置、ACID 事务、全文搜索 (FTS5)、广泛验证 | 高并发写受限（WAL 模式可缓解）、单文件上限 282TB |
| PostgreSQL | 功能丰富、高并发、JSONB 支持 | 需要外部服务、不适合嵌入式场景 |
| LevelDB/RocksDB | 键值存储、高性能写 | 不支持 SQL 查询、关系建模困难、无内置事务 |
| Realm | 对象存储、跨平台同步 | 闭源核心部分、社区较小 |
| WatermelonDB | React Native 优化、离线优先 | 仅适用于 JS 生态 |
| JSON 文件 | 简单、人类可读 | 无事务、无索引、并发不安全、查询效率低 |

## 决策

选择 **SQLite** 作为 DevNote 的唯一持久化层，通过 `rusqlite`（Rust）进行访问。

### Schema 设计

```sql
-- 笔记表
CREATE TABLE notes (
    id          TEXT PRIMARY KEY,
    title       TEXT NOT NULL DEFAULT '',
    content     TEXT NOT NULL DEFAULT '',  -- JSON 格式存储 Block 数据
    folder_id   TEXT REFERENCES folders(id),
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    version     INTEGER NOT NULL DEFAULT 1,
    is_deleted  INTEGER NOT NULL DEFAULT 0,
    encrypted   INTEGER NOT NULL DEFAULT 0
);

-- 文件夹表
CREATE TABLE folders (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    parent_id   TEXT REFERENCES folders(id),
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,
    is_deleted  INTEGER NOT NULL DEFAULT 0
);

-- 标签表
CREATE TABLE tags (
    id      TEXT PRIMARY KEY,
    name    TEXT NOT NULL UNIQUE,
    color   TEXT NOT NULL DEFAULT '#888888'
);

-- 笔记-标签关联表
CREATE TABLE note_tags (
    note_id TEXT REFERENCES notes(id) ON DELETE CASCADE,
    tag_id  TEXT REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (note_id, tag_id)
);

-- 全文搜索索引
CREATE VIRTUAL TABLE notes_fts USING fts5(
    title, content,
    content='notes',
    content_rowid='rowid'
);

-- 同步日志表
CREATE TABLE sync_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    operation   TEXT NOT NULL,      -- create/update/delete
    entity_type TEXT NOT NULL,      -- note/folder/tag
    entity_id   TEXT NOT NULL,
    version     INTEGER NOT NULL,
    timestamp   INTEGER NOT NULL,
    synced      INTEGER NOT NULL DEFAULT 0
);

-- CRDT 操作日志表
CREATE TABLE crdt_operations (
    id          TEXT PRIMARY KEY,
    document_id TEXT NOT NULL,
    operation   TEXT NOT NULL,      -- JSON 格式的 CRDT 操作
    version     INTEGER NOT NULL,
    site_id     TEXT NOT NULL,
    timestamp   INTEGER NOT NULL
);
```

### 关键配置

```rust
// WAL 模式：提高并发写性能
PRAGMA journal_mode = WAL;

// 同步模式：FULL 保证数据不丢失
PRAGMA synchronous = FULL;

// 外键约束
PRAGMA foreign_keys = ON;

// 内存映射 I/O：提升读取性能
PRAGMA mmap_size = 268435456;  // 256MB

// 缓存大小
PRAGMA cache_size = -64000;    // 64MB
```

### 访问层

- **Rust 端**：`rusqlite` 直接操作，由 `devnote-persistence` crate 封装。
- **Dart 端**：废弃 `sqflite`，所有数据操作通过 FFI 调用 Rust 端执行。

## 后果

### 正面

- **零运维**：无需安装和配置外部数据库，应用启动即可使用。
- **成熟稳定**：SQLite 是世界上最广泛部署的数据库，可靠性经过数十年验证。
- **全文搜索**：FTS5 扩展提供高效的全文检索能力，支持拼音分词。
- **事务支持**：ACID 事务保证同步操作的数据一致性。
- **跨平台兼容**：SQLite 数据文件在 macOS/Linux/Windows/iOS/Android 完全兼容。
- **性能优异**：WAL 模式下读操作完全并发，写操作性能提升 10-50 倍。

### 负面

- **并发写限制**：同一时刻只能有一个写者，高并发写场景需要队列化。
- **大文件性能**：单个数据库文件过大（>1GB）时性能下降，需要定期 VACUUM。
- **Schema 迁移**：数据库结构变更需要手动编写迁移脚本，无自动迁移框架。

### 已识别风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| 数据库损坏 | 定期 `PRAGMA integrity_check`；WAL 模式下的自动恢复机制 |
| 大文件性能下降 | 定期执行 `VACUUM`；拆分大表（如将笔记内容单独存储） |
| Schema 迁移失败 | 迁移脚本包裹在事务中；迁移前备份数据库文件 |
| 双源真理 | 统一使用 Rust rusqlite，废弃 Dart sqflite |
