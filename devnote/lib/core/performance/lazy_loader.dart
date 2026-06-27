import 'dart:async';

enum LoadPriority { critical, high, normal, low }

class LazyModule {
  final String name;
  final LoadPriority priority;
  final Future<void> Function() loader;
  bool _loaded = false;
  bool _loading = false;

  LazyModule({
    required this.name,
    required this.priority,
    required this.loader,
  });

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;

  Future<void> load() async {
    if (_loaded || _loading) return;
    _loading = true;
    // P1 修复 (F4): 原实现无 try/finally，若 loader() 抛异常则 _loading 永远为 true，
    // 后续 load() 调用因 guard 直接 return，模块永久卡在"加载中"状态无法重试。
    // 现用 try/finally 确保 _loading 总是被重置，允许失败后重试。
    try {
      await loader();
      _loaded = true;
    } finally {
      _loading = false;
    }
  }
}

class LazyLoader {
  final Map<String, LazyModule> _modules = {};

  void register(String name, LoadPriority priority, Future<void> Function() loader) {
    _modules[name] = LazyModule(name: name, priority: priority, loader: loader);
  }

  Future<void> loadModule(String name) async {
    final module = _modules[name];
    if (module != null) {
      await module.load();
    }
  }

  Future<void> loadByPriority(LoadPriority priority) async {
    final futures = _modules.values
        .where((m) => m.priority == priority && !m.isLoaded)
        .map((m) => m.load());
    await Future.wait(futures);
  }

  Future<void> loadAll() async {
    final sorted = _modules.values.toList()
      ..sort((a, b) => a.priority.index.compareTo(b.priority.index));
    for (final module in sorted) {
      await module.load();
    }
  }

  bool isLoaded(String name) {
    return _modules[name]?.isLoaded ?? false;
  }

  void unregister(String name) {
    _modules.remove(name);
  }
}
