# DevNote 架构优化建议报告

> 生成时间：2025-06-03
> 评估轮次：Round 1 + Round 2（独立复审）
> 评估对象：DevNote 五层解耦架构（Flutter 表示层 + Dart FFI 桥接层 + Rust/Go 核心层 + SQLite 持久化层 + Go 同步服务层）
> 代码规模：459 个源文件，约 154,325 行
> 对照基准：AppFlowy、Obsidian、Notion、Anytype、思源笔记、Notesnook、Joplin、Logseq、Bitwarden、libp2p、tonic、tracing 等

---

## 一、严重问题（架构性缺陷，Round 1）

### 1.1 `devnote_dispatch` 是空壳实现

**位置**: `rust-core/devnote-ffi/src/lib.rs:70-113`

**问题**: `handle_dispatch` 对所有事件返回固定 `code:0, data:payload`，完全无业务逻辑。这是整个 FFI 桥接层的核心入口，本应是请求路由+业务分发总枢纽。

**对照**:
- AppFlowy 的 `event.rs` 使用 `AFEventDispatcher` 注册每个事件的实际 handler
- Obsidian 的 `obsidian.ts` 用 `Plugin.commands` + `addCommand` 注册命令并真正执行

**建议**:
```rust
lazy_static! {
    static ref EVENT_REGISTRY: RwLock<HashMap<String, Box<dyn EventHandler>>> = 
        RwLock::new(HashMap::new());
}

pub fn register_handler(event: &str, handler: Box<dyn EventHandler>) {
    EVENT_REGISTRY.write().unwrap().insert(event.to_string(), handler);
}

fn handle_dispatch(event: &str, payload: Option<&str>) -> DispatchResponse {
    let registry = EVENT_REGISTRY.read().unwrap();
    match registry.get(event) {
        Some(handler) => handler.handle(payload),
        None => DispatchResponse { 
            code: -1, 
            message: format!("unknown event: {}", event), 
            data: None 
        },
    }
}
```

### 1.2 Rust 引擎完全未挂载到 Dart 应用

**位置**: `lib/main.dart`

**问题**: Flutter 应用启动时**没有任何代码调用** `FFIBridge.instance.init()` 加载动态库；没有任何 BLoC 实际通过 Dispatch 调用 Rust。Rust FFI 写了几百行，Dart 端有 sqflite/notes_bloc/folder_bloc 在用 SQLite，**两者完全脱节**。

**对照**: AppFlowy 的 `flutter_app.dart` 在 `main()` 中显式 `await rustDeskPlugin.init()`、`AppFlowyApplication.run()` 启动 Rust 引擎。

