# Architecture Decision Records (ADRs)

本目录包含 DevNote 项目的架构决策记录。每个 ADR 记录了一个重要的架构决策、其背景和后果。

## ADR 列表

| 编号 | 标题 | 状态 | 日期 |
|------|------|------|------|
| [001](001-use-rust-for-core.md) | 使用 Rust 作为核心引擎 | Accepted | 2025-01-15 |
| [002](002-ffi-bridge-pattern.md) | 使用 flutter_rust_bridge v2 实现 Flutter 与 Rust 核心的类型安全通信 | Accepted | 2025-01-20 / 2026-06-23 |
| [003](003-five-layer-architecture.md) | 五层解耦架构设计 | Accepted | 2025-02-01 |
| [004](004-sqlite-for-persistence.md) | SQLite 作为主要持久化层 | Accepted | 2025-02-10 |
| [005](005-crdt-for-sync.md) | CRDT + HLC 用于无冲突同步 | Accepted | 2025-02-20 |
| [006](006-bloc-state-management.md) | BLoC 模式用于 Flutter 状态管理 | Accepted | 2025-03-01 |
| [007](007-wasm-plugin-system.md) | WebAssembly 插件沙箱（运行时从 Wasmtime 迁移至 extism） | Superseded | 2025-03-10 / 2026-06-19 |

## ADR 格式

每个 ADR 遵循标准格式：

- **标题**：简洁描述决策内容
- **状态**：Proposed（提议中）| Accepted（已采纳）| Deprecated（已废弃）| Superseded（已被替代）
- **上下文**：问题背景、约束条件、备选方案
- **决策**：最终选择及详细设计
- **后果**：正面影响、负面影响、已识别风险与缓解措施

## 相关文件

- [C4 架构模型](../c4-architecture.md) — DevNote 的系统架构可视化
- [架构审查报告](../architecture-review.md) — 十二轮独立架构审查结果
