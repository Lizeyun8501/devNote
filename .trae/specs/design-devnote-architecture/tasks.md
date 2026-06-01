# Tasks

## 阶段一：基础框架与核心能力搭建

- [ ] Task 1: 搭建 Flutter+Qt 混合表示层基础框架
  - [ ] SubTask 1.1: 拉取 AppFlowy Flutter 基础工程，配置桌面端和移动端编译打包环境
  - [ ] SubTask 1.2: 复用 AppFlowy 基础 UI 组件库，搭建应用主框架、导航栏、菜单栏、基础列表、目录结构
  - [ ] SubTask 1.3: 实现多端基础自适应布局，配置 Qt 框架集成用于桌面端高级编辑界面
  - [ ] SubTask 1.4: 实现 Platform Channel 原生能力适配（状态栏通知、生物识别、文件访问等）

- [ ] Task 2: 搭建桥接层通信基础设施
  - [ ] SubTask 2.1: 搭建 Rust 核心引擎脚手架工程
  - [ ] SubTask 2.2: 编写 Dart FFI / C ABI 通信适配代码，复用 AppFlowy 的 FFI 绑定代码和消息序列化/反序列化逻辑
  - [ ] SubTask 2.3: 完成 Flutter 与 Rust 之间的通信联调，实现标准数据报文序列化/反序列化
  - [ ] SubTask 2.4: 配置 gRPC/WebSocket 通信适配用于移动端/远程场景

- [ ] Task 3: 搭建本地持久化层基础架构
  - [ ] SubTask 3.1: 集成 SQLite 数据库，复用思源笔记表结构设计逻辑，创建基础存储数据表
  - [ ] SubTask 3.2: 复用 Joplin 文件系统适配代码，搭建本地文件存储基础架构
  - [ ] SubTask 3.3: 实现笔记元数据、内容、附件与本地文件之间的关联读写
  - [ ] SubTask 3.4: 移植 sqlx Rust 库作为 SQLite 底层驱动，移植 fslock 实现跨平台文件锁

- [ ] Task 4: 实现基础块编辑引擎
  - [ ] SubTask 4.1: 移植复用思源笔记的块编辑引擎核心逻辑和 Markdown 解析器
  - [ ] SubTask 4.2: 移植 pulldown-cmark Rust 库作为 Markdown 解析底层后端
  - [ ] SubTask 4.3: 在桌面端和移动端同时实现基础块编辑和 Markdown 渲染
  - [ ] SubTask 4.4: 实现笔记列表展示和目录树状结构展示功能，完成本地编辑闭环

## 阶段二：完善本地笔记管理与核心业务能力

- [ ] Task 5: 扩展高级编辑能力
  - [ ] SubTask 5.1: 实现代码块插入编辑，支持多种代码主题实时切换、行号显示、自动换行
  - [ ] SubTask 5.2: 实现 LaTeX 公式、流程图、时序图渲染
  - [ ] SubTask 5.3: 实现任务列表、表格的插入和编辑
  - [ ] SubTask 5.4: 实现代码片段收藏功能

- [ ] Task 6: 实现笔记管理与知识关联基础能力
  - [ ] SubTask 6.1: 复用思源笔记存储层代码，实现多级目录管理和标签管理
  - [ ] SubTask 6.2: 实现双向链接和关系索引计算
  - [ ] SubTask 6.3: 实现知识图谱基本渲染
  - [ ] SubTask 6.4: 实现实时本地备份，复用 Joplin 文件系统适配代码实现增量写入和数据校验

- [ ] Task 7: 实现全文检索引擎
  - [ ] SubTask 7.1: 复用思源笔记全文检索引擎代码，实现基于 SQLite 的全文索引
  - [ ] SubTask 7.2: 移植 tantivy Rust 全文检索库，提升大规模笔记检索性能
  - [ ] SubTask 7.3: 实现关键词高亮、检索历史、多条件组合筛选
  - [ ] SubTask 7.4: 复用 AppFlowy UI 组件库搭建检索结果页面，适配不同端交互习惯

- [ ] Task 8: 实现格式导入导出引擎
  - [ ] SubTask 8.1: 复用 Joplin 格式导入导出代码，实现主流笔记工具批量导入
  - [ ] SubTask 8.2: 实现 Markdown、PDF、HTML 多格式批量导出
  - [ ] SubTask 8.3: 移植 libmagic 文件识别库，实现导入时文件类型校验和格式兼容处理

- [ ] Task 9: 实现本地加密存储
  - [ ] SubTask 9.1: 复用 Notesnook 加密引擎代码（XChaCha20-Poly1305、Argon2），实现本地数据加密存储
  - [ ] SubTask 9.2: 移植 rustcrypto 加密算法库作为底层依赖
  - [ ] SubTask 9.3: 复用 AppFlowy 设置页面 UI 组件，提供加密配置选项（密钥设置、算法等级选择）

## 阶段三：实现云同步与安全能力闭环

