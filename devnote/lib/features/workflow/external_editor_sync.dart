import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/bridge/error.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/workflow/file_watcher_service.dart';

/// 外部编辑器实时同步服务
///
/// 借鉴的开源项目:
/// - VS Code file watching (https://code.visualstudio.com/api/extension-guides/file-watcher):
///   VS Code 的文件监听机制，通过轮询和原生文件系统事件结合实现可靠的文件变更检测
/// - Syncthing 实时文件同步 (https://docs.syncthing.net/):
///   Syncthing 的实时双向文件同步，通过哈希校验检测文件内容变更
///
/// 实现说明:
/// 监听外部编辑器（如 VS Code、Vim 等）对笔记文件的修改，
/// 自动将变更同步到 DevNote 应用中，实现外部编辑器与 DevNote 的实时同步。
class ExternalEditorSyncService {
  final Dispatch _dispatch = getIt<Dispatch>();
  final FileWatcherService _fileWatcher = FileWatcherService();

  Timer? _debounceTimer;
  StreamSubscription? _watcherSubscription;
  String? _watchingDir;

  /// 开始监听指定目录的文件变更
  /// 借鉴 VS Code 的文件监听机制，结合防抖处理避免频繁同步
  Future<void> startWatching(String notesDir) async {
    if (_watchingDir == notesDir) {
      return;
    }

    // 停止之前的监听
    await stopWatching();

    _watchingDir = notesDir;

    // 启动文件监听
    await _fileWatcher.watchDirectory(notesDir);

    // 订阅文件变更事件
    _watcherSubscription = _fileWatcher.onFileChange.listen(
      (event) => _handleFileChange(event, notesDir),
      onError: (error) {
        // 文件监听错误处理，记录但不中断
        debugPrint('File watcher error: $error');
      },
    );
  }

  /// 停止监听
  Future<void> stopWatching() async {
    await _watcherSubscription?.cancel();
    _watcherSubscription = null;

    _debounceTimer?.cancel();
    _debounceTimer = null;

    await _fileWatcher.stopWatching();
    _watchingDir = null;
  }

  /// 从外部编辑器同步文件到 DevNote
  /// 读取外部编辑器修改的文件内容，更新到 DevNote 数据库
  Future<void> syncFromExternalEditor(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return;
    }

    final content = await file.readAsString();
    final fileName = file.uri.pathSegments.last;

    // 通过 FFI 桥接将内容同步到 Rust 核心
    final payload = jsonEncode({
      'file_path': filePath,
      'file_name': fileName,
      'content': content,
      'sync_source': 'external_editor',
    });

    await _dispatch.asyncRequest(
      'WorkflowEvent.SyncFromExternal',
      payload: utf8.encode(payload),
    );
  }

  /// 将 DevNote 笔记同步到外部编辑器
  /// 将笔记内容写入外部编辑器可访问的文件路径
  Future<void> syncToExternalEditor(String noteId) async {
    // 通过 FFI 桥接获取笔记内容
    final payload = jsonEncode({'note_id': noteId});
    final result = await _dispatch.asyncRequest(
      'WorkflowEvent.GetNoteContent',
      payload: utf8.encode(payload),
    );

    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is Map<String, dynamic>) {
        final content = json['content'] as String?;
        final filePath = json['file_path'] as String?;

        if (content != null && filePath != null) {
          final file = File(filePath);
          await file.writeAsString(content);
        }
      }
    }
  }

  /// 处理文件变更事件
  /// 借鉴 VS Code 的防抖机制，避免短时间内多次同步
  void _handleFileChange(FileChangeEvent event, String notesDir) {
    // 忽略目录变更，只处理文件
    if (event.path.endsWith('/')) {
      return;
    }

    // 忽略临时文件（编辑器通常创建临时文件）
    final fileName = event.path.split('/').last;
    if (_isTempFile(fileName)) {
      return;
    }

    // 取消之前的定时器，重新开始计时
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      // 防抖后执行同步
      switch (event.kind) {
        case FileChangeKind.create:
        case FileChangeKind.modify:
          syncFromExternalEditor(event.path);
          break;
        case FileChangeKind.delete:
          _handleExternalDelete(event.path);
          break;
        case FileChangeKind.rename:
          // 重命名视为删除 + 创建
          _handleExternalDelete(event.path);
          syncFromExternalEditor(event.path);
          break;
      }
    });
  }

  /// 处理外部删除事件
  Future<void> _handleExternalDelete(String filePath) async {
    final payload = jsonEncode({
      'file_path': filePath,
      'sync_source': 'external_editor',
    });

    await _dispatch.asyncRequest(
      'WorkflowEvent.SyncExternalDelete',
      payload: utf8.encode(payload),
    );
  }

  /// 判断是否为临时文件
  /// 借鉴 VS Code 的临时文件识别规则
  bool _isTempFile(String fileName) {
    // 常见的临时文件模式
    const tempPrefixes = ['.', '~', '#', '._'];
    const tempExtensions = ['.tmp', '.swp', '.swo', '.bak', '.crdownload'];

    for (final prefix in tempPrefixes) {
      if (fileName.startsWith(prefix)) {
        return true;
      }
    }

    for (final ext in tempExtensions) {
      if (fileName.endsWith(ext)) {
        return true;
      }
    }

    return false;
  }

  /// 获取当前监听状态
  bool get isWatching => _watchingDir != null;

  /// 获取当前监听的目录
  String? get watchingDir => _watchingDir;
}
