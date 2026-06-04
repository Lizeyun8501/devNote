# ADR 002: FFI Bridge 模式

| 属性 | 值 |
|------|------|
| **标题** | 使用 Dart FFI + C ABI 桥接 Flutter 与 Rust 核心 |
| **状态** | Accepted |
| **日期** | 2025-01-20 |
| **决策者** | DevNote 核心架构团队 |

## 上下文

DevNote 采用 Flutter（Dart）作为 UI 框架，Rust 作为核心引擎。两者需要高效的跨语言通信机制。

### 通信需求

1. **低延迟**：编辑器 keystroke 到渲染需 < 16ms（60fps），FFI 调用开销需控制在 1ms 以内。
2. **大数据传输**：笔记内容（可能数万字符）、搜索结果列表、图谱节点/边数据需要高效传递。
3. **类型安全**：跨语言调用需要保证数据结构的一致性，避免序列化/反序列化错误。
4. **异步支持**：同步、搜索、加密等耗时操作需在后台执行，不阻塞 UI 线程。

### 备选方案

| 方案 | 优势 | 劣势 |
|------|------|------|
| **Dart FFI + C ABI** | 零拷贝可能、延迟 < 0.1ms、无外部进程、直接内存访问 | 仅支持同步调用（需手动管理异步）、跨平台构建复杂 |
| Platform Channel | Flutter 内置、使用简单 | JSON 序列化开销大、延迟 1-5ms、仅支持 Flutter ↔ 原生 |
| gRPC (本地进程) | 类型安全 (Protobuf)、流式支持、跨进程 | 额外进程开销、序列化/反序列化延迟 0.5-2ms |
| WebSocket (本地) | 双向流式、协议成熟 | 文本/二进制序列化开销、延迟 1-10ms、需要本地端口 |
| TCP/UDP Socket | 灵活、可跨进程 | 无类型安全、需要自定义协议、端口管理复杂 |

## 决策

选择 **Dart FFI + C ABI** 作为 Flutter 与 Rust 核心的主要通信方式。

### 架构设计

```
Flutter (Dart)          FFI Bridge              Rust Core
┌─────────────┐    ┌──────────────────┐    ┌──────────────────┐
│  Dispatch   │───>│  ffi_bridge.dart │───>│  devnote-ffi     │
│  (request)  │    │  (JSON encode)   │    │  (extern "C")    │
│             │<───│  ffi_response.dart│<───│  handle_dispatch │
│  (response) │    │  (JSON decode)   │    │  FFIResponse*    │
└─────────────┘    └──────────────────┘    └──────────────────┘
```

### 接口定义

```c
// Rust 端 (extern "C")
FFIResponse* devnote_init();
FFIResponse* devnote_dispatch(const char* event, const char* payload);
void         devnote_free_response(FFIResponse* response);

// Dart 端
final _init = ffi_bridge.lookupFunction<
    Pointer<FFIResponse> Function(),
    Pointer<FFIResponse> Function()
>('devnote_init');
```

### 数据结构

```rust
#[repr(C)]
pub struct FFIResponse {
    pub code: i32,           // 0 = 成功, < 0 = 错误码
    pub message: *mut c_char, // 错误信息
    pub data: *mut c_char,    // JSON 响应数据
}
```

### 关键约定

1. **内存管理**：Rust 端通过 `Box::into_raw` 分配，Dart 端负责调用 `devnote_free_response` 释放。
2. **错误处理**：所有 FFI 函数使用 `std::panic::catch_unwind` 包裹，panic 转换为错误码返回。
3. **异步操作**：耗时操作在 Rust 端使用 `tokio::spawn` 异步执行，通过回调或轮询返回结果。
4. **版本协商**：`devnote_init` 时交换版本号，不兼容时返回错误。

## 后果

### 正面

- **极低延迟**：FFI 调用延迟 < 0.1ms，远低于 Platform Channel（1-5ms）和 gRPC（0.5-2ms）。
- **无额外进程**：Rust 核心以动态链接库形式加载到 Flutter 进程内，无需进程间通信。
- **跨平台一致**：同一份 C ABI 接口在桌面和移动端表现一致。
- **内存可控**：可直接传递大块数据（如笔记内容），避免多次序列化。

### 负面

- **异步支持复杂**：Dart FFI 原生仅支持同步调用，耗时操作需要手动实现异步模式（回调或 Future 轮询）。
- **内存管理责任**：Dart 端必须正确调用 `free_response`，否则会导致内存泄漏。
- **跨平台构建复杂**：需要为每个目标平台（macOS-arm64/x86_64、Linux、Windows、iOS、Android）单独编译 `.dylib`/`.so`/`.dll`。
- **调试困难**：跨语言调试需要同时使用 Dart DevTools 和 Rust GDB/LLDB，问题定位成本高。
- **panic 风险**：Rust panic 跨越 FFI 边界 = UB，必须严格使用 `catch_unwind` 保护。

### 已识别风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| 内存泄漏 | Dart 端使用 `using` 模式确保 `free_response` 被调用；定期内存泄漏检测 |
| panic 跨越 FFI | 所有 FFI 入口函数包裹 `catch_unwind`，panic 转换为 `code: -99` |
| 构建复杂 | 编写自动化构建脚本（`build_rust.sh`），CI 中自动为所有目标平台编译 |
| 版本不兼容 | `devnote_init` 时交换版本号，不匹配返回错误码 |
