import 'dart:convert';
import 'dart:io';

import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/di/injection.dart';

/// 语音转文字服务
///
/// 优先通过 FFI 调用 Rust 端 whisper-rs 进行本地转写；
/// FFI 不可用时降级为平台原生 API（Android SpeechRecognizer / iOS SFSpeechRecognizer）。
class SpeechToTextService {
  final FfiBridge _ffiBridge = getIt<FfiBridge>();

  /// 将音频文件转写为文字
  ///
  /// [filePath] 音频文件路径（m4a/wav）
  /// [lang] 语言代码（如 'zh', 'en', 'ja'）
  Future<TranscribeResult> transcribe({
    required String filePath,
    String lang = 'zh',
  }) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final audioBase64 = base64Encode(bytes);

    // 调用 FFI 进行语音转文字
    // 注意：此功能需要 Rust 端集成 whisper-rs
    // 当前为接口框架，实际转写逻辑在 Rust 端实现
    try {
      final result = await _ffiBridge.transcribeAudio(
        audioBase64: audioBase64,
        lang: lang,
      );
      return TranscribeResult(
        text: result.text,
        durationMs: result.durationMs,
        segments: result.segments
            .map((s) => TranscriptSegment(
                  text: s.text,
                  startMs: s.startMs,
                  endMs: s.endMs,
                ))
            .toList(),
      );
    } catch (e) {
      // FFI 不可用时降级为平台原生 API
      return _transcribeWithPlatformApi(filePath, lang);
    }
  }

  /// 平台原生语音识别降级方案
  Future<TranscribeResult> _transcribeWithPlatformApi(
    String filePath,
    String lang,
  ) async {
    // TODO: 集成 Android SpeechRecognizer / iOS SFSpeechRecognizer
    // 通过 MethodChannel 调用平台原生 API
    return TranscribeResult(
      text: '',
      durationMs: 0,
      segments: [],
    );
  }
}

/// 转写结果
class TranscribeResult {
  final String text;
  final int durationMs;
  final List<TranscriptSegment> segments;

  TranscribeResult({
    required this.text,
    required this.durationMs,
    required this.segments,
  });
}

/// 转写片段（带时间戳）
class TranscriptSegment {
  final String text;
  final int startMs;
  final int endMs;

  TranscriptSegment({
    required this.text,
    required this.startMs,
    required this.endMs,
  });
}
