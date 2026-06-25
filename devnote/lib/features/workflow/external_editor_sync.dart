import 'dart:async';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/observability/app_logger.dart';
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
  ExternalEditorSyncService();

  FileWatcherService get _fileWatcher => getIt<FileWatcherService>();

  Timer? _debounceTimer;
  StreamSubscription? _watcherSubscription;
  String? _watchingDir;

  // 保留 _debounceTimer 引用以保持向后兼容，但实际使用 _fileTimers

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
        AppLogger.e('FileWatcher', 'File watcher error', error: error);
      },
    );
  }

  /// 停止监听
  Future<void> stopWatching() async {
    await _watcherSubscription?.cancel();
    _watcherSubscription = null;

    _debounceTimer?.cancel();
    _debounceTimer = null;

    // 修复：清理所有文件级别定时器
    for (final timer in _fileTimers.values) {
      timer.cancel();
    }
    _fileTimers.clear();

    await _fileWatcher.stopWatching();
    _watchingDir = null;
  }

  /// 从外部编辑器同步文件到 DevNote
  /// 读取外部编辑器修改的文件内容，更新到 DevNote 数据库
  Future<void> syncFromExternalEditor(String filePath) async {
    // FFI 层尚未实现此事件
    throw UnimplementedError(
      'WorkflowEvent.SyncFromExternal not yet implemented in FFI',
    );
  }

  /// 将 DevNote 笔记同步到外部编辑器
  /// 将笔记内容写入外部编辑器可访问的文件路径
  Future<void> syncToExternalEditor(String noteId) async {
    // FFI 层尚未实现此事件
    throw UnimplementedError(
      'WorkflowEvent.GetNoteContent not yet implemented in FFI',
    );
  }

  /// 处理文件变更事件
  /// 借鉴 VS Code 的防抖机制，避免短时间内多次同步
  /// 修复：使用逐个文件防抖而非全局覆盖，避免事件丢失
  /// 原代码使用单个 _debounceTimer，新事件覆盖旧定时器导致旧事件被丢弃
  /// 例如文件 A 在 t=0 变更，文件 B 在 t=0.3s 变更，文件 A 的定时器被取消导致丢失
  final Map<String, Timer> _fileTimers = {};

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

    // 取消该文件的旧定时器，重新开始计时
    _fileTimers[event.path]?.cancel();
    _fileTimers[event.path] = Timer(const Duration(milliseconds: 500), () {
      _fileTimers.remove(event.path);
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
    // FFI 层尚未实现此事件
    throw UnimplementedError(
      'WorkflowEvent.SyncExternalDelete not yet implemented in FFI',
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

  /// 释放资源：停止监听，关闭文件监听器
  Future<void> dispose() async {
    await stopWatching();
    await _fileWatcher.dispose();
  }
}
