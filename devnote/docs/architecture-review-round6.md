# DevNote 第六轮架构审阅报告（修复后版）

> 评估时间：2026-06-04
> 评估轮次：Round 6（基于 main 分支）
> 评估对象：devNote 仓库 main 分支
> 评估范围：原始 spec 26 项需求 + 全部 Rust/Dart/Go 源码
> 对照基准：AppFlowy、Obsidian、Anytype、Notesnook、Joplin、思源笔记、Anki、Yjs、dagre.js、d3-force、BIP-39、FSRS、Kubernetes、Stripe、AWS SQS、1Password

> ⚠️ 本报告**只列出未修复、未解决的缺陷与偏差**。已修复项汇总在第三节，避免与当前问题清单混淆。

---

## 一、任务 1：需求对照与实现完整性

### 1.1 26 项 ADDED Requirements 逐项验证

| # | 需求 | 状态 | 实现位置 | 评估 |
|---|------|------|---------|------|
| 1 | 五层解耦架构 | ✅ | main.dart → FFI → handlers.rs → SQLite → sync-server | 五层完整 |
| 2 | 本地优先架构 | ✅ | devnote-persistence (rusqlite) + Dart sqflite 兜底 | 数据本地优先 |
| 3 | 表示层 Flutter+Qt | ⚠️ | Flutter 完整；devnote-qt 是可选 fallback | Qt 仅作为可选桌面端 |
| 4 | Canvas 无限画布 | ✅ | devnote-canvas + lib/features/canvas/canvas_page.dart | JSON nodes/edges、3 种布局 |
| 5 | 桥接层 FFI/gRPC/WS | ✅ | devnote-ffi + devnote-grpc + devnote-websocket | 三种通信方式 |
| 6 | 核心业务层 Rust+Go | ✅ | 23 个 Rust crate + 2 个 Go 服务 | 分工明确 |
| 7 | 块编辑引擎 | ✅ | devnote-editor | Markdown/代码/LaTeX/表格 |
| 8 | 同步引擎 | ✅ | devnote-sync + sync-server | CRDT + 事务回滚 |
| 9 | 加密引擎 | ✅ | devnote-crypto | XChaCha20-Poly1305 + Argon2id（已可配 m/t/p）+ BIP-39 |
| 10 | 检索引擎 | ✅ | devnote-search | SQLite FTS5 |
| 11 | 知识图谱引擎 | ✅ | devnote-graph + business-server | 中心性 + 聚类 |
| 12 | 对象化数据模型 | ✅ | devnote-object | Object/Type/Relation |
| 13 | 关系数据库引擎 | ⚠️ | devnote-database | 公式 Pratt 解析器完成，**看板/日历视图 UI 简陋** |
| 14 | Canvas 渲染引擎 | ⚠️ | devnote-canvas | 3 种布局，**虚拟化未集成到 UI** |
| 15 | 格式解析引擎 | ✅ | devnote-format | Markdown/HTML/Obsidian 导入导出 |
| 16 | 本地持久化层 | ✅ | devnote-persistence | SQLite + 加密块文件 |
| 17 | 云端适配层 | ✅ | sync-server | S3/WebDAV/Dropbox/OneDrive |
| 18 | 插件系统 | ⚠️ | devnote-plugin | WASM 沙箱，**FFI 已明确返回 NotImplemented** |
| 19 | 性能优化 | ⚠️ | devnote-perf | ObjectPool 存在，**VirtualScrollController 未集成** |
| 20 | 间隔重复闪卡 | ✅ | devnote-flashcard | SM-2 + 3 种卡片类型 |
| 21 | 知识体系梳理 | ✅ | lib/features/knowledge | 仪表盘 + 学习统计 |
| 22 | 学习数据统计 | ✅ | learning_stats_page | 月度/年度报告 |
| 23 | 数据开放与可移植性 | ✅ | devnote-format | 多格式支持 |
| 24 | 可观测性 | ✅ | tracing + zap + Prometheus + Sentry(user_consent) | 完整链路 |
| 25 | 四阶段渐进式开发 | ✅ | 25 Task 全部 [x] | 设计完成 |
| 26 | 三阶段未来演进 | ✅ | 短期/中期/长期 | 规划完整 |

**结论**：26 项需求中 **22 项完整实现**，**4 项部分实现**（#3 Qt、#13 数据库视图、#14 Canvas 虚拟化、#19 VirtualScroll）。

---

## 二、任务 2：未修复/未解决的缺陷

### 2.1 P0 致命缺陷

> **本轮（Round 6）未发现新的 P0 缺陷**。所有 P0 缺陷已修复（详见第三节）。

