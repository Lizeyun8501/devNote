// P2-5: 全局待办/提醒系统模块依赖注册。
// 遵循 ai_module.dart / vault_module.dart 的模块自注册模式：
// core/di 仅注册 core 层服务，features 层各自提供 register/dispose 函数，
// 由 main.dart 在 setupDependencies() 之后顺序调用，消除 core → features 反向依赖。

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/todo/services/notification_service.dart';
import 'package:devnote/features/todo/services/todo_service.dart';

/// 注册 Todo 模块依赖
/// NotificationService 必须先于 TodoService 注册（TodoService 依赖它）。
Future<void> registerTodoDependencies() async {
  if (!getIt.isRegistered<NotificationService>()) {
    getIt.registerLazySingleton<NotificationService>(() => NotificationService());
  }
  if (!getIt.isRegistered<TodoService>()) {
    getIt.registerLazySingleton<TodoService>(() => TodoService());
  }
}

/// 释放 Todo 模块资源
/// 取消所有已调度的通知，然后注销单例。
void disposeTodoModule() {
  if (getIt.isRegistered<TodoService>()) {
    getIt.resetLazySingleton<TodoService>();
  }
  if (getIt.isRegistered<NotificationService>()) {
    getIt<NotificationService>().cancelAll();
    getIt.resetLazySingleton<NotificationService>();
  }
}
