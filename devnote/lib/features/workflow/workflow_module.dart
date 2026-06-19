// 修复(P1): 将 features 层的依赖注册从 core/di/injection.dart 迁移至此，
// 消除 core → features 的反向依赖。

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/workflow/external_editor_sync.dart';
import 'package:devnote/features/workflow/file_watcher_service.dart';

/// 注册 Workflow 模块依赖
Future<void> registerWorkflowDependencies() async {
  getIt.registerLazySingleton<FileWatcherService>(() => FileWatcherService());
  getIt.registerLazySingleton<ExternalEditorSyncService>(
    () => ExternalEditorSyncService(),
  );
}

/// 释放 Workflow 模块资源
void disposeWorkflowModule() {
  if (getIt.isRegistered<ExternalEditorSyncService>()) {
    getIt<ExternalEditorSyncService>().dispose();
  }
  if (getIt.isRegistered<FileWatcherService>()) {
    getIt<FileWatcherService>().dispose();
  }
}
