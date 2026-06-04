# 第八轮架构设计与缺陷审阅报告

> 日期：2026-06-04
> 范围：/workspace/devnote 全项目（Dart + Flutter + Rust + Go）

## 一、缺陷审计结果

### P0 - 严重缺陷（已全部修复）

| # | 缺陷 | 位置 | 修复方案 | 状态 |
|---|------|------|---------|------|
| D-1 | SyncBloc冲突状态处理创建空ConflictResolver | sync_bloc.dart:74-81, 177-184 | 改用 `_syncService.conflictResolver.conflicts` 获取实际冲突数据 | ✅ |
| D-2 | _listenToServiceState 未订阅状态流 | sync_bloc.dart:56-58 | 使用 `_syncService.stateStream.listen()` 建立实际订阅 | ✅ |

### P1 - 重要缺陷（已全部修复）

| # | 缺陷 | 位置 | 修复方案 | 状态 |
|---|------|------|---------|------|
| D-3 | database_helper迁移缺少事务保护 | database_helper.dart:239-367 | 改为 `batch.execute()` + `batch.commit(noResult: true)` 确保原子性 | ✅ |
| D-4 | _onPullChanges未处理pullResult | sync_bloc.dart:201 | 添加对 `serviceState.status` 的判断和同步完成日志 | ✅ |
| D-5 | startup_manager缺少耗时记录 | startup_manager.dart:86-98 | 添加 Stopwatch 计时，记录每个任务耗时 | ✅ |

### P2 - 轻微缺陷（已标注）

| # | 缺陷 | 位置 | 建议 | 状态 |
|---|------|------|------|------|
| D-6 | compressImage 未验证编码结果 | memory_manager.dart:87-122 | 已有长度比较逻辑 | ✅ |
| D-7 | CacheManager TTL 默认值 | cache_manager.dart:30-34 | 已按类型设置合理默认TTL | ✅ |

## 二、开源模块替换建议

### 已标注的开源替代方案

| 当前实现 | 推荐的开源替代 | 优势 | 迁移优先级 |
|----------|---------------|------|-----------|
| 自研 FFI 绑定 | [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge) | 自动生成绑定，减少手写错误 | 中 |
| 自研知识图谱渲染 | [graphview](https://pub.dev/packages/graphview) | 成熟图可视化，内置 Sugiyama 布局 | 中 |
| 自研缓存管理 | [flutter_cache_manager](https://pub.dev/packages/flutter_cache_manager) | 成熟的文件缓存，内置 SQLite | 低 |
| 自研 CRDT 实现 | [automerge](https://crates.io/crates/automerge) | 成熟 CRDT，性能经过验证 | 高 |
| 自研 WASM 插件沙箱 | [extism](https://crates.io/crates/extism) | 多语言插件支持，内置 API | 中 |

### 已添加开源注释的文件

| 文件 | 添加内容 |
|------|---------|
| lib/core/bridge/ffi_bridge.dart | flutter_rust_bridge 替代方案注释 |
| lib/features/knowledge_graph/graph_service.dart | graphview/force_graph 替代方案注释 |
| lib/core/performance/cache_manager.dart | flutter_cache_manager 替代方案注释 |
| rust-core/devnote-crdt/src/lib.rs | automerge 替代方案注释 |
| rust-core/devnote-plugin/src/lib.rs | extism 替代方案注释 |

## 三、本轮架构调整

### 1. SyncService 增强

- 新增 `conflictResolver` 属性，供 SyncBloc 获取实际冲突数据
- 新增 `stateStream` 广播流，支持外部订阅同步状态变化
- 激活 `_notifyListeners()` 方法，状态变更时自动通知

### 2. SyncBloc 缺陷修复

- 冲突状态处理改为使用 SyncService 的实际冲突数据
- 添加状态流订阅，实时响应同步状态变化
- 拉取结果增加状态判断和日志记录

### 3. DatabaseHelper 事务保护

- _onUpgrade 改为 batch 执行，利用 sqflite 事务机制确保迁移原子性
- 迁移失败时自动回滚，防止数据库处于不一致状态

### 4. StartupManager 耗时记录

- 添加 Stopwatch 计时，记录每个启动任务的耗时
- 输出结构化日志，便于性能分析和优化

## 四、历史审计问题状态

| 轮次 | 总缺陷 | 已修复 | 未修复 |
|------|--------|--------|--------|
| Round 1+2 | 14 | 14 | 0 |
| Round 3 | 8 | 8 | 0 |
| Round 4 | 5 | 5 | 0 |
| Round 5 | 5 | 5 | 0 |
| Round 6 | 7 | 7 | 0 |
| Round 7 | 5 | 5 | 0 |
| Round 8 | 5 | 5 | 0 |
| **累计** | **49** | **49** | **0** |

## 五、总结

本轮完成了：
1. **架构缺陷审计**：发现 2 个 P0 + 3 个 P1 缺陷，全部修复
2. **开源模块审查**：识别 5 个可替代的开源模块，已添加注释标注
3. **同步服务增强**：SyncService 新增冲突解析器暴露和状态流订阅

下一轮建议重点关注：
- 测试覆盖率提升
- flutter_rust_bridge 迁移评估
- automerge CRDT 迁移评估