- [ ] Task 10: 搭建自建同步服务
  - [ ] SubTask 10.1: 搭建基于 Go 语言的自建同步服务，复用 Joplin 同步服务端代码
  - [ ] SubTask 10.2: 实现多存储后端适配、同步请求路由、流量分发、并发控制、同步日志管理
  - [ ] SubTask 10.3: 适配云原生架构，编写 Dockerfile 完成容器化部署
  - [ ] SubTask 10.4: 移植 minio-go 库对接 S3 兼容存储，移植 syncthing 逻辑作为流量控制后端

- [ ] Task 11: 实现客户端同步引擎
  - [ ] SubTask 11.1: 复用 Joplin 同步引擎适配代码，实现增量同步和断点续传
  - [ ] SubTask 11.2: 移植 rdiff 增量传输库优化同步流量
  - [ ] SubTask 11.3: 实现同步状态展示、网络异常自动重连、多设备通信激活

- [ ] Task 12: 实现 CRDT 冲突解决
  - [ ] SubTask 12.1: 复用 AppFlowy CRDT 冲突解决算法逻辑，融合进同步引擎
  - [ ] SubTask 12.2: 实现多设备并发编辑时自动冲突合并
  - [ ] SubTask 12.3: 复用思源笔记历史版本代码，冲突内容保存为历史版本并生成冲突备份文件

- [ ] Task 13: 实现端到端加密同步
  - [ ] SubTask 13.1: 复用 Notesnook 端到端加密引擎代码，适配到同步层
  - [ ] SubTask 13.2: 实现同步数据加密传输和解密处理，服务端安全存储密文
  - [ ] SubTask 13.3: 复用 Joplin 云存储适配代码，对接 S3、WebDAV、Dropbox、OneDrive 存储后端

- [ ] Task 14: 实现 P2P 同步通道
  - [ ] SubTask 14.1: 复用 Anytype 加密 P2P 传输逻辑
  - [ ] SubTask 14.2: 复用 libp2p-rs 或 webrtc-rs 实现设备发现、连接建立、加密传输通道
  - [ ] SubTask 14.3: 中央服务器仅用于信令交换和公钥分发

- [ ] Task 15: 多端同步联调与优化
  - [ ] SubTask 15.1: 完成多端同步整体联调，验证各种网络环境和并发编辑场景
  - [ ] SubTask 15.2: 优化同步引擎冲突合并效率
  - [ ] SubTask 15.3: 添加同步状态异常通知和同步流量监控功能

## 阶段四：优化知识关联能力、适配技术开发场景

- [ ] Task 16: 完善知识图谱引擎
  - [ ] SubTask 16.1: 复用思源笔记知识图谱引擎代码，完善关系计算逻辑
  - [ ] SubTask 16.2: 实现知识图谱可视化交互（节点拖拽、缩放、筛选、关系高亮展示）

- [ ] Task 17: 实现间隔重复闪卡功能
  - [ ] SubTask 17.1: 集成开源 Anki 风格间隔重复算法
  - [ ] SubTask 17.2: 实现多种闪卡类型（基础问答、填空、cloze）
  - [ ] SubTask 17.3: 实现从笔记中批量生成闪卡
  - [ ] SubTask 17.4: 实现复习进度统计和记忆曲线展示

- [ ] Task 18: 实现开发工作流集成
  - [ ] SubTask 18.1: 实现笔记库 Git 版本管理
  - [ ] SubTask 18.2: 实现外部编辑器（VS Code）实时同步
  - [ ] SubTask 18.3: 实现项目文档自动同步和 GitHub 集成

- [ ] Task 19: 实现插件系统基础框架
  - [ ] SubTask 19.1: 基于 WebAssembly 实现插件沙箱运行时隔离
  - [ ] SubTask 19.2: 设计并实现统一插件 API 抽象层（编辑、存储、同步、UI、网络、Canvas、数据库视图、对象类型、编辑器装饰）
  - [ ] SubTask 19.3: 实现插件动态加载、卸载、懒加载机制
  - [ ] SubTask 19.4: 实现插件版本管理和兼容性处理
  - [ ] SubTask 19.5: 实现插件权限控制系统
  - [ ] SubTask 19.6: 实现插件数据隔离和操作日志记录
  - [ ] SubTask 19.7: 搭建官方插件市场网站，支持安装、更新、评分、评论、签名验证

- [ ] Task 20: 实现 Canvas 渲染引擎和基础交互
  - [ ] SubTask 20.1: 定义 Canvas 数据模型（JSON 格式：nodes 和 edges），复用 Obsidian Canvas 数据结构
  - [ ] SubTask 20.2: 实现画布节点添加、移动、连线、保存/加载功能
  - [ ] SubTask 20.3: 桌面端集成 Qt QGraphicsView 框架实现高性能画布
  - [ ] SubTask 20.4: 移动端基于 Flutter CustomPaint/InteractiveViewer 构建画布

- [ ] Task 21: 实现关系数据库引擎
  - [ ] SubTask 21.1: 复用 AppFlowy appflowy-database 核心代码（Rust 实现）
  - [ ] SubTask 21.2: 实现表格视图，支持创建数据库、列类型、行操作
  - [ ] SubTask 21.3: 实现看板视图和日历视图
  - [ ] SubTask 21.4: 实现公式解析器（借鉴 Notion 公式或自行实现简单 DSL）
  - [ ] SubTask 21.5: 实现数据库与块级内容双向绑定