**建议**:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FFIBridge.instance.init();
  await Dispatch.instance.init();
  runApp(DevNoteApp());
}
```

### 1.3 重复的持久化层（双源真理）

**位置**:
- `lib/core/persistence/database_helper.dart`（Dart sqflite）
- `rust-core/devnote-persistence/src/lib.rs`（Rust rusqlite）

**问题**: 两套独立的 SQLite 架构、独立 schema（字段名有小写差异 `note_id` vs `noteId`）、独立连接管理。

**对照**: AppFlowy 只有 Rust 一份存储；Joplin 只有 JS 一份存储。

### 1.4 编辑器是内存数据结构（无持久化闭环）

**位置**: `lib/features/editor/services/editor_service.dart:6`

```dart
final Map<String, List<BlockModel>> _noteBlocks = {};  // 进程内 Map
```

**问题**: 用户笔记内容保存在 Dart 进程的 `Map` 中，**应用退出全部丢失**。

---

## 二、循环依赖与分层问题

### 2.1 devnote-core ↔ devnote-sync 循环依赖

**位置**: `rust-core/devnote-core/src/lib.rs:9-10`

**建议**: 抽出 `devnote-events` crate，只放事件枚举（无业务依赖），所有 crate 依赖它。

### 2.2 devnote-ffi 错误地依赖 devnote-grpc/websocket

**位置**: `rust-core/devnote-ffi/Cargo.toml:12-14`

### 2.3 devnote-canvas 内部用 libloading 检查 Qt

**位置**: `rust-core/devnote-canvas/src/lib.rs:30-38`

---

## 三、性能与资源问题

### 3.1 FFI 同步阻塞异步 runtime

**位置**: `rust-core/devnote-ffi/src/lib.rs:216`

### 3.2 每次 FFI 调用 malloc 大块字符串

**位置**: `lib/core/bridge/dispatch.dart:86-92`

### 3.3 全局 Mutex + LazyLock 在每个 FFI 调用都 lock

**位置**: `rust-core/devnote-ffi/src/lib.rs:220`

### 3.4 手写 base64_encode 重复造轮子

**位置**: `rust-core/devnote-ffi/src/lib.rs:388-410`

---

## 四、错误处理与可观测性

### 4.1 FFI 接口无错误码语义

**位置**: `rust-core/devnote-ffi/src/lib.rs:37`

### 4.2 tracing 未真正初始化

**位置**: `rust-core/devnote-observe/src/lib.rs`

### 4.3 Go 业务层无熔断/限流

**位置**: `business-server/internal/handler/knowledge_handler.go`

---

## 五、安全与一致性

### 5.1 SRP 协议与 Bcrypt 并存造成歧义

**位置**: `sync-server/internal/service/auth_service.go`

### 5.2 自签证书直接上线

**位置**: `sync-server/internal/cert/generate.go`

### 5.3 IPFS HTTP API 无认证

**位置**: `rust-core/devnote-ipfs/src/lib.rs`

### 5.4 WebSocket 无 Origin 检查

**位置**: `rust-core/devnote-websocket/src/lib.rs`

---

## 六、CRDT 与同步

### 6.1 CRDT 无因果稳定性

**位置**: `rust-core/devnote-crdt/src/lib.rs:19-24`

### 6.2 同步服务无操作转换日志 (OTL)

**位置**: `rust-core/devnote-sync/src/lib.rs`

### 6.3 冲突备份文件无规范

**位置**: `rust-core/devnote-crdt/src/lib.rs`

---

## 七、Go 业务层

### 7.1 知识图谱算法无单元测试

**位置**: `business-server/internal/service/knowledge_service.go`

### 7.2 缺少 OpenAPI/Swagger 文档

### 7.3 同步服务与业务服务耦合 JWT secret

---

## 八、Flutter 表现层

### 8.1 BLoC 直连全局 Dispatch（破坏 DI）

### 8.2 错误类型 FlowyResult/FlowyInternalError 来自 AppFlowy 残留

### 8.3 UI 状态与业务状态不分

### 8.4 缺少骨架屏/空态

---

## 九、构建与工程化

### 9.1 缺少 CI/CD

### 9.2 Workspace.dependencies 覆盖不全

### 9.3 无 Cargo feature 标志分层启用

### 9.4 iOS/Android 缺少 cargo build 集成脚本

---

## 十、文档与可发现性

### 10.1 缺少架构图 (C4 Model)

### 10.2 各 Rust crate 缺 README

### 10.3 缺少 ADR (Architecture Decision Records)

---

## 十一、安全细节

### 11.1 Workspace.dependencies pin 缺失

### 11.2 gRPC TLS 缺 CA 验证

---

## 十二、Round 2 独立复审新发现

以下发现来自第二轮独立审查（3 个 agent 并行深度检视），与第一轮**不重复**，对照优秀开源软件新增的问题：

### 12.1 零测试覆盖（工程基线）[P0]

**位置**: 全项目范围

**验证结果**:
- Flutter 仅有 1 个 `test/widget_test.dart`（仅测试渲染，无业务逻辑测试）
- Go sync-server：**0 个 `_test.go` 文件**
- Go business-server：**0 个 `_test.go` 文件**
- Rust crate：有 52 个单元测试（集中在 `devnote-crdt`），但 `devnote-ffi`、`devnote-grpc`、`devnote-websocket`、`devnote-qt`、`devnote-ipfs` 全部**零测试**

**对照**:
- AppFlowy：Rust 端 1,200+ 单元测试，Flutter 端 Widget 测试全覆盖
- Logseq：Clojure spec 测试 + E2E Playwright 测试
- Anytype：Protobuf 契约测试 + Rust 集成测试

**建议**: 最小基线 = 每个 crate 至少 3 个核心函数的单测；每个 Go handler 至少 1 个 happy path 测试。

### 12.2 Dockerfile 非多阶段构建（生产安全风险）[P2]

**位置**: `sync-server/Dockerfile`

**验证**:
```dockerfile
FROM golang:1.22-alpine AS builder    # ✅ 多阶段 builder
# ...
FROM alpine:3.19                      # ✅ 多阶段 runtime
COPY --from=builder /sync-server /app/sync-server
```

**状态**: sync-server Dockerfile 是多阶段的 ✅。**已修正**。business-server Dockerfile 同样为多阶段构建 ✅。

### 12.3 Rate Limit 是单机内存 map，非分布式限流 [P1]

**位置**: `sync-server/internal/middleware/rate_limit.go`

**问题**: `visitors` 是 `map[string]*visitor` 存在进程内存中。多实例部署时（K8s Pod > 1），每个实例独立计数，无法真正限流。

**对照**: Istio/Envoy 用 Redis 或 Nginx limit_req 做分布式限流；GitHub API 用 Redis + 漏桶。

**建议**: 改用 Redis-backed rate limiter（`github.com/go-redis/redis_rate`）或 Go 内嵌 token bucket。

### 12.4 JWT Secret 硬编码在默认值中（安全风险）[P1]

**位置**:
- `sync-server/internal/config/config.go:33`: `getEnv("JWT_SECRET", "devnote-sync-secret-key")`
- `sync-server/docker-compose.yml:13`: `JWT_SECRET=${JWT_SECRET:-devnote-sync-secret-key}`
- `business-server/docker-compose.yml:13`: `JWT_SECRET=${JWT_SECRET:-devnote-business-secret-key}`

**问题**: 开发默认值 `devnote-sync-secret-key` 如果生产环境忘记设环境变量，任何人可用此密钥伪造 JWT。

**对照**: Bitwarden/1Password 的 secret 如果未设置，应用**启动失败**而非使用默认值。

**建议**:
```go
func Load() *Config {
    jwtSecret := os.Getenv("JWT_SECRET")
    if jwtSecret == "" {
        panic("JWT_SECRET environment variable must be set")
    }
    // ...
}
```

### 12.5 Formula 解析器无优先级处理（数学正确性）[P1]

**位置**: `rust-core/devnote-database/src/formula.rs:92-112`

**验证**:
```rust
// 当前的 lexer 将所有运算符作为 Token::Add/Sub/Mul/Div 顺序返回
// 但 evaluator 是简单的左到右解析，没有运算符优先级
// 例如 "1 + 2 * 3" 会被解析为 (1 + 2) * 3 = 9 而非 7
```

**对照**: Notion 的 formula 引擎和 Apple Numbers 的公式解析器都正确处理 `*` 优先级高于 `+`。

**建议**: 用递归下降解析或 Pratt parser：
```rust
fn parse_primary(&mut self) -> Result<Expr, String> {
    let left = self.parse_atom()?;
    // 先处理 * / (高优先级)
    // 再处理 + - (低优先级)
}
```

### 12.6 CRDT merge 非真正幂等 [P2]

**位置**: `rust-core/devnote-crdt/src/lib.rs:260-276`

**验证**: `merge` 通过 `filter(|op| !local_ids.contains(op.id()))` 过滤已存在 ID 的操作。但 `local_ids` 是一个 `HashSet<String>` 构建自当前 `self.operations`。如果同一个操作被删除后又重新插入（tombstone 操作），ID 可能不在集合中，导致重复应用。

**对照**: Yjs 用 `(client_id, clock)` 二元组做精确去重，不依赖操作是否在数组中。

**建议**:
```rust
pub struct AppliedOps {
    applied: HashSet<String>,  // 持久化的已应用操作 ID
}

