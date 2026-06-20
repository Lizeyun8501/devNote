// 修复(P2-1): 将 EditorService 注册到 DI 容器，消除页面中直接 new Service 绕过 DI 的问题。
// 遵循 ai_module.dart 的模块自注册模式：core/di 仅注册 core 层服务，
// features 层各自提供 register/dispose 函数，由 main.dart 调用。

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/editor/services/editor_service.dart';

/// 注册 Editor 模块依赖
Future<void> registerEditorDependencies() async {
  if (!getIt.isRegistered<EditorService>()) {
    getIt.registerLazySingleton<EditorService>(() => EditorService());
  }
}

/// 释放 Editor 模块资源
/// EditorService 依赖的 DatabaseHelper 由 disposeCore() 统一释放，无需额外清理。
void disposeEditorModule() {
  // EditorService 无需显式释放资源
}
