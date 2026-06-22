// 白板模块 DI 注册 —— 遵循项目模块自注册模式
// 借鉴 canvas_module.dart / editor_module.dart 的写法

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/whiteboard/whiteboard_service.dart';

/// 注册白板模块依赖
Future<void> registerWhiteboardDependencies() async {
  if (!getIt.isRegistered<WhiteboardService>()) {
    getIt.registerLazySingleton<WhiteboardService>(() => WhiteboardService());
  }
}

/// 释放白板模块资源
void disposeWhiteboardModule() {
  // WhiteboardService 无需显式释放资源
}