impl CRDTDocument {
    pub fn has_applied(&self, op_id: &str) -> bool {
        self.applied_ops.contains(op_id)
    }
}
```

### 12.7 两个 Docker Compose 文件重复定义 sync-server [P2]

**位置**:
- `sync-server/docker-compose.yml:1-41` 定义了 `sync-server` + `minio`
- `business-server/docker-compose.yml:1-62` 也定义了 `sync-server` + `minio` + `business-server`

**问题**: 两份 `docker-compose.yml` 各自包含 `sync-server` + `minio` 的完整定义。如果分别 `docker-compose up`，会导致：
1. 端口冲突（两个 minio 都想绑 9000:9000）
2. 数据不共享（两个独立 volume）

**建议**: 合并为一个根级 `docker-compose.yml`：
```yaml
services:
  sync-server: ...
  business-server: ...
  minio: ...
  # 可选：postgres for production
```

### 12.8 Canvas 序列化字段名与 Obsidian 不完全匹配 [P2]

**位置**: `rust-core/devnote-canvas/src/lib.rs:125-141`

**验证**: Rust 端使用 `#[serde(rename = "fromNode")]`、`toNode`、`fromSide` 等，但 Obsidian Canvas 实际格式使用 `fromNode`（小写 n）而非 `fromNode`。部分字段如 `canvasColor`、`zoom`、`x`、`y` 在 `CanvasData` 结构体中缺失。

