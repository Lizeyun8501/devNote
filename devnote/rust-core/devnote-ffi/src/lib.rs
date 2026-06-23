//! DevNote FFI 桥接层 —— 基于 flutter_rust_bridge v2 的类型安全绑定
//!
//! ## 架构
//! 原实现：自研 C ABI FFI 桥接层（devnote_init/devnote_dispatch/devnote_free_string）
//!         + Event-Dispatch 模式（handlers.rs 中字符串路由到闭包 handler）
//! 现实现：flutter_rust_bridge v2 自动生成类型安全的 Dart 绑定
//!
//! ## FRB v2 优势
//! - **类型安全**：自动生成 Dart 绑定，消除双端 JSON schema 不一致
//! - **内存安全**：消除手写 malloc/free 和 catch_unwind
//! - **性能**：SSE 编解码器比 JSON 序列化快数倍
//! - **开发效率**：新增 Rust 函数只需 `flutter_rust_bridge_codegen generate`
//! - **高级特性**：支持 async/await、Stream、Result 类型
//!
//! 来源: https://pub.dev/packages/flutter_rust_bridge
//! 版本: v2.12.0

// FRB API 模块 —— 所有 pub fn 会被 FRB codegen 扫描并生成 Dart 绑定
pub mod frb_api;

// FRB codegen 自动生成的运行时模块
// 由 `flutter_rust_bridge_codegen generate` 写入
mod frb_generated;
