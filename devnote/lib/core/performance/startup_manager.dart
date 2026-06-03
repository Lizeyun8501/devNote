import 'dart:async';

class StartupManager {
  StartupManager();

  final List<StartupTask> _criticalTasks = [];
  final List<StartupTask> _normalTasks = [];
  final List<StartupTask> _lazyTasks = [];
  final Map<String, Duration> _taskDurations = {};
  DateTime? _startupTime;

  Map<String, Duration> get taskDurations => Map.unmodifiable(_taskDurations);
  Duration? get totalStartupTime => _startupTime != null ? DateTime.now().difference(_startupTime!) : null;

  Future<void> initialize() async {
    registerCritical('initTheme', () async {
      // Theme initialization happens on first access
    });

    registerCritical('initRouter', () async {
      // Router initialization happens on first access
    });

    await runStartup();
  }

  void registerCritical(String name, Future<void> Function() task) {
    _criticalTasks.add(StartupTask(name: name, task: task));
  }

  void registerNormal(String name, Future<void> Function() task) {
    _normalTasks.add(StartupTask(name: name, task: task));
  }

  void registerLazy(String name, Future<void> Function() task) {
    _lazyTasks.add(StartupTask(name: name, task: task));
  }

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

  Future<void> _runTask(StartupTask task) async {
    final start = DateTime.now();
    await task.task();
    final duration = DateTime.now().difference(start);
    _taskDurations[task.name] = duration;
  }

  Future<void> _runLazyTasks() async {
    for (final task in _lazyTasks) {
      await _runTask(task);
    }
  }

  void reset() {
    _criticalTasks.clear();
    _normalTasks.clear();
    _lazyTasks.clear();
    _taskDurations.clear();
    _startupTime = null;
  }
}

class StartupTask {
  final String name;
  final Future<void> Function() task;

  StartupTask({required this.name, required this.task});
}