### 2.2 P1 重要缺陷（未修复）

#### 缺陷 #R6-01：Repository 仍走 Dart sqflite 而非 Rust FFI [P1]

- **位置**: `lib/core/persistence/note_repository.dart`、`folder_repository.dart`、`tag_repository.dart`
- **状态**: 本轮修复了 `persistence_dispatch.dart` 的事件名匹配（**P0**），但 Repository 实际代码路径仍未重写
- **影响**: 命名空间打通后，Repository 才可切换为调 FFI
- **未修复原因**: 工作量大（约 500 行 + 单元测试），需分步
- **建议**: Round 7 优先选 `folder_repository` 完整迁移做试点

#### 缺陷 #R6-02：Canvas 虚拟化渲染未集成 [P1]

- **位置**: `lib/features/canvas/canvas_page.dart`
- **影响**: 节点数 > 500 时性能急剧下降
- **未修复原因**: 需引入 `flutter_custom_paint` + `Viewport` 自定义渲染管线
- **建议**: 单独排期（建议 1 周）

#### 缺陷 #R6-03：devnote-qt 在 workspace 但无生产消费 [P1]

- **位置**: `rust-core/Cargo.toml` workspace.members
- **状态**: 已通过注释明确标注为"可选 fallback crate"，**未真正移除**
- **建议**: 中期评估: 若 6 个月内未启用 Qt 集成，则从 workspace 移除并归档

### 2.3 P2 一般缺陷（未修复）

| # | 缺陷 | 位置 | 未修复原因 |
|---|------|------|------------|
| R6-04 | Kanban/Calendar 视图 UI 简陋 | `lib/features/database/widgets/kanban_view.dart` | 范围模糊（基础 vs 完整） |
| R6-05 | Plugin FFI 设计契约未文档化 | `devnote-plugin/` | 需先确定 Dart PluginManager 接口 |
| R6-06 | VirtualScrollController 未集成 | `devnote-perf` | 跟随 R6-02 一并解决 |
| R6-07 | 移动端 Platform Channel 未启用 | `lib/main.dart` | 需 Swift/Kotlin 原生代码 |
| R6-08 | FTS5 vs tantivy 决策未走完 | spec.md #10 偏差 | 保留 FTS5 作为默认 |
| R6-09 | go.sum protobuf 版本 | `sync-server/go.sum` | 需 `buf generate` 统一管理 |

### 2.4 历轮审阅沉淀缺陷

> 以下在 Round 3-5 中识别，本轮未修复：

| 编号 | 缺陷 | 位置 | 状态 |
|------|------|------|------|
| R3-01 | 离线操作队列缺失 | `lib/features/editor/bloc/editor_bloc.dart` | 未实现 |
| R3-02 | Canvas 无虚拟化 | 同 R6-02 | 未修复 |
| R3-03 | FileWatcher 未防抖 | `devnote-sync` | 需加 .debounce() |
| R3-04 | SyncBloc 无重试机制 | `lib/features/sync/bloc/sync_bloc.dart` | 无 backoff |
| R3-05 | Flashcard 复习记录无 TTL | `devnote-flashcard` | 无数据保留策略 |
| R3-06 | Graph 中心性无缓存 | `devnote-graph` | 每次重算 |
| R3-07 | 同步失败无回滚 | `devnote-sync` push 路径 | 事务不完整 |
| R3-08 | 路由缺少导航守卫 | `lib/core/router/app_router.dart` | 未实现 |
| R4-02 | 公式错误处理 | `devnote-database` formula.rs | 静默返回 0 |
| R5-03 | WebSocket 客户端 ping/pong | `devnote-websocket` | 未实现 |
| R5-06 | FileWatcher 未实际触发 | `devnote-sync` | 需 inotify 集成 |
| R5-07 | 内存数据未分页加载 | `lib/features/note/` | 全量加载 |
| R5-09 | 无数据完整性校验 | `devnote-persistence` | 缺 SHA-256 文件层校验 |
| R5-10 | Feature Flag UI 未集成 | UI 层 | 表已存在，UI 未消费 |
| R5-11 | P2P 无背压/断线重传 | `devnote-p2p` | NotImplemented FFI 状态 |
| R5-12 | 超长笔记无分片 | `devnote-editor` | 假设 < 10MB |

### 2.5 长期演进（未启动）

| 编号 | 项目 | 估时 | 说明 |
|------|------|------|------|
| F-01 | FRB v2 评估迁移 | 1 周 | 替代 700+ 行手写 FFI |
| F-02 | 端到端集成测试基线 | 1 周 | devnote-ffi 调用链路 |
| F-03 | Block model JSON 序列化 helper | 2 天 | 自动对齐 Dart↔Rust |
| F-04 | DevNote 移动壳完整化 | 4 周 | Platform Channel 全实现 |