- [ ] Task 22: 实现对象化数据模型引擎
  - [ ] SubTask 22.1: 复用 Anytype 对象模型类型定义和关系存储逻辑，适配 Rust 实现
  - [ ] SubTask 22.2: 实现对象的创建、序列化、反序列化、关系解析和版本追踪
  - [ ] SubTask 22.3: 将对象化模型与块存储打通，允许将任何块提升为独立对象
  - [ ] SubTask 22.4: 可选移植 IPFS 块存储接口（rust-ipfs 或 ipfs-embed）

- [ ] Task 23: 实现知识管理增强功能
  - [ ] SubTask 23.1: 实现知识体系梳理工具（图谱筛选搜索、进度跟踪、标签化管理）
  - [ ] SubTask 23.2: 实现学习数据统计与分析（笔记统计、知识盲区发现、学习报告生成）
  - [ ] SubTask 23.3: 实现画布知识连接（Canvas Knowledge Mapping），支持多人实时协作画布（基于 CRDT）
  - [ ] SubTask 23.4: 实现对象化关系浏览（Object Graph），节点-边形式展示对象关系
  - [ ] SubTask 23.5: 实现数据库视图仪表盘（Database Dashboard），多数据库聚合、嵌入式图表、统计卡片

- [ ] Task 24: 全流程性能优化
  - [ ] SubTask 24.1: 启动速度优化（懒加载模块、预编译缓存、数据库连接池），目标 1 秒以内
  - [ ] SubTask 24.2: 大文档编辑优化（虚拟滚动、增量解析、分块存储），支持百万字级别
  - [ ] SubTask 24.3: 内存占用优化（内存池、图片压缩和懒加载、GC 优化）
  - [ ] SubTask 24.4: 同步性能优化（增量同步、断点续传、并发同步）
  - [ ] SubTask 24.5: Canvas 性能优化（离屏渲染、瓦片缓存、增量布局计算、节点懒加载）
  - [ ] SubTask 24.6: 对象化模型性能优化（邻接表存储、批量事务异步写入）

- [ ] Task 25: 全平台测试与适配
  - [ ] SubTask 25.1: Windows 平台功能验证与适配
  - [ ] SubTask 25.2: macOS 平台功能验证与适配
  - [ ] SubTask 25.3: Linux 平台功能验证与适配
  - [ ] SubTask 25.4: Android 平台功能验证与适配
  - [ ] SubTask 25.5: iOS 平台功能验证与适配
  - [ ] SubTask 25.6: 发布 MVP 版本

# Task Dependencies
- [Task 2] depends on [Task 1] (桥接层需要表示层框架就绪)
- [Task 3] depends on [Task 2] (持久化层需要桥接层通信就绪)
- [Task 4] depends on [Task 3] (块编辑引擎需要持久化层存储就绪)
- [Task 5] depends on [Task 4] (高级编辑需要基础编辑引擎就绪)
- [Task 6] depends on [Task 4] (知识关联需要编辑引擎就绪)
- [Task 7] depends on [Task 3] (检索引擎需要持久化层就绪)
- [Task 8] depends on [Task 4] (格式解析需要编辑引擎就绪)
- [Task 9] depends on [Task 3] (加密存储需要持久化层就绪)
- [Task 10] depends on [Task 9] (同步服务需要加密引擎就绪)
- [Task 11] depends on [Task 10] (客户端同步需要服务端就绪)
- [Task 12] depends on [Task 11] (冲突解决需要同步引擎就绪)
- [Task 13] depends on [Task 9] (加密同步需要加密引擎就绪)
- [Task 14] depends on [Task 10] (P2P 同步需要同步服务就绪)
- [Task 15] depends on [Task 12, Task 13, Task 14] (联调需要所有同步组件就绪)
- [Task 16] depends on [Task 6] (知识图谱完善需要基础知识关联就绪)
- [Task 17] depends on [Task 4] (闪卡需要编辑引擎就绪)
- [Task 18] depends on [Task 3] (工作流集成需要持久化层就绪)
- [Task 19] depends on [Task 2] (插件系统需要桥接层通信就绪)
- [Task 20] depends on [Task 1] (Canvas 需要表示层就绪)
- [Task 21] depends on [Task 3] (关系数据库需要持久化层就绪)
- [Task 22] depends on [Task 3, Task 4] (对象化模型需要持久化层和编辑引擎就绪)
- [Task 23] depends on [Task 16, Task 20, Task 21, Task 22] (增强功能需要多个引擎就绪)
- [Task 24] depends on [Task 15, Task 23] (性能优化需要所有功能就绪)
- [Task 25] depends on [Task 24] (测试需要性能优化完成)

# Parallelizable Work
- Task 5, Task 6, Task 7, Task 8, Task 9 可并行（均依赖阶段一完成，相互独立）
- Task 10, Task 14 可并行（同步服务和 P2P 通道独立）
- Task 16, Task 17, Task 18, Task 19, Task 20, Task 21, Task 22 可并行（阶段四各引擎独立开发）
