# 数据库迁移版本协调规范

> **状态**: Accepted
> **日期**: 2026-06-23
> **关联 ADR**: [ADR 004 — SQLite 作为主要持久化层](adr/004-sqlite-for-persistence.md)

## 1. 背景

DevNote 采用三端 SQLite 架构，每端有独立的 schema 和迁移管理：

| 端 | 迁移工具 | 迁移版本 | 数据库文件 |
|----|----------|----------|-----------|
| Flutter（客户端） | sqflite `onCreate`/`onUpgrade` 回调 | 整数版本 1–7 | `devnote.db` |
| business-server | golang-migrate（文件式） | `000001` | `business.db` |
| sync-server | golang-migrate（文件式） | `000001` | `sync.db` |

三端 schema **有意分离**，不是漂移：

- **Flutter 端**：完整的本地数据库（笔记内容、文件夹、标签、附件、块、对象数据库、FTS 全文索引），支持离线编辑。
- **business-server**：笔记**元数据**服务（不含内容），管理标签层级、文件夹树、知识图谱、校验规则。
- **sync-server**：笔记**内容快照**与同步服务，管理用户认证、设备同步、版本历史、分享、邮件转笔记。

笔记内容存储在 sync-server 的 `note_snapshots.content`，元数据存储在 business-server 的 `note_meta`，客户端本地存储完整数据。三端通过 `note_id` 关联。

## 2. Schema 概念映射

### 2.1 笔记

| 概念 | Flutter `notes` | business-server `note_meta` | sync-server `note_snapshots` |
|------|----------------|-----------------------------|-------------------------------|
| 主键 | `id` (TEXT) | `id` (TEXT) | `id` (TEXT, 快照 ID) |
| 笔记 ID | `id` | `id` | `note_id` (TEXT) |
| 用户 ID | — (单用户) | `user_id` (TEXT) | `user_id` (TEXT) |
| 标题 | `title` | `title` | `title` (在 `shared_notes` 中) |
| 内容 | `content` | — (不存储内容) | `content` + `checksum` |
| 加密 | `is_encrypted` | `is_encrypted` + `content_hash` | — |
| 时间戳 | `created_at`/`updated_at` (TEXT) | `created_at`/`modified_at` (DATETIME) | `created_at` (DATETIME) |
| 版本 | — | — | `version` (INTEGER, 单调递增) |

### 2.2 文件夹

| 概念 | Flutter `folders` | business-server `folder_meta` |
|------|------------------|-------------------------------|
| 主键 | `id` | `id` |
| 名称 | `name` | `name` |
| 父级 | `parent_id` ( nullable) | `parent_id` + `path` (路径物化) |
| 排序 | `sort_order` | `sort_order` |
| 统计 | — | `note_count` + `child_count` |

### 2.3 标签

| 概念 | Flutter `tags` + `note_tags` | business-server `tag_meta` + `tag_relation` |
|------|------------------------------|---------------------------------------------|
| 标签表 | `tags` (id, name, color) | `tag_meta` (id, name, color, parent_id, use_count) |
| 关联表 | `note_tags` (note_id, tag_id) | `tag_relation` (tag_id, note_id, linked_at) |
| 层级 | — (扁平) | `parent_id` (树形) |

### 2.4 独有表

| 端 | 独有表 | 用途 |
|----|--------|------|
| Flutter | `attachments`, `blocks`, `databases`, `database_fields`, `database_rows`, `database_cells`, `database_views`, `object_types`, `object_properties`, `object_relations_definitions`, `objects`, `object_relations`, `notes_fts` (FTS5) | 本地编辑器、对象数据库、全文搜索 |
| business-server | `knowledge_relation`, `validation_rule`, `business_rule` | 知识图谱、校验规则 |
| sync-server | `users`, `devices`, `sync_records`, `refresh_tokens`, `shared_notes`, `user_email_aliases` | 认证、同步、分享、邮件 |