**对照**: Obsidian Canvas `.canvas` 文件是完整 JSON，包含 `nodes`、`edges`、`canvas` 级别属性（color、zoom）。

**建议**: 补充 CanvasData 的顶层属性：
```rust
pub struct CanvasData {
    pub nodes: Vec<CanvasNode>,
    pub edges: Vec<CanvasEdge>,
    #[serde(rename = "canvasColor")]
    pub canvas_color: Option<String>,
    pub zoom: Option<f64>,
    pub x: Option<f64>,
    pub y: Option<f64>,
}
```

### 12.9 MarkdownParser 缺失大量块类型 [P2]

**位置**: `rust-core/devnote-editor/src/lib.rs:11-25`

**验证**: `BlockType` 仅有 6 种：`Paragraph`, `Heading`, `CodeBlock`, `List`, `Quote`, `Divider`。缺少：
- `Image`（笔记中的图片是核心需求）
- `Callout`（思源笔记/Notion 的 callout）
- `MathBlock`（块级 LaTeX）
- `Table`（虽然解析器有 TableParser，但不在 BlockType 枚举中）
- `Embed`（嵌入视频/文件）
- `TaskListItem`（有 TaskListParser，但无对应 BlockType）

**对照**: Notion 支持 20+ 种 block 类型；Obsidian 通过插件扩展到 30+ 种。

### 12.10 全项目缺少 integration/E2E 测试 [P1]

**位置**: 全项目

**验证**: 仅有 `test/widget_test.dart` 一个 Flutter 测试。无任何：
- FFI 集成测试（Dart 调 Rust 是否真正工作）
- 同步 E2E 测试（client → server → client 闭环）
- 加密集成测试（encrypt → decrypt 一致性）

**对照**:
- AppFlowy 有 `flutter_integration_test/` 目录，模拟真实用户操作
- Notesnook 有 Cypress E2E 测试覆盖加密/同步完整流程

### 12.11 Go 优雅关闭已实现（验证通过）[已确认]

**位置**: `sync-server/cmd/server/main.go:175-208`

**验证**: sync-server 已有完整的 `signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)` + `httpServer.Shutdown(ctx)` 优雅关闭实现。**此问题不存在**。

### 12.12 Cargo.lock + pubspec.lock + go.sum 完整性 [已确认]

**验证**:
- `Cargo.lock`: 存在，所有依赖版本固定 ✅
- `pubspec.lock`: 通过 `flutter pub get` 自动管理 ✅
- `go.sum`: sync-server 和 business-server 均有 ✅
- **结论**: 依赖锁定完整，无浮动版本问题 ✅

### 12.13 跨平台 FFI 构建脚本缺失（已确认 Round 1 结论）[P1]

**位置**: 项目根目录

**验证**: 无任何 `build_rust.sh`、`build_android.sh`、CMake integration for Flutter。

**对照**: AppFlowy 用 `Makefile` + `build_runner.sh` 自动为 iOS/Android/macOS/Linux/Windows 交叉编译。

---

## 十三、按优先级排序的修复建议（合并版）

