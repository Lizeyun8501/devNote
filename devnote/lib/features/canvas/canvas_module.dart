// 修复(P2-1): 将 CanvasService 注册到 DI 容器，消除页面中直接 new Service 绕过 DI 的问题。
// 遵循 ai_module.dart 的模块自注册模式：core/di 仅注册 core 层服务，
// features 层各自提供 register/dispose 函数，由 main.dart 调用。

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/canvas/canvas_service.dart';

/// 注册 Canvas 模块依赖
Future<void> registerCanvasDependencies() async {
  if (!getIt.isRegistered<CanvasService>()) {
    getIt.registerLazySingleton<CanvasService>(() => CanvasService());
  }
}

/// 释放 Canvas 模块资源
void disposeCanvasModule() {
  if (getIt.isRegistered<CanvasService>()) {
    getIt<CanvasService>().dispose();
  }
}
