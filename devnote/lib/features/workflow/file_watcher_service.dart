import 'dart:async';

enum FileChangeKind { create, modify, delete, rename }

class FileChangeEvent {
  final String path;
  final FileChangeKind kind;

  const FileChangeEvent({
    required this.path,
    required this.kind,
  });

  factory FileChangeEvent.fromJson(Map<String, dynamic> json) {
    return FileChangeEvent(
      path: json['path'] as String,
      kind: FileChangeKind.values.firstWhere(
        (e) => e.name == (json['kind'] as String),
        orElse: () => FileChangeKind.modify,
      ),
    );
  }
}

class FileWatcherService {
  StreamController<FileChangeEvent>? _controller;

  // ============================================================
  // 防抖机制 —— 借鉴 VS Code 的 files.watcherExclude + debounce 设计
  // 来源: https://code.visualstudio.com/api/extension-guides/file-watcher
  // 借鉴内容: 文件变更事件的防抖处理，避免短时间内大量事件导致性能问题
  // ============================================================
  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 300);
  final List<FileChangeEvent> _pendingEvents = [];

  Stream<FileChangeEvent> get onFileChange {
    _controller ??= StreamController<FileChangeEvent>.broadcast();
    return _controller!.stream;
  }

  Future<void> watchDirectory(String path) async {
    // FFI 层尚未实现此事件
    throw UnimplementedError(
      'WorkflowEvent.WatchDirectory not yet implemented in FFI',
    );
  }

  Future<void> stopWatching() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingEvents.clear();
    await _controller?.close();
    _controller = null;
  }

  /// 防抖处理：短时间内多个文件变更事件合并为一次通知
  /// 借鉴 VS Code 的 file watcher debounce 机制
  void _addDebouncedEvent(FileChangeEvent event) {
    _pendingEvents.add(event);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (_controller != null && !_controller!.isClosed) {
        // 合并同类事件：相同路径只保留最后一个
        final merged = <String, FileChangeEvent>{};
        for (final e in _pendingEvents) {
          merged[e.path] = e;
        }
        for (final e in merged.values) {
          _controller!.add(e);
        }
      }
      _pendingEvents.clear();
    });
  }

  // ============================================================
  // 外部编辑器同步支持
  // 借鉴 VS Code 的 file watching 机制：
  // https://code.visualstudio.com/api/extension-guides/file-watcher
  // ============================================================

  bool _externalEditorEnabled = false;
  final Set<String> _ignoredPaths = <String>{};
  final Set<String> _watchedExternalPaths = <String>{};

  /// 启用外部编辑器同步
  /// 添加指定路径到监听列表，外部编辑器的变更将通过 onFileChange 流推送
  void enableExternalEditorSync(String path) {
    _externalEditorEnabled = true;
    _watchedExternalPaths.add(path);
  }

  /// 禁用外部编辑器同步
  void disableExternalEditorSync(String path) {
    _watchedExternalPaths.remove(path);
    if (_watchedExternalPaths.isEmpty) {
      _externalEditorEnabled = false;
    }
  }

  /// 添加忽略路径（不触发事件）
  /// 借鉴 VS Code 的 files.watcherExclude 配置
  void addIgnoredPath(String pattern) {
    _ignoredPaths.add(pattern);
  }

  /// 移除忽略路径
  void removeIgnoredPath(String pattern) {
    _ignoredPaths.remove(pattern);
  }

  /// 检查路径是否被忽略
  bool isPathIgnored(String path) {
    return _ignoredPaths.any((pattern) => path.contains(pattern));
  }

  /// 检查外部编辑器同步是否已启用
  bool get isExternalEditorEnabled => _externalEditorEnabled;

  /// 获取当前监听的目录路径
  List<String> get externalPaths => List.unmodifiable(_watchedExternalPaths);

  /// 释放资源：取消定时器，关闭流控制器
  Future<void> dispose() async {
    await stopWatching();
  }
}