| 优先级 | 任务 | 工作量 | 影响 | 来源 |
|--------|------|--------|------|------|
| **P0** | 把 `devnote_dispatch` 接到真实业务 handler | 1-2 天 | 修复最严重架构空壳 | R1 |
| **P0** | Dart 启动时初始化 FFIBridge + 切换持久层为 Rust | 3 天 | 修复数据双源真理 | R1 |
| **P0** | EditorService 改为 Rust 持久化 | 1 天 | 修复内容丢失 | R1 |
| **P0** | 建立最小测试基线（每 crate 3 单测，Go 每 handler 1 测试） | 2 天 | 工程基线 | R2 |
| **P0** | 解决 devnote-core ↔ devnote-sync 循环依赖 | 0.5 天 | 修复编译警告 | R1 |
| **P1** | 实现 HLC 替代 wall clock | 1 天 | 修复 CRDT 正确性 | R1 |
| **P1** | 实现本地 sync log 去重 | 1 天 | 修复同步重复应用 | R1 |
| **P1** | 编写 GitHub Actions CI | 1 天 | 工程基线 | R1 |
| **P1** | 修复 formula 解析器运算符优先级 | 0.5 天 | 数学正确性 | R2 |
| **P1** | JWT Secret 未设置时启动失败 | 0.5 天 | 安全 | R2 |
| **P1** | Rate Limit 改为 Redis/token bucket | 1 天 | 分布式限流 | R2 |
| **P1** | FFI + Rust 端集成测试 | 1 天 | 端到端验证 | R2 |
| **P2** | devnote-ffi 错误码改为枚举 | 0.5 天 | 可观测性 | R1 |
| **P2** | 引入 swaggo 生成 OpenAPI | 0.5 天 | API 文档 | R1 |
| **P2** | devnote-grpc 强制证书验证 | 0.5 天 | 安全 | R1 |
| **P2** | 合并两份 docker-compose.yml | 0.5 天 | 运维简化 | R2 |
| **P2** | CanvasData 补全顶层属性 | 0.5 天 | Obsidian 兼容 | R2 |
| **P2** | 跨平台 FFI 构建脚本 | 1 天 | 部署 | R1 |
| **P3** | 知识图谱算法单测 | 1 天 | 正确性保证 | R1 |
| **P3** | C4 架构图 + ADR 文档 | 2 天 | 团队可维护性 | R1 |
| **P3** | 补充 Image/Callout/Math 块类型 | 1 天 | 编辑器功能 | R2 |

---

## 十四、Round 3 独立复审新发现

以下发现来自第三轮独立审查（3 个 agent 并行深度检视），与 Round 1/2 **不重复**：

### 14.1 WASM 插件沙箱无资源限制 [P1]

**位置**: `rust-core/devnote-plugin/src/lib.rs:75-174`

**问题**: WASM sandbox 没有设置 CPU 时间限制、内存上限、执行超时。一个恶意或缺陷插件可以：
- 无限循环占用 CPU
- 分配大量内存导致 OOM
- 访问文件系统（未限制 WASI 权限）

**对照**:
- VS Code 扩展宿主进程有 5 秒激活超时 + 内存限制
- Obsidian 插件在沙箱 Worker 中运行，有 `setTimeout` 上限
- Chrome 扩展的 `content_scripts` 有 CPU 配额

**建议**:
```rust
let mut config = wasmtime::Config::new();
config.max_wasm_stack(2 * 1024 * 1024);       // 2MB 栈上限
config.wasm_memory(16);                         // 16 页 = 1MB 内存上限
config.consume_fuel(true);                      // 启用 fuel 计量
let engine = Engine::new(&config)?;
let mut store = Store::new(&engine, ());
store.add_fuel(1_000_000)?;                     // 100 万 fuel 单位
// 执行后检查 fuel 消耗
```

### 14.2 P2P 无背压/连接池/断线重传 [P1]

**位置**: `rust-core/devnote-p2p/src/lib.rs:300-330`

**问题**: 
- 无连接池：每次发送消息都建立新连接
- 无背压：消息队列可无限增长
- 对端断线后无重传机制，数据可能丢失

**对照**: libp2p 的 `Floodsub/Gossipsub` 自带背压；BitTorrent 协议有 piece 重传。

**建议**: 使用 `tokio::sync::mpsc::channel` 带有界容量 + 重试队列 + ACK 确认机制。

### 14.3 ObjectPool 非线程安全且无上限 [P2]

**位置**: `rust-core/devnote-perf/src/lib.rs:12-40`

**问题**: `ObjectPool<T>` 使用 `Mutex<Vec<Box<T>>>` 但无容量上限，无 LRU 淘汰策略，长时间运行会内存泄漏。

**对照**: Apache Commons Pool 有 `maxTotal`/`maxIdle`/`evictionTimer`。

**建议**: 添加 `max_size` 参数 + `evict_idle()` 定时清理。

### 14.4 FileWatcher 未处理系统溢出 [P2]

**位置**: `rust-core/devnote-workflow/src/lib.rs:318-374`

