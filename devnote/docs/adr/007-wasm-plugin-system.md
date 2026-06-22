# ADR 007: WebAssembly 插件沙箱

| 属性 | 值 |
|------|------|
| **标题** | 使用 WebAssembly（WASM）实现插件沙箱系统 |
| **状态** | Superseded（运行时从 Wasmtime 迁移至 extism，见下方"变更记录"） |
| **日期** | 2025-03-10 |
| **决策者** | DevNote 核心架构团队 |

## 上下文

DevNote 需要支持第三方插件扩展功能（如自定义导出格式、笔记分析工具、主题引擎），同时保证：

1. **安全性**：插件不能访问宿主文件系统、网络、或用户敏感数据（除非显式授权）。
2. **资源隔离**：插件的 CPU、内存使用需有限制，不能影响宿主应用稳定性。
3. **跨平台**：插件在桌面和移动端运行一致。
4. **语言无关**：开发者可以使用 Rust、C、C++、AssemblyScript 等编译到 WASM 的语言编写插件。

### 备选方案

| 方案 | 优势 | 劣势 |
|------|------|------|
| **WebAssembly (Wasmtime)** | 沙箱安全、资源限制、跨平台、多语言支持、成熟运行时 | 生态相对年轻、WASI 标准仍在演进 |
| **Lua 脚本** | 轻量、嵌入简单、Obsidian/Neovim 验证 | 语言单一、无原生沙箱（需自行实现）、性能一般 |
| **JavaScript (QuickJS)** | JS 生态丰富、开发者熟悉 | 沙箱实现复杂、GC 开销、QuickJS 生态小 |
| **Python (MicroPython)** | 开发者友好、生态庞大 | 运行时大、沙箱困难、移动端支持有限 |
| **原生插件 (dylib/so)** | 性能最高、无限制 | 无安全沙箱、平台特定、崩溃可导致宿主崩溃 |
| **gRPC 外部进程** | 完全隔离、崩溃不影响宿主 | 进程启动开销大、IPC 延迟高、部署复杂 |

## 决策

选择 **WebAssembly（通过 Wasmtime 运行时）** 作为 DevNote 的插件沙箱方案。

### 架构设计

```
┌────────────────────────────────────────────────────────┐
│                 DevNote Core (Rust)                    │
│                                                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │            WASM Plugin Sandbox                   │  │
│  │                                                  │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐      │  │
│  │  │ Plugin A │  │ Plugin B │  │ Plugin C │      │  │
│  │  │ (WASM)   │  │ (WASM)   │  │ (WASM)   │      │  │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘      │  │
│  │       │             │             │              │  │
│  │  ┌────▼─────────────▼─────────────▼────┐        │  │
│  │  │         WASI Host Functions         │        │  │
│  │  │  - note.read / note.write           │        │  │
│  │  │  - editor.insert_block              │        │  │
│  │  │  - crypto.hash / crypto.random      │        │  │
│  │  │  - fs.read (沙箱路径限定)           │        │  │
│  │  │  - timer.now                        │        │  │
│  │  └─────────────────────────────────────┘        │  │
│  │                                                  │  │
│  │  Resource Limits:                               │  │
│  │  - max_wasm_stack: 2MB                          │  │
│  │  - max_memory: 16 pages (1MB)                   │  │
│  │  - fuel_limit: 1,000,000 units                  │  │
│  │  - execution_timeout: 5s                        │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘
```

### WASI 接口定义

```rust
// 插件可访问的宿主 API
pub trait PluginHost {
    // 笔记操作（沙箱化，仅允许访问授权的笔记）
    fn note_read(&self, note_id: &str) -> Result<String>;
    fn note_write(&self, note_id: &str, content: &str) -> Result<()>;

    // 编辑器操作
    fn editor_insert_block(&self, block: &BlockModel) -> Result<()>;

    // 加密操作
    fn crypto_hash(&self, data: &[u8]) -> Result<Vec<u8>>;
    fn crypto_random_bytes(&self, len: usize) -> Result<Vec<u8>>;

    // 受限文件系统访问（仅沙箱目录）
    fn fs_read(&self, path: &str) -> Result<Vec<u8>>;
    fn fs_write(&self, path: &str, data: &[u8]) -> Result<()>;

    // 时间
    fn timer_now(&self) -> Result<u64>;
}
```

### 资源限制配置

```rust
let mut config = wasmtime::Config::new();
config.max_wasm_stack(2 * 1024 * 1024);       // 2MB 栈上限
config.consume_fuel(true);                     // 启用 fuel 计量
let engine = Engine::new(&config)?;

let mut store = Store::new(&engine, PluginContext::new());
store.set_fuel(1_000_000)?;                    // 100 万 fuel 单位

// 内存限制：16 页 = 1MB
let memory_type = MemoryType::new(1, Some(16));
```

