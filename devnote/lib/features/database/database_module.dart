// 修复(P2-1): 将 DatabaseService 注册到 DI 容器，消除页面中直接 new Service 绕过 DI 的问题。
// 遵循 ai_module.dart 的模块自注册模式：core/di 仅注册 core 层服务，
// features 层各自提供 register/dispose 函数，由 main.dart 调用。

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/database/database_service.dart';
import 'package:devnote/features/database/models/comment_model.dart';

/// 注册 Database 模块依赖
Future<void> registerDatabaseDependencies() async {
  if (!getIt.isRegistered<DatabaseService>()) {
    getIt.registerLazySingleton<DatabaseService>(() => DatabaseService());
  }
  // P1-6: 行内评论服务
  if (!getIt.isRegistered<CommentService>()) {
    getIt.registerLazySingleton<CommentService>(() => CommentService());
  }
}

/// 释放 Database 模块资源
/// DatabaseService 依赖的 DatabaseHelper 由 disposeCore() 统一释放，无需额外清理。
void disposeDatabaseModule() {
  // DatabaseService 无需显式释放资源
}