**问题**: `notify::RecommendedWatcher` 在文件系统事件溢出时（如 `git checkout` 大量文件）会返回 `Error::Io` 或 `EventKind::Any`，当前代码未处理。

**对照**: VS Code 的 `chokidar` 有 `awaitWriteFinish` + `ignored` + `stabilityThreshold`。

**建议**: 添加溢出处理 + 事件去抖（debounce 100ms）+ 忽略 `.git/` 目录。

### 14.5 编辑器无 Undo/Redo [P1]

**位置**: `lib/features/editor/bloc/editor_bloc.dart:105-125`

**问题**: EditorBloc 没有 undo/redo 栈。用户误操作后无法撤销。

**对照**: Notion、Obsidian、AppFlowy 均支持 Ctrl+Z/Ctrl+Y。

**建议**: 添加 `UndoStack<EditorEvent>` + `RedoStack<EditorEvent>`，每次操作前 push 当前状态快照。

### 14.6 SyncBloc 无重试机制 [P1]

**位置**: `lib/features/sync/bloc/sync_bloc.dart:70-80`

**问题**: 同步失败直接抛异常到 UI，无指数退避重试。

**对照**: Joplin 同步有 3 次重试 + 指数退避；Dropbox SDK 有自动重试。

**建议**: 实现 `RetryPolicy { max_retries: 3, base_delay: 1s, max_delay: 30s }`。

### 14.7 Canvas 无虚拟化，大量节点卡顿 [P2]

**位置**: `lib/features/canvas/bloc/canvas_bloc.dart:10-20`

**问题**: CanvasBloc 一次性加载所有节点/边到内存，无虚拟化裁剪。1000+ 节点时 UI 会严重卡顿。

**对照**: Figma 使用 viewport culling + tile-based rendering；Miro 有 LOD (Level of Detail) 缩放。

**建议**: 只渲染 viewport 内的节点 + 预加载边缘 1 层节点。

### 14.8 VirtualScrollController 未集成到实际 Widget [P2]

**位置**: `lib/core/performance/virtual_scroll_controller.dart:1-63`

**问题**: 虚拟滚动控制器实现了偏移计算，但**未集成到任何 ListView/Scrollable Widget**。是孤立代码。

**建议**: 集成到 `NoteList` 和 `SearchResultCard` 列表中。

### 14.9 路由缺少导航守卫 [P2]

**位置**: `lib/core/router/app_router.dart:36-209`

**问题**: 路由定义完整，支持深度链接，但**无导航守卫**。未登录用户可直接访问 `/settings/sync` 等需认证页面。

**对照**: AppFlowy 用 `AuthGuard` 包裹需登录路由；Notion 有 workspace-level 权限检查。

**建议**: 添加 `GoRouter.redirect` 钩子检查认证状态。

### 14.10 无国际化 (i18n) 支持 [P1]

**位置**: `lib/features/settings/settings_page.dart` + `pubspec.yaml`

**问题**: 
- 设置页无语言选择选项
- 所有 UI 文本硬编码中文字符串（如 `'笔记列表'`、`'设置'`）
- pubspec.yaml 虽有 `flutter_localizations` 和 `intl` 依赖，但**未生成 ARB 文件**

**对照**: AppFlowy 支持 40+ 语言；Notion 支持 15 种语言。

**建议**: 
1. 提取所有硬编码字符串到 `lib/l10n/app_zh.arb` / `app_en.arb`
2. 运行 `flutter gen-l10n`
3. 在 SettingsPage 添加语言切换

### 14.11 FFI 无版本协商/向后兼容 [P2]

**位置**: `rust-core/devnote-ffi/src/lib.rs:21-54`

**问题**: `FFIResponse` 没有 `version` 字段。Rust 端升级后如果改变了返回格式，旧版 Flutter 无法感知。

**对照**: AppFlowy 的 FFI 有 `FFIRequest { header: EventHeader, payload: Vec<u8> }` 含版本号；gRPC 用 protobuf 天然向后兼容。

**建议**: 在 `devnote_init` 时交换版本号，不匹配时返回错误。

### 14.12 Go API 无版本控制 [P2]

**位置**: `sync-server/internal/handler/sync.go:18-86`

**问题**: API 路径是 `/api/v1/...`，但没有中间件校验 `Accept-Version` header。客户端升级后可能调到不兼容的 API。

**建议**: 添加 `API-Version` header 校验中间件。

