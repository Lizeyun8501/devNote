# DevNote - 先进云笔记应用

## 项目简介

DevNote 是一款面向开发者和技术用户的新一代云笔记应用，融合了块编辑器、知识图谱、闪卡复习、数据库视图、插件系统等先进功能。项目采用 Rust + Flutter + Go 三端架构，通过 FFI 桥接实现高性能核心与跨平台 UI 的深度集成，致力于打造本地优先、端到端加密、多设备同步的专业级知识管理工具。

## 架构设计

DevNote 采用五层架构设计，自底向上依次为：

```
┌─────────────────────────────────────────────────────┐
│                   表现层 (UI Layer)                   │
│         Flutter Widgets / Pages / Themes             │
├─────────────────────────────────────────────────────┤
│                  状态管理层 (BLoC Layer)               │
│         BLoC / Event / State / Provider              │
├─────────────────────────────────────────────────────┤
│                  服务层 (Service Layer)                │
│       Feature Services / Repository Pattern          │
├─────────────────────────────────────────────────────┤
│                  桥接层 (FFI Bridge Layer)             │
│        FFI Dispatch / Request / Response             │
├─────────────────────────────────────────────────────┤
│                  核心层 (Rust Core Layer)              │
│  Editor / CRDT / Crypto / Search / Sync / Graph     │
└─────────────────────────────────────────────────────┘
```

- **核心层**：纯 Rust 实现，包含编辑器、CRDT 协同、加密、搜索、同步、图谱等核心逻辑，通过 FFI 导出 C 接口
- **桥接层**：Dart FFI 绑定，封装 Rust 核心层的 C 接口为 Dart 异步调用
- **服务层**：Flutter 端业务逻辑，采用 Repository 模式管理数据持久化
- **状态管理层**：基于 BLoC 模式的响应式状态管理
- **表现层**：Material Design 3 风格的 Flutter UI 组件

## 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| UI 框架 | Flutter 3.x + Dart 3.x | 跨平台 UI，支持 Android/iOS/macOS/Windows/Linux/Web |
| 状态管理 | flutter_bloc + Provider | BLoC 模式响应式状态管理 |
| 路由 | go_router | 声明式路由，支持深链接 |
| 数据持久化 | Rust rusqlite (权威源) + sqflite (兜底) | SQLite 本地存储 + 不可变数据模型 |
| 核心引擎 | Rust (Edition 2021) | 高性能核心逻辑 |
| 加密 | XChaCha20-Poly1305 + Argon2id | 端到端加密 |
| 协同 | CRDT (RGA) | 无冲突复制数据类型，支持离线编辑 |
| 搜索 | tantivy (主引擎) + SQLite FTS5 (兼容) | 全文搜索引擎 |
| 同步服务 | Go + Gin | 云端同步服务器 |
| 云存储 | S3 兼容 | 对象存储后端 |
| FFI 桥接 | flutter_rust_bridge v2.12.0 | Rust 与 Dart 的跨语言调用 |

## 项目结构

```
devnote/
├── lib/                          # Flutter 应用源码
│   ├── main.dart                 # 应用入口
│   ├── core/                     # 核心基础设施
│   │   ├── bridge/               # FFI 桥接层
│   │   │   ├── ffi_bridge.dart   # FFI 绑定
│   │   │   ├── dispatch.dart     # 事件分发
│   │   │   ├── ffi_request.dart  # 请求封装
│   │   │   └── ffi_response.dart # 响应解析
│   │   ├── constants/            # 常量定义
│   │   ├── persistence/          # 数据持久化
│   │   │   ├── models/           # 数据模型 (freezed)
│   │   │   ├── database_helper.dart
│   │   │   ├── note_repository.dart
│   │   │   ├── folder_repository.dart
│   │   │   └── tag_repository.dart
│   │   ├── router/               # 路由配置
│   │   ├── theme/                # 主题系统
│   │   └── performance/          # 性能优化
│   │       ├── startup_manager.dart
│   │       ├── cache_manager.dart
│   │       ├── memory_manager.dart
│   │       ├── virtual_scroll_controller.dart
│   │       └── lazy_loader.dart
│   ├── features/                 # 功能模块
│   │   ├── editor/               # 块编辑器
│   │   ├── notes/                # 笔记管理
│   │   ├── search/               # 全局搜索
│   │   ├── sync/                 # 多端同步
│   │   ├── canvas/               # 无限画布
│   │   ├── database/             # 数据库视图
│   │   ├── knowledge_graph/      # 知识图谱
│   │   ├── knowledge/            # 知识管理
│   │   ├── flashcard/            # 闪卡复习
│   │   ├── object/               # 对象系统
│   │   ├── plugins/              # 插件系统
│   │   ├── workflow/             # 工作流/Git
│   │   └── settings/             # 设置
│   └── l10n/                     # 国际化
├── rust-core/                    # Rust 核心引擎
│   ├── devnote-core/             # 核心模型与 trait
│   ├── devnote-ffi/              # FFI 导出层
│   ├── devnote-editor/           # 块编辑器引擎
│   ├── devnote-crdt/             # CRDT 协同算法
│   ├── devnote-crypto/           # 加密引擎
│   ├── devnote-search/           # 全文搜索引擎
│   ├── devnote-sync/             # 同步引擎
│   ├── devnote-persistence/      # 持久化层
│   ├── devnote-p2p/              # P2P 通信
│   ├── devnote-plugin/           # 插件运行时
│   ├── devnote-graph/            # 图谱引擎
│   ├── devnote-database/         # 数据库引擎
│   ├── devnote-object/           # 对象系统
│   ├── devnote-flashcard/        # 闪卡引擎
│   ├── devnote-perf/             # 性能优化
│   ├── devnote-observe/          # 可观测性
│   └── devnote-extensions/       # 扩展功能 (OCR/ASR 等)
├── sync-server/                  # Go 同步服务器
│   ├── cmd/server/               # 服务入口
│   ├── internal/
│   │   ├── config/               # 配置管理
│   │   ├── handler/              # HTTP 处理器
│   │   ├── middleware/           # 中间件 (CORS/JWT/限流)
│   │   ├── model/                # 数据模型
│   │   ├── service/              # 业务逻辑
│   │   └── storage/              # 存储适配器 (SQLite/S3)
│   ├── Dockerfile
│   └── docker-compose.yml
├── android/                      # Android 平台
├── ios/                          # iOS 平台
├── linux/                        # Linux 平台
├── macos/                        # macOS 平台
├── windows/                      # Windows 平台
├── web/                          # Web 平台
└── test/                         # 测试
```

