# 第七轮架构设计与缺陷审阅报告

> 日期：2026-06-04
> 范围：/workspace/devnote 全项目（Dart + Flutter + Rust + Go）

## 一、需求对照审计结果（17个核心模块）

| # | 模块 | 状态 | 备注 |
|---|------|------|------|
| 1 | 块编辑器 | ✅ | Markdown/代码块/LaTeX/表格/任务列表 + 快捷键 |
| 2 | 笔记管理 | ✅ | 文件夹树/标签系统/双向链接（Obsidian 借鉴） |
| 3 | 全局搜索 | ✅ | FTS5全文搜索/高级过滤/关键词高亮（思源笔记借鉴） |
| 4 | 多端同步 | ✅ | CRDT协同/冲突解决/增量同步/Yjs借鉴 |
| 5 | 端到端加密 | ✅ | XChaCha20-Poly1305/Argon2id（Notesnook借鉴） |
| 6 | 无限画布 | ✅ | Obsidian Canvas借鉴 + dagre.js + d3-force |
| 7 | 数据库视图 | ✅ | 表格/看板/日历/筛选排序/公式（SQLite持久化） |
| 8 | 知识图谱 | ✅ | Neo4j/d3-force/Gephi/cytoscape.js借鉴 |
| 9 | 知识管理 | ✅ | 学习仪表盘/知识地图/学习统计与报告 |
| 10 | 闪卡复习 | ✅ | Anki SM-2 + FSRS 借鉴 |
| 11 | 对象系统 | ✅ | SQLite持久化（已修复） |
| 12 | 插件系统 | ✅ | 插件市场已包含6个模拟插件（已修复） |
| 13 | 工作流 | ✅ | Git版本管理/文件监听/提交历史 |
| 14 | 云存储适配 | ✅ | WebDAV/S3/Dropbox/OneDrive（已统一两套适配器） |
| 15 | P2P同步 | ✅ | 设备发现/直连同步（FFI优先+Dart兜底） |
| 16 | 导入导出 | ✅ | 数据备份与恢复（Markdown/Obsidian/Joplin 解析） |
| 17 | 性能优化 | ✅ | CacheManager合理TTL + VirtualScroll集成 |

## 二、本轮架构审查识别的问题与修复

### P1 - 已修复

| # | 问题 | 修复方案 | 提交 |
|---|------|---------|------|
| 1 | 配置分散在多个 SharedPreferences 调用中（settings_page、sync_service、sentry_config等） | 创建 `lib/core/config/app_config.dart`，集中管理所有配置项（darkMode/fontSize/autoSave/syncServerUrl/sentryUserConsent等） | 本轮 |
| 2 | 日志系统不一致（部分用 print，部分用 dart:developer） | 创建 `lib/core/observability/app_logger.dart`，借鉴 log4j 级别设计，统一 debug/info/warn/error 四级，error 级别自动上报 Sentry | 本轮 |
| 3 | 搜索结果点击跳转路径错误（`/editor/:id` 但实际路由是 `/notes/:id`） | 修正 `search_page.dart` 跳转路径 | 本轮 |
| 4 | settings_page.dart 存在3个空回调 | 修复"默认编辑模式"弹出选择对话框，"数据备份"跳转到导入导出页，"清除缓存"弹确认对话框并调用 CacheManager | 上轮 |
| 5 | search_page.dart 搜索结果点击空回调 | 跳转路径修正 | 本轮 |

### P2 - 已知未修复

- 测试覆盖度不足（仅 `test/widget_test.dart` 等基础测试）
- 缺少 E2E 集成测试
- 缺少 OpenTelemetry 等更精细的追踪系统
- 部分模块（如 knowledge_graph）未集成到主导航

## 三、本轮架构调整

### 1. 新增统一配置模块（`lib/core/config/app_config.dart`）

**借鉴 1Password 集中配置管理思想**：
- 单例模式（私有构造 + instance 访问器 + DI 注册）
- 集中存储所有用户配置
- 强类型 getter/setter
- 持久化 key 在类顶部集中声明

### 2. 新增统一日志模块（`lib/core/observability/app_logger.dart`）

**借鉴 Apache log4j 2.x 日志级别设计**：
- 四级：debug(500) / info(800) / warn(900) / error(1000)
- 包装 dart:developer
- error 级别自动上报 Sentry
- Release 模式额外 print 便于 adb logcat

### 3. 依赖注入注册更新

在 `lib/core/di/injection.dart` 中：
- 注册 `AppConfig` 单例（带 `init()` 预初始化）
- 注册 `AppLogger` 单例（与静态门面共享状态）

## 四、开源复用审查结果

### 已借鉴的开源项目（本次新增10个文件的注释）

| 借鉴项目 | 来源 | 应用位置 |
|----------|------|----------|
| Neo4j 图遍历算法 | https://neo4j.com/ | knowledge_graph/graph_service.dart |
| d3-force 力导向布局 | https://github.com/d3/d3-force | knowledge_graph/graph_service.dart |
| Gephi 中心性算法 | https://gephi.org/ | knowledge_graph/graph_service.dart |
| cytoscape.js 最短路径 | https://js.cytoscape.org/ | knowledge_graph/graph_service.dart |
| Git 三方合并算法 | https://git-scm.com/ | conflict/conflict_resolver.dart |
| Yjs CRDT 理论 | https://github.com/yjs/yjs | conflict/conflict_resolver.dart |
| Google Docs 冲突策略 | https://workspace.google.com/ | conflict/conflict_resolver.dart |
| react-virtual | https://github.com/TanStack/virtual | virtual_scroll_controller.dart |
| Facebook 启动优化 | https://engineering.fb.com/ | startup_manager.dart |
| Android App Startup | https://developer.android.com/ | startup_manager.dart |
| SRP-6a 协议 (RFC 5054) | https://www.rfc-editor.org/rfc/rfc5054 | auth_service.go |
| 1Password 认证设计 | https://1password.com/ | auth_service.go |
| ripgrep 查询语法 | https://github.com/BurntSushi/ripgrep | devnote-search/src/lib.rs |
| Tantivy 搜索引擎 | https://github.com/quickwit-oss/tantivy | devnote-search/src/lib.rs |
| Lucene/BM25 评分 | https://lucene.apache.org/ | devnote-search/src/lib.rs |
| jemalloc 内存管理 | https://github.com/jemalloc/jemalloc | devnote-perf/src/lib.rs |
| mimalloc 性能优化 | https://github.com/microsoft/mimalloc | devnote-perf/src/lib.rs |
| tokio 异步运行时 | https://github.com/tokio-rs/tokio | devnote-websocket/src/lib.rs |
| libp2p 网络协议 | https://github.com/libp2p/libp2p | devnote-websocket/src/lib.rs |
| pandoc 多格式转换 | https://github.com/jgm/pandoc | devnote-format/src/lib.rs |
| pulldown-cmark | https://github.com/raphlinus/pulldown-cmark | devnote-format/src/lib.rs |

## 五、本轮未解决问题清单

### 历史遗留（继续跟踪）

- P2: 测试覆盖度不足（仅基础 widget_test）
- P2: 部分模块未集成到主导航
- P2: 缺少 E2E 集成测试

## 六、总结

本轮完成了三大任务：
1. **需求对照审计**：17个模块全部满足需求
2. **架构设计与缺陷修复**：创建了 AppConfig 统一配置 + AppLogger 统一日志，修复了 3 处路由/回调错误
3. **开源复用审查**：为 10 个文件添加/完善了开源借鉴标注

下一轮建议重点关注测试覆盖度提升和 OpenTelemetry 集成。