### 14.13 Argon2id 参数不可配置 [P2]

**位置**: `rust-core/devnote-crypto/src/lib.rs:54-87`

**问题**: 默认 `m_cost=19456` (19MB)、`t_cost=3`、`p_cost=1`。在低端移动设备上 19MB 内存 + 3 次迭代可能导致 2-5 秒延迟。

**对照**: Bitwarden 允许用户选择 KDF 迭代次数；1Password 使用 SRP 替代 Argon2 登录。

**建议**: `CryptoConfig` 暴露 `argon2_memory`/`argon2_iterations` 参数，移动端默认降低为 `m_cost=8192, t_cost=2`。

### 14.14 密钥丢失无恢复机制 [P1]

**位置**: `rust-core/devnote-crypto/src/lib.rs:177-181`

**问题**: 如果用户忘记主密码或丢失派生密钥，**所有加密数据永久不可恢复**。没有恢复密钥/助记词机制。

**对照**:
- Bitwarden 提供恢复代码
- 1Password 提供紧急恢复包 (Recovery Kit)
- ProtonMail 提供恢复短语

**建议**: 生成 24 词 BIP-39 助记词作为恢复密钥，加密存储后允许用户离线备份。

### 14.15 Flashcard 复习记录无数据保留策略 [P2]

**位置**: `rust-core/devnote-flashcard/src/lib.rs:290-300`

**问题**: `review_records` 表无限增长，长期使用后可能有数十万条记录。

**建议**: 添加 `purge_old_reviews(before: DateTime)` 方法，默认保留最近 1 年。

### 14.16 Graph 中心性每次重新计算，无缓存 [P2]

**位置**: `rust-core/devnote-graph/src/lib.rs:340-365`

**问题**: `calculate_centrality` 每次调用都全量计算。1000+ 节点的 PageRank 需要 O(V²) 时间。

**对照**: Neo4j 有图算法结果缓存；NetworkX 支持 `cache=True`。

**建议**: 缓存计算结果 + `dirty` 标记（图变更时置脏）。

### 14.17 Dart 端迁移框架为空壳 [P2]

**位置**: `lib/core/persistence/database_helper.dart:95-102`

**问题**: Dart 端的 `migrate` 方法有框架但**无实际迁移逻辑**。如果 Dart 端继续使用 sqflite，schema 变更将导致运行时错误。

### 14.18 同步失败无回滚 [P1]

**位置**: `rust-core/devnote-sync/src/lib.rs:113-134`

**问题**: sync 中途失败（如网络断开），已应用的操作无法回滚，导致本地数据处于不一致状态。

**对照**: Joplin 同步用事务包裹每次 sync 操作；Git 用 atomic commit。

**建议**: 每次 sync 操作包裹在 SQLite 事务中，失败时 rollback。

---

## 十五、按优先级排序的修复建议（三轮合并版）

