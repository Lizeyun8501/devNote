# ADR 006: BLoC 模式用于 Flutter 状态管理

| 属性 | 值 |
|------|------|
| **标题** | 使用 BLoC（Business Logic Component）模式管理 Flutter 应用状态 |
| **状态** | Accepted |
| **日期** | 2025-03-01 |
| **决策者** | DevNote 前端架构团队 |

## 上下文

DevNote 的 Flutter 应用需要管理复杂的状态，包括：

1. **UI 状态**：列表加载、编辑光标位置、对话框开关、导航状态。
2. **业务状态**：笔记列表、文件夹树、标签集合、同步状态。
3. **异步状态**：FFI 调用结果、网络请求、文件 I/O。
4. **跨组件共享状态**：当前选中笔记、用户设置、主题配置。

### 备选方案

| 方案 | 优势 | 劣势 |
|------|------|------|
| **BLoC** | 单向数据流、测试友好、与 FFI 异步调用天然适配、生态成熟 | 样板代码多、学习曲线较陡 |
| Provider | 简单、Flutter 官方推荐、学习成本低 | 复杂状态管理混乱、无标准化事件流 |
| Riverpod | 类型安全、编译期检查、依赖注入 | 相对年轻、社区较小、与 BLoC 概念重叠 |
| GetX | 全功能（路由/状态/依赖注入）、简洁 | 反 Flutter 最佳实践、隐式依赖、难以测试 |
| MobX | 响应式、自动追踪依赖 | 需要代码生成、调试困难 |

## 决策

选择 **BLoC 模式**（通过 `flutter_bloc` 包）作为 DevNote 的 Flutter 状态管理方案。

### 架构设计

```
┌──────────────────────────────────────────────────────┐
│                    Presentation                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
│  │  Notes   │  │  Editor  │  │  Settings│  ...      │
│  │  Page    │  │  Page    │  │  Page    │           │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘           │
│       │             │             │                   │
│  ┌────▼─────┐  ┌────▼─────┐  ┌────▼─────┐           │
│  │ NotesBloc│  │EditorBloc│  │Settings  │           │
│  │          │  │          │  │Bloc      │           │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘           │
└───────┼─────────────┼─────────────┼──────────────────┘
        │             │             │
   ┌────▼─────────────▼─────────────▼────┐
   │           Service Layer             │
   │  ┌──────────┐  ┌──────────┐        │
   │  │ Dispatch │  │ FFIBridge│        │
   │  │ (FFI)    │  │          │        │
   │  └──────────┘  └──────────┘        │
   └─────────────────────────────────────┘
```

### BLoC 事件-状态模型

```dart
// 事件
sealed class NotesEvent {}
class NotesLoadRequested extends NotesEvent {}
class NoteSelected extends NotesEvent { final String noteId; }
class NoteCreated extends NotesEvent { final String title; }
class NoteDeleted extends NotesEvent { final String noteId; }
class NoteUpdated extends NotesEvent { final String noteId; final String content; }

// 状态
sealed class NotesState {}
final class NotesInitial extends NotesState {}
final class NotesLoading extends NotesState {}
final class NotesLoaded extends NotesState {
  final List<NoteModel> notes;
  final String? selectedNoteId;
}
final class NotesError extends NotesState { final String message; }
```

### 与 FFI 集成

```dart
class NotesBloc extends Bloc<NotesEvent, NotesState> {
  final Dispatch _dispatch;  // FFI 请求分发

  NotesBloc(this._dispatch) : super(NotesInitial()) {
    on<NotesLoadRequested>(_onLoad);
    on<NoteSelected>(_onSelect);
    on<NoteCreated>(_onCreate);
    on<NoteDeleted>(_onDelete);
  }

  Future<void> _onLoad(NotesLoadRequested event, Emitter<NotesState> emit) async {
    emit(NotesLoading());
    try {
      final response = await _dispatch.send('notes.list', {});
      final notes = response.data.map((e) => NoteModel.fromJson(e)).toList();
      emit(NotesLoaded(notes: notes));
    } catch (e) {
      emit(NotesError(message: e.toString()));
    }
  }
}
```

### 依赖注入

使用 `get_it` 管理 BLoC 和 Service 实例：

```dart
final getIt = GetIt.instance;

void setupDependencies() {
  getIt.registerSingleton<FFIBridge>(FFIBridge.instance);
  getIt.registerSingleton<Dispatch>(Dispatch.instance);
  getIt.registerFactory<NotesBloc>(() => NotesBloc(getIt<Dispatch>()));
  getIt.registerFactory<EditorBloc>(() => EditorBloc(getIt<Dispatch>()));
  getIt.registerFactory<SyncBloc>(() => SyncBloc(getIt<Dispatch>()));
}
```

## 后果

### 正面

- **单向数据流**：事件 → 状态 → UI，数据流向清晰，易于理解和调试。
- **测试友好**：BLoC 可以脱离 UI 独立测试，`bloc_test` 库支持事件驱动测试。
- **与 FFI 天然适配**：BLoC 的异步事件流与 FFI 调用的异步特性完美匹配。
- **状态隔离**：每个 BLoC 管理独立状态域，降低跨组件状态耦合。
- **DevTools 支持**：`flutter_bloc` 与 Flutter DevTools 集成，支持 BLoC 状态可视化。

### 负面

- **样板代码多**：每个功能需要定义事件、状态、BLoC 三个类，代码量较大。
- **过度抽象风险**：简单的 UI 状态（如对话框开关）不需要 BLoC，应使用 `setState`。
- **DI 依赖**：BLoC 依赖 `get_it` 等 DI 框架，否则构造器注入变得繁琐。
- **Dart 3 特性未充分利用**：当前使用老式 `copyWith` 状态类，可迁移到 Dart 3 `sealed class` + `record`。

### 已识别风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| BLoC 直连全局 Dispatch（破坏 DI）| 通过构造函数注入 Dispatch，使用 get_it 管理实例 |
| 样板代码过多 | 对于简单状态使用 `setState` 或 `ValueNotifier`；复杂状态才用 BLoC |
| 状态类不够类型安全 | 迁移到 Dart 3 `sealed class`，利用 exhaustive switch |
| BLoC 生命周期管理 | 使用 `BlocProvider` 自动管理 dispose；避免全局单例 BLoC |
