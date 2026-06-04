import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/bridge/error.dart';
import 'package:devnote/core/di/injection.dart';

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
  final Dispatch _dispatch = getIt<Dispatch>();
  StreamController<FileChangeEvent>? _controller;

  Stream<FileChangeEvent> get onFileChange {
    _controller ??= StreamController<FileChangeEvent>.broadcast();
    return _controller!.stream;
  }

  Future<void> watchDirectory(String path) async {
    final payload = jsonEncode({'watch_path': path});
    await _dispatch.asyncRequest(
      'WorkflowEvent.WatchDirectory',
      payload: utf8.encode(payload),
    );
  }

  Future<void> stopWatching() async {
    await _controller?.close();
    _controller = null;
  }

  void handleEvent(FlowyResult<Uint8List, FlowyInternalError> result) {
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is Map<String, dynamic>) {
        final event = FileChangeEvent.fromJson(json);
        _controller?.add(event);
      }
    }
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
}