| 优先级 | 任务 | 工作量 | 影响 | 来源 |
|--------|------|--------|------|------|
| **P0** | 把 `devnote_dispatch` 接到真实业务 handler | 1-2 天 | 修复最严重架构空壳 | R1 |
| **P0** | Dart 启动时初始化 FFIBridge + 切换持久层为 Rust | 3 天 | 修复数据双源真理 | R1 |
| **P0** | EditorService 改为 Rust 持久化 | 1 天 | 修复内容丢失 | R1 |
| **P0** | 建立最小测试基线 | 2 天 | 工程基线 | R2 |
| **P0** | 解决 devnote-core ↔ devnote-sync 循环依赖 | 0.5 天 | 修复编译警告 | R1 |
| **P1** | 实现 HLC 替代 wall clock | 1 天 | 修复 CRDT 正确性 | R1 |
| **P1** | 实现本地 sync log 去重 | 1 天 | 修复同步重复应用 | R1 |
| **P1** | 编写 GitHub Actions CI | 1 天 | 工程基线 | R1 |
| **P1** | 修复 formula 解析器运算符优先级 | 0.5 天 | 数学正确性 | R2 |
| **P1** | JWT Secret 未设置时启动失败 | 0.5 天 | 安全 | R2 |
| **P1** | Rate Limit 改为 Redis/token bucket | 1 天 | 分布式限流 | R2 |
| **P1** | FFI + Rust 端集成测试 | 1 天 | 端到端验证 | R2 |
| **P1** | WASM 插件沙箱加资源限制 | 1 天 | 安全 | R3 |
| **P1** | P2P 加背压/连接池/重传 | 1 天 | 可靠性 | R3 |
| **P1** | 编辑器加 Undo/Redo | 1 天 | 用户体验 | R3 |
| **P1** | SyncBloc 加重试机制 | 0.5 天 | 可靠性 | R3 |
| **P1** | 国际化 (i18n) 支持 | 2 天 | 全球化 | R3 |
| **P1** | 密钥恢复机制 (BIP-39 助记词) | 1 天 | 数据安全 | R3 |
| **P1** | 同步失败加事务回滚 | 0.5 天 | 数据一致性 | R3 |
| **P2** | devnote-ffi 错误码改为枚举 | 0.5 天 | 可观测性 | R1 |
| **P2** | 引入 swaggo 生成 OpenAPI | 0.5 天 | API 文档 | R1 |
| **P2** | devnote-grpc 强制证书验证 | 0.5 天 | 安全 | R1 |
| **P2** | 合并两份 docker-compose.yml | 0.5 天 | 运维简化 | R2 |
| **P2** | CanvasData 补全顶层属性 | 0.5 天 | Obsidian 兼容 | R2 |
| **P2** | 跨平台 FFI 构建脚本 | 1 天 | 部署 | R1 |
| **P2** | ObjectPool 加容量上限 + LRU | 0.5 天 | 内存泄漏 | R3 |
| **P2** | FileWatcher 加溢出处理 + 去抖 | 0.5 天 | 稳定性 | R3 |
| **P2** | Canvas 加 viewport 虚拟化 | 1 天 | 性能 | R3 |
| **P2** | VirtualScroll 集成到实际 Widget | 0.5 天 | 性能 | R3 |
| **P2** | 路由加导航守卫 | 0.5 天 | 安全 | R3 |
| **P2** | FFI 加版本协商 | 0.5 天 | 兼容性 | R3 |
| **P2** | Go API 加版本控制中间件 | 0.5 天 | 兼容性 | R3 |
| **P2** | Argon2id 参数可配置 | 0.5 天 | 移动端性能 | R3 |
| **P2** | Flashcard 加数据保留策略 | 0.5 天 | 存储管理 | R3 |
| **P2** | Graph 中心性结果缓存 | 0.5 天 | 性能 | R3 |
| **P2** | Dart 端迁移框架填充 | 0.5 天 | 数据一致性 | R3 |
| **P3** | 知识图谱算法单测 | 1 天 | 正确性保证 | R1 |
| **P3** | C4 架构图 + ADR 文档 | 2 天 | 团队可维护性 | R1 |
| **P3** | 补充 Image/Callout/Math 块类型 | 1 天 | 编辑器功能 | R2 |

---

## 总结

DevNote 项目的**架构骨架设计优秀**（五层解耦、开源复用、性能优化、CRDT、SRP、IPFS 等），代码量（约 15.4 万行）和模块完整度都令人印象深刻。但经过三轮独立审查，从优秀开源软件的标准看，核心问题如下：

**三轮合并结论**：

1. **架构落地不完整**：`devnote_dispatch` 是空壳，Rust 引擎与 Dart UI 完全脱节（**最严重**）
2. **数据双源真理**：Dart sqflite 与 Rust rusqlite 各自维护，违反 spec 的"本地优先"
3. **零测试覆盖**：Go 服务 0 测试，Flutter 仅 1 个渲染测试，多个 Rust crate 零测试
4. **插件沙箱不安全**：WASM 无 CPU/内存/超时限制，恶意插件可耗尽资源
5. **编辑器缺 Undo/Redo**：用户误操作无法撤销
6. **同步不可靠**：无重试、无回滚、无背压
7. **密钥丢失无恢复**：用户忘记主密码 = 数据永久丢失
8. **公式解析器有数学错误**：无运算符优先级
9. **安全风险**：JWT Secret 硬编码默认值；SRP 与 Bcrypt 并存
10. **工程化缺失**：无 CI/CD、无 E2E 测试、无跨平台构建脚本、无国际化
11. **CRDT 正确性**：wall-clock 排序、merge 非真正幂等

最关键的一步是**先把 devnote_dispatch 真正接到业务 handler**，让 Rust 引擎成为唯一数据源，否则所有优化都建立在一个空壳上。
