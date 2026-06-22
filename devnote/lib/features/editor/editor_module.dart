// 修复(P2-1): 将 EditorService 注册到 DI 容器，消除页面中直接 new Service 绕过 DI 的问题。
// 遵循 ai_module.dart 的模块自注册模式：core/di 仅注册 core 层服务，
// features 层各自提供 register/dispose 函数，由 main.dart 调用。

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/services/note_block_creation_port.dart';
import 'package:devnote/features/editor/services/editor_service.dart';
import 'package:devnote/features/editor/services/math_ink_service.dart';
import 'package:devnote/features/editor/services/speech_to_text_service.dart';
import 'package:devnote/features/editor/services/timeline_recorder_service.dart';
import 'package:devnote/features/editor/services/voice_recorder_service.dart';

/// 注册 Editor 模块依赖
Future<void> registerEditorDependencies() async {
  if (!getIt.isRegistered<EditorService>()) {
    getIt.registerLazySingleton<EditorService>(() => EditorService());
  }
  // P1 修复 (P1-3): 注册 NoteBlockCreationPort 接口，允许 notes 模块
  // 通过接口依赖 editor 实现，打破 notes ↔ editor 循环依赖。
  if (!getIt.isRegistered<NoteBlockCreationPort>()) {
    getIt.registerLazySingleton<NoteBlockCreationPort>(
      () => getIt<EditorService>(),
    );
  }
  if (!getIt.isRegistered<VoiceRecorderService>()) {
    getIt.registerLazySingleton<VoiceRecorderService>(() => VoiceRecorderService());
  }
  if (!getIt.isRegistered<SpeechToTextService>()) {
    getIt.registerLazySingleton<SpeechToTextService>(() => SpeechToTextService());
  }
  if (!getIt.isRegistered<TimelineRecorderService>()) {
    getIt.registerLazySingleton<TimelineRecorderService>(
      () => TimelineRecorderService(getIt<VoiceRecorderService>()),
    );
  }
  // P2-9: 手写公式识别（数学墨迹）服务
  if (!getIt.isRegistered<MathInkService>()) {
    getIt.registerLazySingleton<MathInkService>(() => MathInkService());
  }
}

/// 释放 Editor 模块资源
/// EditorService 依赖的 DatabaseHelper 由 disposeCore() 统一释放，无需额外清理。
void disposeEditorModule() {
  // EditorService 无需显式释放资源
}