### 插件生命周期

```
1. 加载：下载/读取 .wasm 文件 → 验证签名 → 编译为 Module
2. 实例化：创建 Instance + Store（含资源限制）+ 注入 Host Functions
3. 初始化：调用插件的 `init()` 入口函数
4. 执行：按需调用插件导出的函数
5. 卸载：释放 Instance 和 Store，回收资源
```

### 安全模型

| 安全层 | 机制 |
|--------|------|
| **沙箱隔离** | WASM 无直接系统调用，所有操作必须通过 Host Function |
| **资源限制** | Fuel 计量 + 内存上限 + 栈深度限制 + 执行超时 |
| **权限控制** | 插件声明所需权限，用户授权后注入对应 Host Function |
| **签名验证** | 插件 .wasm 文件需包含开发者签名，加载时验证 |
| **网络隔离** | 默认禁止网络访问，需显式授权并限定域名白名单 |

## 后果

### 正面

- **强安全沙箱**：WASM 无法直接访问宿主系统，所有操作必须通过显式授权的 Host Function。
- **资源可控**：通过 fuel 计量、内存上限、栈深度限制、超时机制防止恶意插件耗尽资源。
- **跨平台一致**：WASM 字节码在桌面和移动端运行结果一致。
- **多语言支持**：开发者可以使用 Rust、C、C++、AssemblyScript、Go（TinyGo）等语言编写插件。
- **崩溃隔离**：插件崩溃（trap）不会导致宿主应用崩溃，Wasmtime 安全捕获所有异常。

### 负面

- **性能开销**：WASM 执行比原生代码慢 10-30%，对于计算密集型插件可感知。
- **生态限制**：WASI 标准仍在演进，部分 POSIX API 不可用（如 socket、fork）。
- **开发门槛**：插件开发者需要了解 WASM 编译链和 WASI 接口。
- **包体积**：Wasmtime 运行时增加约 5-10MB 的包体积。
- **文件系统访问受限**：WASI 的 `preopen` 目录机制需要精心设计沙箱路径。

### 已识别风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| 插件无限循环耗尽 CPU | Fuel 计量限制，超过上限自动终止 |
| 插件内存泄漏 | 内存上限（16 pages = 1MB），超限自动终止 |
| 插件逃逸沙箱 | WASM 无法直接系统调用；所有 Host Function 参数严格验证 |
| 恶意插件获取敏感数据 | 权限控制模型，仅注入授权后的 Host Function |
| WASI 标准不兼容 | 使用 Wasmtime 稳定 API 版本；定期更新运行时 |

## 变更记录

### Superseded — 运行时从 Wasmtime 迁移至 extism

**状态变更日期**：2026-06-19
**新方案**：[extism](https://extism.org/)（通用 WASM 插件框架，底层仍基于 WASM 沙箱）

本 ADR 记录的"直接使用 Wasmtime 运行时 + 手写 WASI Host Functions"方案已被 `extism` 取代。代码实际状态如下：

- `rust-core/devnote-plugin/Cargo.toml` 依赖 `extism = { version = "1" }`（workspace 依赖），不再直接依赖 `wasmtime`。
- `rust-core/Cargo.toml` workspace 依赖中声明 `extism = { version = "1" }`，注释明确标注"从自研 wasmtime 沙箱 → extism 通用插件框架"。

**迁移原因**：

1. **降低开发门槛**：extism 内置多语言插件开发支持（Rust/Go/Python/JS 等 16+ 语言），插件开发者无需直接对接 WASI 底层 API。
2. **内置插件 API**：extism 提供 HTTP 请求、日志、缓存等开箱即用的 Host Function，减少手写 `PluginHost` trait 的工作量。
3. **沙箱安全不变**：extism 底层仍基于 WASM 沙箱，本 ADR"安全模型"中的沙箱隔离、资源限制、权限控制等设计原则继续生效。
4. **维护成本**：Wasmtime API 随版本演进较快，直接依赖需持续跟进；extism 封装了运行时细节，降低维护负担。

**保留的设计**：本 ADR 的"安全模型"（沙箱隔离、资源限制、权限控制、签名验证、网络隔离）和"插件生命周期"设计仍然有效，extism 在这些方面提供等价或更完善的能力。仅"资源限制配置"中的 Wasmtime 特定 API（`Config::max_wasm_stack`、`Store::set_fuel` 等）不再适用，改用 extism 的 manifest 配置。

本 ADR 的"决策"中关于"通过 Wasmtime 运行时"的部分仅作为历史记录保留，当前运行时为 extism。
