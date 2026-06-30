# ADR-007: 三端字段映射矩阵

## 状态

已采纳 (2025-06-25)

## 背景

DevNote 跨三端技术栈：Go 服务端（business-server / sync-server）、Rust 核心层（devnote-core）、Dart 客户端（Flutter UI）。三端各自维护数据模型，字段命名、表名、以及模型组成存在差异，导致：

1. 跨端 bug 难以定位（字段名不一致导致序列化/反序列化异常）
2. 新成员无法快速理解各端模型对应关系
3. API 文档与实现不一致（API 可能返回 `modified_at`，但客户端期望 `updated_at`）

## 决策

### 1. Source of Truth 原则

| 层级 | 角色 | Source of Truth |
|------|------|-----------------|
| Rust 核心层 | 本地持久化 + 核心业务逻辑 | **Rust 模型为准** |
| Go 服务端 | 同步中继 + 业务 API | 跟随 Rust 模型（向下兼容） |
| Dart 客户端 | UI 展示 + 交互 | 跟随 Rust 模型（通过 FFI 自动映射） |

### 2. 字段映射矩阵

#### Note 模型

| 概念 | Rust (`Note`) | Go (`NoteMeta`) | Dart (`NoteModel`) |
|------|--------------|-----------------|---------------------|
| **主键** | `id: Uuid` | `ID: string` | `id: String` |
| **标题** | `title: String` | `Title: string` | `title: String` |
| **内容/块** | `blocks: Vec<Block>` | ❌ 无 | `blocks: List<BlockModel>` |
| **文件夹** | `folder_id: Uuid` | ❌ 无 | `folderId: String` |
| **标签** | `tags: Vec<Tag>` | ❌ 无 | `tags: List<String>` |
| **更新时间** | `updated_at: DateTime` | `ModifiedAt: time.Time` | `updatedAt: DateTime` |
| **创建时间** | `created_at: DateTime` | `CreatedAt: time.Time` | `createdAt: DateTime` |
| **置顶** | `is_pinned: bool` | `IsPinned: bool` | `isPinned: bool` |
| **加密** | `is_encrypted: bool` | `IsEncrypted: bool` | `isEncrypted: bool` |
| **排序** | `sort_order: i32` | ❌ 无 | `sortOrder: int` |
| **颜色** | `color: Option<String>` | ❌ 无 | `color: String?` |

#### Folder 模型

| 概念 | Rust (`Folder`) | Go (`FolderMeta`) | Dart (`FolderModel`) |
|------|----------------|-------------------|----------------------|
| **主键** | `id: Uuid` | `ID: string` | `id: String` |
| **名称** | `name: String` | `Name: string` | `name: String` |
| **父节点** | `parent_id: Option<Uuid>` | `ParentID: *string` | `parentId: String?` |
| **排序** | `sort_order: i32` | ❌ 无 | `sortOrder: int` |
| **更新时间** | `updated_at: DateTime` | `ModifiedAt: time.Time` | `updatedAt: DateTime` |
| **创建时间** | `created_at: DateTime` | `CreatedAt: time.Time` | `createdAt: DateTime` |

#### Tag 模型

| 概念 | Rust (`Tag`) | Go (`Tag`) | Dart (`TagModel`) |
|------|------------|-----------|-------------------|
| **主键** | `id: Uuid` | `ID: string` | `id: String` |
| **名称** | `name: String` | `Name: string` | `name: String` |
| **颜色** | `color: Option<String>` | ❌ 无 | `color: String?` |
| **创建时间** | `created_at: DateTime` | `CreatedAt: time.Time` | `createdAt: DateTime` |

### 3. 表名映射

| 概念 | Rust/Dart 表名 | Go 表名 | 说明 |
|------|---------------|---------|------|
| 笔记 | `notes` | `note_meta` | Go 服务端使用 `_meta` 后缀区分元数据 |
| 文件夹 | `folders` | `folder_meta` | 同上 |
| 标签 | `tags` | `tags` | 一致 |
| 笔记-标签关联 | `note_tags` | `note_tags` | 一致 |
| 块 | `blocks` | ❌ 无 | Go 服务端不存储块数据 |
| 附件 | `attachments` | ❌ 无 | Go 服务端不存储附件 |

### 4. 时间字段命名约定

| Rust/Dart | Go | API JSON |
|-----------|-----|----------|
| `created_at` | `CreatedAt` | `created_at` |
| `updated_at` | `ModifiedAt` | `modified_at` |

**重要**: 由于 Go 端已广泛使用 `modified_at`，API JSON 保持 `modified_at` 命名不变。Rust FFI 端序列化使用 `updated_at`，Dart 端反序列化时两者均接受。Go 服务端在下一大版本（v2 API）中统一为 `updated_at`。

### 5. 序列化约定

- **Rust → Dart (FFI)**: 通过 `flutter_rust_bridge` 自动序列化，使用 camelCase (JSON)
- **Rust → SQLite**: `rusqlite` 直接映射，字段名 snake_case
- **Go → SQLite**: `database/sql` 直接映射，字段名 PascalCase
- **Go → JSON API**: `encoding/json` struct tags，字段名 snake_case
- **Dart → SQLite (sqflite)**: 手动映射，字段名 camelCase（已弃用，FFI 模式替代）

### 6. 向后兼容性

- Go 服务端 API 保持 `modified_at` 字段名，直至 v2 API
- Dart 端 `NoteModel.fromJson` 同时接受 `updated_at` 和 `modified_at`
- Go 端 `NoteMeta` 暂不添加 `content/blocks/tags/folder_id` 字段（服务端不存储内容）

## 影响

- **Rust**: 无变更（Rust 模型为 source of truth）
- **Go**: 保持在 `modified_at` 命名，v2 统一为 `updated_at`
- **Dart**: 新增 `fromJson` 兼容性，同时接受两种命名
- **文档**: 本 ADR 作为跨端映射的唯一参考文档

## 备选方案

1. **立即统一为 `updated_at`**: 破坏现有 API 兼容性，需要客户端同步升级
2. **Go 端新增字段**: 增加服务端存储开销，且与"服务端不存内容"的设计原则冲突
3. **不做任何改变**: 长期维护成本高，新成员学习曲线陡峭

## 参考资料

- [ADR-003: 五层架构](file:///workspace/devnote/docs/adr/003-five-layer-architecture.md)
- [ADR-004: SQLite 持久化](file:///workspace/devnote/docs/adr/004-sqlite-for-persistence.md)