## 3. 版本协调规则

### 3.1 版本号命名

- **Flutter 端**：整数版本号（当前 7），通过 `onUpgrade` 回调按版本号递增执行。
- **Go 服务端**：golang-migrate 格式 `NNNNNN_description.up.sql` / `.down.sql`（当前 `000001`）。

### 3.2 协调规则

1. **三端版本号独立**：不强制对齐版本号。Flutter v7 不等于 business-server 000007。
2. **变更通知**：任一端 schema 变更时，必须在本文档"变更记录"中记录，并评估是否影响其他端。
3. **跨端影响评估清单**（变更时逐项检查）：
   - [ ] 新增/删除字段是否影响 sync-server 的 `payload`（JSON 格式）？
   - [ ] 新增/删除表是否需要 business-server 的元数据同步？
   - [ ] Flutter 端的 `onUpgrade` 是否需要数据迁移脚本？
   - [ ] sync-server 的 `note_snapshots.checksum` 算法是否需要更新？
4. **向后兼容**：Go 服务端迁移必须提供 `.down.sql` 回滚脚本。Flutter 端 `onUpgrade` 不可逆（sqflite 限制），需在迁移前备份。
5. **Flutter 端迁移前备份**：`_backupBeforeMigration()` 在升级前复制数据库文件，失败时回滚。

### 3.3 迁移文件命名约定

**Go 服务端**（golang-migrate）：
```
migrations/
  000001_init_schema.up.sql
  000001_init_schema.down.sql
  000002_add_xxx.up.sql          # 未来迁移示例
  000002_add_xxx.down.sql
```

**Flutter 端**（sqflite）：
```dart
// database_helper.dart
static const _databaseVersion = 7;

Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  final batch = db.batch();
  for (int v = oldVersion + 1; v <= newVersion; v++) {
    switch (v) {
      case 2: // v2 迁移
      case 3: // v3 迁移
      // ...
    }
  }
  await batch.commit();
}
```

## 4. 迁移工具对比

| 维度 | golang-migrate（Go 端） | sqflite onUpgrade（Flutter 端） |
|------|------------------------|-------------------------------|
| 迁移文件 | 独立 `.sql` 文件 | 代码内嵌 SQL |
| 版本追踪 | `schema_migrations` 表 | `schema_version` 表 |
| 回滚支持 | `.down.sql` | 不支持（需备份恢复） |
| 事务支持 | 自动事务 | `batch.commit()` |
| CI 验证 | `migrate -path ./migrations -database sqlite3://... up` | 集成测试中验证 |

## 5. CI 检查清单

在 CI 中执行以下检查，防止 schema 漂移：

```bash
# 1. Go 服务端迁移文件验证（确保 up/down 配对）
for dir in business-server/migrations sync-server/migrations; do
  ups=$(ls $dir/*.up.sql 2>/dev/null | wc -l)
  downs=$(ls $dir/*.down.sql 2>/dev/null | wc -l)
  [ "$ups" -eq "$downs" ] || { echo "ERROR: $dir 迁移文件 up/down 不配对"; exit 1; }
done

# 2. Go 服务端迁移可执行性验证（内存 SQLite）
migrate -path business-server/migrations -database "sqlite3://file::memory:?cache=shared" up
migrate -path sync-server/migrations -database "sqlite3://file::memory:?cache=shared" up

# 3. Flutter 端迁移版本号检查
grep "_databaseVersion" lib/core/persistence/database_helper.dart
```

## 6. 变更记录

| 日期 | 端 | 版本 | 变更描述 | 跨端影响 |
|------|----|------|----------|----------|
| 2026-06-23 | business-server | 000001 | 初始 schema（7 表） | 无 |
| 2026-06-23 | sync-server | 000001 | 初始 schema（7 表） | 无 |
| 2026-06-23 | Flutter | v7 | 当前版本（含数据库/对象/FTS 表） | 无 |

> **新增迁移时必须更新此表。**
