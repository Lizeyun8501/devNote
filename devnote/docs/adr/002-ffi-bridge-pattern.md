# ADR 002: FFI Bridge 模式

| 属性 | 值 |
|------|------|
| **标题** | 使用 flutter_rust_bridge v2 实现 Flutter 与 Rust 核心的类型安全通信 |
| **状态** | Accepted（已迁移完成） |
| **日期** | 2025-01-20（初稿）/ 2026-06-23（迁移完成） |
| **决策者** | DevNote 核心架构团队 |

## 上下文

DevNote 采用 Flutter（Dart）作为 UI 框架，Rust 作为核心引擎。两者需要高效的跨语言通信机制。

### 通信需求

1. **低延迟**：编辑器 keystroke 到渲染需 < 16ms（60fps），FFI 调用开销需控制在 1ms 以内。
2. **大数据传输**：笔记内容（可能数万字符）、搜索结果列表、图谱节点/边数据需要高效传递。
3. **类型安全**：跨语言调用需要保证数据结构的一致性，避免序列化/反序列化错误。
4. **异步支持**：同步、搜索、加密等耗时操作需在后台执行，不阻塞 UI 线程。

### 架构演进历史

| 阶段 | 方案 | 时间 | 状态 |
|------|------|------|------|
| 初稿 | Dart FFI + C ABI（手写 Event-Dispatch） | 2025-01-20 | 已废弃 |
| 当前 | flutter_rust_bridge v2（类型安全绑定） | 2026-06-23 | 现行 |

### 备选方案

| 方案 | 优势 | 劣势 |
|------|------|------|
| **flutter_rust_bridge v2** | 类型安全、自动内存管理、异步原生支持、SSE 编解码器 | 需要 codegen 步骤 |
| Dart FFI + C ABI | 零拷贝可能、延迟 < 0.1ms、无外部进程 | 仅同步调用、手写 malloc/free、JSON 序列化 |
| Platform Channel | Flutter 内置、使用简单 | JSON 序列化开销大、延迟 1-5ms |
| gRPC (本地进程) | 类型安全 (Protobuf)、流式支持 | 额外进程开销、序列化/反序列化延迟 0.5-2ms |

## 决策

选择 **flutter_rust_bridge v2**（FRB v2）作为 Flutter 与 Rust 核心的主要通信方式。

### 架构设计

```
Flutter (Dart)          FRB Codegen          Rust Core
┌─────────────┐    ┌──────────────────┐    ┌──────────────────┐
│  FFIBridge  │───>│  SSE 编解码器    │───>│  frb_api.rs     │
│  (调用层)    │    │  (类型安全)      │    │  (pub fn)        │
│             │<───│  (自动序列化)     │<───│  (引擎)          │
└─────────────┘    └──────────────────┘    └──────────────────┘
```

### 核心变更（v2 迁移）

| 废弃项 | 替代项 |
|--------|--------|
| `dart:ffi` DynamicLibrary/lookupFunction | FRB 生成的 `RustLib.instance.api.*` |
| 手写 C ABI `extern "C"` 函数 | FRB 自动生成的 FFI 绑定 |
| `FFIResponseC` 结构体 | FRB 自动映射的 Dart 类型 |
| Event-Dispatch 字符串路由 | 直接函数调用 |
| JSON 序列化/反序列化 | SSE 编解码器 |
| `ffi_response.dart` | 删除（不再需要） |
| `handlers.rs` Event-Dispatch | 删除（不再需要） |
| `build.rs` cbindgen | 删除（不再需要） |

### 文件变更摘要

**新增文件：**
- `flutter_rust_bridge.yaml` — FRB codegen 配置
- `lib/src/rust/frb_generated.dart` — FRB 运行时入口
- `lib/src/rust/frb_generated.io.dart` — IO 平台实现
- `lib/src/rust/frb_generated.web.dart` — Web 平台实现
- `lib/src/rust/library.dart` — FRB 生成的 API 函数和数据类型
- `scripts/codegen.sh` — FRB codegen 脚本

**删除文件：**
- `rust-core/devnote-ffi/src/handlers.rs` — Event-Dispatch 模式
- `rust-core/devnote-ffi/src/build.rs` — cbindgen 构建脚本
- `rust-core/devnote-ffi/devnote_ffi.h` — 生成的 C 头文件
- `lib/core/bridge/ffi_response.dart` — FFIResponseC 结构体

**重写文件：**
- `lib/core/bridge/ffi_bridge.dart` — 使用 FRB 绑定替代 dart:ffi
- `lib/core/bridge/mixins/*.dart` — 直接调用 FRB 函数
- `lib/features/editor/services/math_ink_service.dart` — 使用 FRB 替代 dart:ffi
- `rust-core/tests/integration_test.rs` — 测试 FRB API 替代 C ABI dispatch

### 关键约定

1. **代码生成**：首次设置或新增 Rust 函数后，运行 `flutter_rust_bridge_codegen generate`。
2. **生成的 API**：所有 Rust 端 `pub fn` 会自动映射为 Dart 函数，无需手写绑定。
3. **初始化流程**：`RustLib.instance.init()` → `initEngines(dbPath)`。
4. **数据类型映射**：Rust `struct` → Dart `class`，自动序列化/反序列化。

## 后果

### 正面

- **类型安全**：FRB 自动生成 Dart ↔ Rust 类型映射，消除手写 JSON 编解码错误。
- **内存安全**：FRB 自动管理跨语言内存分配/释放，无需手写 `malloc`/`free`。
- **性能**：SSE 编解码器比 JSON 序列化快数倍。
- **异步原生支持**：FRB 原生支持 `Future`，无需手写回调或轮询。
- **开发效率**：新增 Rust 函数只需 `flutter_rust_bridge_codegen generate`，无需手写 `extern "C"` 包装。

### 负面

- **codegen 步骤**：首次设置或新增 Rust 函数时需要运行代码生成。
- **学习曲线**：需要了解 FRB 的 API 约束（如不支持某些 Rust 类型）。

### 风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| codegen 步骤被遗忘 | 创建 `scripts/codegen.sh` 脚本，文档化生成命令 |
| 生成的代码被意外修改 | FRB 生成文件添加 "DO NOT EDIT MANUALLY" 注释 |
| FRB 不支持某些 Rust 类型 | 参考 FRB 文档，避免使用不支持的类型 |

## 附录：迁移清单

- [x] Rust: 删除 `handlers.rs`（Event-Dispatch 模式）
- [x] Rust: 删除 `build.rs`（cbindgen）
- [x] Rust: 删除 `devnote_ffi.h`（C 头文件）
- [x] Rust: 保留 `frb_api.rs`（FRB API 入口）
- [x] Dart: 删除 `ffi_response.dart`
- [x] Dart: 重写 `ffi_bridge.dart` 使用 FRB 绑定
- [x] Dart: 更新 mixins 使用 FRB 函数
- [x] Dart: 创建 FRB 生成文件存根
- [x] 构建: 创建 `scripts/codegen.sh`
- [x] 构建: 更新 `scripts/build_rust.sh`
- [x] 测试: 更新 Rust 集成测试
- [x] 文档: 更新本 ADR
