// P2-4: Notes 模块依赖注册。
// 遵循 ai_module.dart / templates_module.dart 的模块自注册模式：
// core/di 仅注册 core 层服务，features 层各自提供 register/dispose 函数，
// 由 main.dart 在 setupDependencies() 之后顺序调用，消除 core → features 反向依赖。
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/notes/services/daily_notes_service.dart';
import 'package:devnote/features/notes/services/ocr_service.dart';
import 'package:devnote/features/notes/services/share_service.dart';
import 'package:devnote/features/notes/services/version_history_service.dart';

/// 注册 Notes 模块依赖
Future<void> registerNotesDependencies() async {
  if (!getIt.isRegistered<DailyNotesService>()) {
    getIt.registerLazySingleton<DailyNotesService>(() => DailyNotesService());
  }
  // P0-2: OCR 文字识别 + 图片搜索服务
  if (!getIt.isRegistered<OcrService>()) {
    getIt.registerLazySingleton<OcrService>(() => OcrService());
  }
  // P1-4: 版本历史服务
  if (!getIt.isRegistered<VersionHistoryService>()) {
    getIt.registerLazySingleton<VersionHistoryService>(() => VersionHistoryService());
  }
  // P2-1: 笔记公开分享/发布服务
  if (!getIt.isRegistered<ShareService>()) {
    getIt.registerLazySingleton<ShareService>(() => ShareService());
  }
}

/// 释放 Notes 模块资源
/// DailyNotesService 基于 SharedPreferences，无句柄需显式释放。
void disposeNotesModule() {
  // DailyNotesService 无需显式释放资源
}
