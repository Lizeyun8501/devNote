/// 启动管理器（Startup Manager）
///
/// 将应用启动过程拆分为 **关键任务（Critical）/ 普通任务（Normal）/ 延迟任务（Lazy）**
/// 三档优先级，并提供每个任务的耗时埋点，便于性能基线建立与回归监控。
///
/// ## 借鉴的开源项目
/// - **Facebook 移动应用启动优化** ([Engineering Blog](https://engineering.fb.com/)):
///   借鉴其"启动分级"思想：把启动任务按"是否阻塞首屏"分类，
///   - 关键任务：必须在首屏可见前完成（Theme、Router 等）；
///   - 普通任务：在首屏可见后尽快完成（Analytics、Telemetry 注册等）；
///   - 延迟任务：放到首屏完全渲染之后的下一个事件循环中执行（深层模块预热等）。
/// - **Android App Startup** ([官方文档](https://developer.android.com/topic/libraries/app-startup)):
///   借鉴其"启动器 / InitializationProvider"模式：通过 `registerXxx` API 显式注册任务，
///   框架在合适阶段自动执行。本类以 Dart 异步任务实现了相同语义。
///
/// ## 实现说明
/// - 启动顺序：先 `Critical`（顺序 `await`）→ 再 `Normal`（顺序 `await`）→ 最后 `Lazy`（`unawaited` 后台）。
/// - 每个任务执行前后记录 `DateTime` 时间戳，最终汇总到 `_taskDurations`。
/// - `totalStartupTime` 返回从 `runStartup` 开始到当前时刻的总耗时，用于性能监控。
/// - 任务粒度细化为 `StartupTask` 值对象（name + task function），便于在埋点中识别。
library;

import 'dart:async';

/// 启动管理器
///
/// 参考实现：
/// - [Facebook 移动应用启动优化](https://engineering.fb.com/) — 启动分级策略
/// - [Android App Startup](https://developer.android.com/topic/libraries/app-startup) — 启动器注册模式
class StartupManager {
  StartupManager();

  /// 关键任务列表：必须在首屏可见前完成（顺序 `await`）
  final List<StartupTask> _criticalTasks = [];
  /// 普通任务列表：首屏可见后尽快完成（顺序 `await`）
  final List<StartupTask> _normalTasks = [];
  /// 延迟任务列表：后台执行（`unawaited`）
  final List<StartupTask> _lazyTasks = [];
  /// 任务耗时埋点（key: 任务名, value: 单次执行耗时）
  final Map<String, Duration> _taskDurations = {};
  /// `runStartup` 调用时刻，用于计算总启动耗时
  DateTime? _startupTime;

  /// 对外暴露的任务耗时表（只读）
  Map<String, Duration> get taskDurations => Map.unmodifiable(_taskDurations);
  /// 从 `runStartup` 起到当前时刻的总耗时，未启动时为 `null`
  Duration? get totalStartupTime => _startupTime != null ? DateTime.now().difference(_startupTime!) : null;

  /// 初始化入口：注册内置关键任务并启动
  ///
  /// 借鉴 Facebook 移动端做法：Theme / Router 等 UI 必需模块在 `Critical` 阶段注册。
  Future<void> initialize() async {
    registerCritical('initTheme', () async {
      // Theme initialization happens on first access
    });

    registerCritical('initRouter', () async {
      // Router initialization happens on first access
    });

    await runStartup();
  }

  /// 注册关键任务
  ///
  /// 借鉴 Android App Startup `Initializer.create()` API：显式声明任务与依赖。
  void registerCritical(String name, Future<void> Function() task) {
    _criticalTasks.add(StartupTask(name: name, task: task));
  }

  /// 注册普通任务
  void registerNormal(String name, Future<void> Function() task) {
    _normalTasks.add(StartupTask(name: name, task: task));
  }

  /// 注册延迟任务（首屏之后后台执行）
  void registerLazy(String name, Future<void> Function() task) {
    _lazyTasks.add(StartupTask(name: name, task: task));
  }

  /// 按"关键 → 普通 → 延迟"顺序执行所有已注册任务
  ///
  /// 借鉴 Facebook 移动应用启动优化：
  /// - 关键 / 普通任务 `await` 顺序执行，确保首屏不闪烁；
  /// - 延迟任务 `unawaited` 后台执行，释放主线程。
  Future<void> runStartup() async {
    _startupTime = DateTime.now();

    for (final task in _criticalTasks) {
      await _runTask(task);
    }

    for (final task in _normalTasks) {
      await _runTask(task);
    }

    unawaited(_runLazyTasks());
  }

  /// 执行单个任务并记录耗时
  Future<void> _runTask(StartupTask task) async {
    final start = DateTime.now();
    await task.task();
    final duration = DateTime.now().difference(start);
    _taskDurations[task.name] = duration;
  }

  /// 顺序执行所有延迟任务（`unawaited` 调用，故失败不影响主流程）
  Future<void> _runLazyTasks() async {
    for (final task in _lazyTasks) {
      await _runTask(task);
    }
  }

  /// 重置管理器（清空所有任务与耗时记录），主要用于测试场景
  void reset() {
    _criticalTasks.clear();
    _normalTasks.clear();
    _lazyTasks.clear();
    _taskDurations.clear();
    _startupTime = null;
  }
}

/// 启动任务值对象
///
/// 借鉴 Android App Startup `Initializer<T>` 设计：每个任务带有一个 `name`（用于埋点识别）
/// 和一个 `task`（要执行的异步逻辑）。
class StartupTask {
  /// 任务名（用于 `_taskDurations` 的 key 与日志标识）
  final String name;
  /// 任务执行体
  final Future<void> Function() task;

  StartupTask({required this.name, required this.task});
}
