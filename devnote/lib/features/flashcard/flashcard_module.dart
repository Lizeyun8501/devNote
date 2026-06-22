// 修复(P2-1): 将 FlashcardService 注册到 DI 容器，消除页面中直接 new Service 绕过 DI 的问题。
// 遵循 ai_module.dart 的模块自注册模式：core/di 仅注册 core 层服务，
// features 层各自提供 register/dispose 函数，由 main.dart 调用。

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/flashcard/flashcard_service.dart';

/// 注册 Flashcard 模块依赖
Future<void> registerFlashcardDependencies() async {
  if (!getIt.isRegistered<FlashcardService>()) {
    getIt.registerLazySingleton<FlashcardService>(() => FlashcardService());
  }
}

/// 释放 Flashcard 模块资源
/// FlashcardService 依赖的 Dispatch 由 disposeCore() 统一释放，无需额外清理。
void disposeFlashcardModule() {
  // FlashcardService 无需显式释放资源
}