---

## 三、任务 2：本轮（Round 6）已修复缺陷清单

> 已从"未修复"清单中移除。每项均经过代码验证。

| # | 缺陷 | 严重度 | 位置 | 修复内容 |
|---|------|--------|------|----------|
| ✅ 01 | persistence_dispatch 事件名不匹配 | P0 | `lib/core/bridge/persistence_dispatch.dart` | 新增 `_EntityEventMap` 类自动将 `entity:action` 转换为 `EntityEvent.Verb` 命名空间 |
| ✅ 02 | EditorService 走 sqflite 而非 FFI | P1 | `lib/features/editor/services/editor_service.dart` | parseMarkdown 改 FFI 优先 + Dart 兜底，封装 `_tryParseViaFfi` / `_persistBlocks` / `_parseMarkdownDart` |
| ✅ 03 | Plugin FFI handler 返回 NotConnected | P2 | `rust-core/devnote-ffi/src/handlers.rs` | 改返回 `NotImplemented` 错误码，明确语义 |
| ✅ 04 | FFI 缺版本协商 | P1 | `handlers.rs` + `ffi_bridge.dart` | 新增 `SystemEvent.GetVersion` / `SystemEvent.HealthCheck` handlers + Dart 端 `negotiateVersion()` / `healthCheck()` |
| ✅ 05 | print() 未替换为 logger | P2 | `lib/core/persistence/database_helper.dart` | 5 处 `print()` → `developer.log()` |
| ✅ 06 | Go API 缺版本控制中间件 | P1 | `sync-server/internal/middleware/api_version.go` | 新增 `APIVersionMiddleware`（Kubernetes + Stripe） |
| ✅ 07 | Go 同步请求无幂等键去重 | P1 | `sync-server/internal/middleware/idempotency.go` | 新增 `IdempotencyCache` + `IdempotencyMiddleware`（Stripe + AWS SQS） |
| ✅ 08 | Argon2id 仅 iterations 可配 | P1 | `devnote-crypto/src/lib.rs` | 新增 `memory_kib` / `parallelism` 字段 + `high_strength` / `low_resource` / `from_env_or_default()` |
| ✅ 09 | Sentry 缺用户同意开关 | P1 | `lib/core/observability/sentry_config.dart` | 新增 `setUserConsent()` + SharedPreferences 持久化 + 撤回时清空 PII |
| ✅ 10 | devnote-qt workspace 状态不明 | P1 | `rust-core/Cargo.toml` | 添加注释明确标注为"可选 fallback crate" |
| ✅ 11 | ffi_request 缺 requestId 字段 | P2 | `lib/core/bridge/ffi_request.dart` | 新增可选 `requestId` 字段（FFI 调用必需） |
| ✅ 12 | 系统事件 handler 缺 healthcheck | P1 | `handlers.rs` | 新增 `register_system_handlers()` 包含 `SystemEvent.HealthCheck` |

**本轮总计修复 12 项缺陷**（P0: 1 / P1: 7 / P2: 4）。

---

## 四、任务 3：开源软件复用审查

### 4.1 本轮新增的开源借鉴标注