## 核心功能模块列表

| 模块 | 功能说明 | 状态 |
|------|----------|------|
| 块编辑器 | 支持 Markdown、代码块、LaTeX、表格、任务列表的块级编辑器 | MVP |
| 笔记管理 | 文件夹树、标签系统、双向链接 | MVP |
| 全局搜索 | FTS5 全文搜索、高级过滤、关键词高亮 | MVP |
| 多端同步 | CRDT 协同、冲突解决、增量同步 | MVP |
| 端到端加密 | XChaCha20-Poly1305 加密、Argon2id 密钥派生 | MVP |
| 无限画布 | 节点与边的可视化画布 | MVP |
| 数据库视图 | 表格/看板/日历视图、筛选排序、公式计算 | MVP |
| 知识图谱 | 节点关系可视化、图谱过滤 | MVP |
| 知识管理 | 学习仪表盘、知识地图、学习统计与报告 | MVP |
| 闪卡复习 | 间隔重复、复习统计、卡片管理 | MVP |
| 对象系统 | 自定义对象类型、对象关系图谱 | MVP |
| 插件系统 | 插件市场、权限管理、插件设置 | MVP |
| 工作流 | Git 版本管理、文件监听、提交历史 | MVP |
| 云存储适配 | WebDAV / S3 / Dropbox / OneDrive | MVP |
| P2P 同步 | 设备发现、直连同步 | MVP |
| 导入导出 | 数据备份与恢复 | MVP |
| 性能优化 | 启动管理、缓存策略、内存管理、虚拟滚动 | MVP |

## 开发环境配置

### 前置要求

- **Flutter**: >= 3.7.2 (Dart >= 3.7.2)
- **Rust**: >= 1.96.0 (Edition 2021)
- **Go**: >= 1.21
- **Android Studio / Xcode**: 用于移动端调试

### 安装步骤

1. **克隆仓库**
   ```bash
   git clone <repo-url>
   cd devnote
   ```

2. **安装 Flutter 依赖**
   ```bash
   flutter pub get
   ```

3. **编译 Rust 核心**
   ```bash
   cd rust-core
   cargo build --release
   cd ..
   ```

4. **生成 Dart 代码**（freezed / json_serializable）
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

5. **启动同步服务器**（可选）
   ```bash
   cd sync-server
   go run cmd/server/main.go
   ```

## 编译运行指南

### 桌面端 (macOS / Windows / Linux)

```bash
flutter run -d macos    # macOS
flutter run -d windows  # Windows
flutter run -d linux    # Linux
```

### 移动端 (Android / iOS)

```bash
flutter run -d android  # Android
flutter run -d ios      # iOS (需要 Xcode)
```

### Web 端

```bash
flutter run -d chrome
```

### 运行测试

```bash
# Rust 测试
cd rust-core
cargo test --workspace

# Flutter 分析
dart analyze lib/

# Flutter 测试
flutter test
```

### 构建 Release

```bash
flutter build apk       # Android APK
flutter build ios       # iOS
flutter build macos     # macOS
flutter build web       # Web
```

## 开发路线图

### v0.1.0 - MVP (当前)
- [x] 五层架构搭建
- [x] Rust 核心引擎 (17 个 crate)
- [x] Flutter 功能模块 (16 个 feature)
- [x] Go 同步服务器
- [x] FFI 桥接层
- [x] 块编辑器 (Markdown/LaTeX/代码/表格/任务列表)
- [x] CRDT 协同算法
- [x] 端到端加密
- [x] 全文搜索
- [x] 多端同步框架
- [x] 知识图谱
- [x] 闪卡复习
- [x] 插件系统框架

### v0.2.0 - 稳定版
- [ ] 完善所有模块的端到端集成测试
- [ ] 优化 CRDT 合并性能
- [ ] 实现离线优先同步策略
- [ ] 完善插件 API 与沙箱隔离
- [ ] 添加更多云存储适配器

### v0.3.0 - 协作版
- [ ] 实时协同编辑
- [ ] WebSocket 推送
- [ ] 用户权限管理
- [ ] 团队空间

### v0.4.0 - 生态版
- [ ] 插件市场上线
- [ ] 主题商店
- [ ] 模板系统
- [ ] API 开放平台

### v1.0.0 - 正式版
- [ ] 全平台稳定性验证
- [ ] 性能基准测试达标
- [ ] 安全审计通过
- [ ] 完整文档与教程

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md) before getting started.

## Community

- [Report a Bug](https://github.com/Lizeyun8501/devNote/issues)
- [Request a Feature](https://github.com/Lizeyun8501/devNote/issues)
- [Discussions](https://github.com/Lizeyun8501/devNote/discussions)
