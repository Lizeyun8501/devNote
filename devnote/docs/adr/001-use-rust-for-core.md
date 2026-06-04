# ADR 001: 选择 Rust 作为核心引擎

| 属性 | 值 |
|------|------|
| **标题** | 使用 Rust 实现 DevNote 核心引擎 |
| **状态** | Accepted |
| **日期** | 2025-01-15 |
| **决策者** | DevNote 核心架构团队 |

## 上下文

DevNote 需要一套高性能、跨平台的核心引擎来处理以下需求：

1. **高性能数据处理**：笔记编辑、CRDT 合并、全文搜索、图谱计算等操作需要在毫秒级响应，尤其是大文档（10 万+ blocks）场景下。
2. **内存安全**：作为本地优先应用，核心引擎直接操作本地文件系统与 SQLite 数据库，内存安全问题可能导致数据损坏。
3. **跨平台编译**：需要为桌面（macOS/Linux/Windows）、移动端（iOS/Android）编译为原生动态链接库。
4. **插件扩展**：需要支持 WebAssembly 插件沙箱，允许第三方开发者在不危及宿主安全的前提下扩展功能。
5. **并发处理**：同步引擎需要处理多端并发变更的合并，要求高性能的并发原语。

### 备选方案

| 方案 | 优势 | 劣势 |
|------|------|------|
| **Rust** | 零成本抽象、内存安全、WASM 一等公民、跨平台工具链成熟 | 学习曲线陡峭、编译时间长 |
| C++ | 性能极致、生态丰富 | 无内存安全保证、跨平台构建复杂、依赖管理困难 |
| Go | 开发效率高、内置并发 | 无泛型（早期版本）、GC 延迟影响实时性、不支持 WASM 沙箱 |
| Zig | 简洁、无运行时 | 生态尚不成熟、WASM 支持有限 |

## 决策

选择 **Rust** 作为 DevNote 核心引擎的实现语言，构建为 19 个独立 Crate 组成的 Workspace：

- `devnote-core` — 领域模型
- `devnote-ffi` — FFI 接口
- `devnote-persistence` — SQLite 持久化
- `devnote-crypto` — 加密模块
- `devnote-sync` — 同步引擎
- `devnote-crdt` — CRDT 引擎
- `devnote-editor` — Markdown 编辑器
- `devnote-search` — 全文搜索
- `devnote-graph` — 知识图谱
- `devnote-plugin` — WASM 插件沙箱
- `devnote-p2p` — P2P 通信
- `devnote-canvas` — 画布模块
- `devnote-flashcard` — 闪卡系统
- `devnote-workflow` — 工作流
- `devnote-grpc` — gRPC 服务
- `devnote-websocket` — WebSocket 服务
- `devnote-events` — 事件系统
- `devnote-observe` — 可观测性
- `devnote-perf` — 性能工具

### 关键依赖

- `rusqlite` — SQLite 绑定
- `wasmer` / `wasmtime` — WASM 运行时
- `libp2p` — P2P 网络
- `tonic` — gRPC 框架
- `tracing` — 结构化日志
- `serde` — 序列化

## 后果

### 正面

- **内存安全**：编译期所有权系统消除空指针解引用、数据竞争、缓冲区溢出等常见安全问题。
- **性能卓越**：零成本抽象、无 GC 暂停，CRDT 合并和全文搜索性能优于 GC 语言 3-5 倍。
- **WASM 一等公民**：Rust → WASM 工具链成熟，插件沙箱可通过 Wasmtime 实现 CPU/内存/超时限制。
- **跨平台**：`cargo build --target` 支持所有目标平台，配合 `cbindgen` 自动生成 C 头文件。
- **并发安全**：`Send`/`Sync` trait 保证线程安全，`tokio` 异步运行时支持高并发 I/O。

### 负面

- **学习曲线陡峭**：Rust 的所有权、生命周期、借用检查对团队是新挑战，需要 1-2 个月适应期。
- **编译时间长**：全量编译 19 个 crate 约 3-5 分钟，增量编译约 30-60 秒，影响开发迭代速度。
- **FFI 边界风险**：`unsafe` 代码（`from_raw`、`as_ptr`）需要严格审查，panic 跨越 FFI 边界会导致 UB，必须使用 `catch_unwind` 包裹。
- **生态局限**：某些领域（如富文本编辑器渲染）缺乏成熟的 Rust 库，可能需要自行实现或集成 C 库。

### 已识别风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| FFI 不安全 | 所有 `unsafe` 函数使用 `std::panic::catch_unwind` 包裹；使用 `NonNull<T>` 替代裸指针 |
| 编译时间长 | CI 使用 `sccache` 缓存；开发中使用 `cargo check` 代替 `cargo build` |
| 团队技能不足 | 建立 Rust 编码规范、代码审查清单、内部分享机制 |