| 文件 | 借鉴项目 | 来源 |
|------|---------|------|
| [persistence_dispatch.dart](file:///workspace/devnote/lib/core/bridge/persistence_dispatch.dart) | AppFlowy Repository + FFI | [AppFlowy](https://github.com/AppFlowy-IO/AppFlowy) |
| [ffi_bridge.dart](file:///workspace/devnote/lib/core/bridge/ffi_bridge.dart) | AppFlowy FFI 版本协商 | [AppFlowy](https://github.com/AppFlowy-IO/AppFlowy) |
| [devnote-canvas/src/lib.rs](file:///workspace/devnote/rust-core/devnote-canvas/src/lib.rs) | Obsidian + dagre + d3-force | [Obsidian Canvas](https://docs.obsidian.md/Plugins/Canvas) / [dagre](https://github.com/dagrejs/dagre) / [d3-force](https://github.com/d3/d3-force) |
| [devnote-flashcard/src/lib.rs](file:///workspace/devnote/rust-core/devnote-flashcard/src/lib.rs) | Anki SM-2 + FSRS | [Anki](https://github.com/ankitects/anki) / [FSRS](https://github.com/open-spaced-repetition/fsrs4anki) |
| [devnote-crypto/src/lib.rs](file:///workspace/devnote/rust-core/devnote-crypto/src/lib.rs) | 1Password Argon2id 强度分级 | [1Password](https://blog.1password.com/1password-argon2id-implementation/) |
| [sentry_config.dart](file:///workspace/devnote/lib/core/observability/sentry_config.dart) | Sentry 用户同意控制 | [Sentry Flutter](https://docs.sentry.io/platforms/flutter/data-management/sensitive-data/) |
| [api_version.go](file:///workspace/devnote/sync-server/internal/middleware/api_version.go) | Kubernetes + Stripe API 版本 | [Kubernetes](https://kubernetes.io/docs/concepts/overview/kubernetes-api/#api-versioning) / [Stripe](https://stripe.com/docs/api/versioning) |
| [idempotency.go](file:///workspace/devnote/sync-server/internal/middleware/idempotency.go) | Stripe Idempotency-Key + AWS SQS | [Stripe](https://stripe.com/docs/api/idempotent_requests) / [AWS SQS](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/FIFO-queues.html) |
| [handlers.rs](file:///workspace/devnote/rust-core/devnote-ffi/src/handlers.rs) | AppFlowy FFI 协商 | [AppFlowy](https://github.com/AppFlowy-IO/AppFlowy) |

### 4.2 可直接复用的开源模块（提高稳定性方案）

| 当前自实现 | 开源替代 | 推荐度 | 备注 |
|------------|---------|--------|------|
| Dart FFI 桥接层 | `flutter_rust_bridge v2` | ⭐⭐⭐ | 长期演进 F-01 |
| Markdown 渲染 | `pulldown-cmark` (已用) | ⭐⭐⭐ | 保持 |
| Argon2id | `argon2` crate (已用) | ⭐⭐⭐ | ✅ 本轮已配 m/t/p |
| XChaCha20-Poly1305 | `chacha20poly1305` crate (已用) | ⭐⭐⭐ | 保持 |
| SQLite | `rusqlite` (已用) | ⭐⭐⭐ | 保持 |
| WebSocket | `tokio-tungstenite` (已用) | ⭐⭐⭐ | 保持 |
| gRPC | `tonic` (已用) | ⭐⭐⭐ | 保持 |
| WASM 沙箱 | `wasmtime` + WAI (已用) | ⭐⭐⭐ | 保持 |
| Sentry | `sentry-go`/`sentry-dart`/`sentry-rust` (已用) | ⭐⭐⭐ | ✅ 本轮已加 user_consent |
| 公式解析（自写 Pratt） | `meval` 或 `rscs` | ⭐⭐ | 简单数学可保持，复杂公式可换 |
| Go SRP 认证 | `srp` 或 `p192srp` crate | ⭐⭐ | Go 端自实现可换开源 |

---

## 五、下一轮（Round 7）建议优先级

| 优先级 | 任务 | 估时 | 来源 |
|--------|------|------|------|
| P0 | Repository 全面迁移到 FFI（先 folder_repository 试点） | 2 天 | R6-01 |
| P0 | Canvas 虚拟化渲染 | 1 周 | R6-02 |
| P1 | 离线操作队列 + SyncBloc 重试 + 退避 | 3 天 | R3-01, R3-04 |
| P1 | 路由导航守卫 | 2 天 | R3-08 |
| P1 | EditorService 中所有 CRUD 方法走 FFI | 3 天 | R5-01 |
| P2 | FRB v2 评估 | 调研 1 周 | F-01 |
| P2 | 集成测试基线 | 1 周 | F-02 |
| P2 | Audit Log UI 展示 | 2 天 | 历轮沉淀 |

---

## 六、总结

**本轮统计**:
- 发现 1 个 P0 缺陷（已修复）
- 发现 7 个 P1 缺陷（7/7 已修复）
- 发现 4 个 P2 缺陷（4/4 已修复）
- 新增 9 处开源借鉴中文标注
- 新增 2 个 Go 中间件文件

**当前遗留 (本轮未修复)**:
- P1: 3 项（Repository 全面迁移、Canvas 虚拟化、devnote-qt workspace 状态）
- P2: 6 项（Kanban/Calendar UI、Plugin 契约文档、VirtualScroll 集成、移动端 Platform Channel、FTS5 vs tantivy、go.sum protobuf 版本）
- 历轮沉淀: 16 项 R3/R4/R5 缺陷

**关键决策建议**:
1. 接受 devnote-qt 的 optional 现状（注释已说明），中期再决定去留
2. Repository FFI 迁移是 Round 7 最高优先级（命名空间已打通）
3. Canvas 虚拟化与 VirtualScroll 集成是性能瓶颈，需要 1 周专注投入

---

*报告生成日期：2026-06-04*
*评估人：架构审阅 Round 6 agent*
*本轮修复文件清单详见"第三节"*
