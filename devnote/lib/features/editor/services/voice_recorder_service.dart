import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 语音录制服务 —— 封装 record 包的 AudioRecorder
///
/// 职责：
/// - 请求麦克风权限
/// - 开始/停止/取消录音（AAC-LC 编码，m4a 输出）
/// - 跟踪录音时长
///
/// 录音文件存储在应用文档目录下，文件名格式：voice_<timestamp>.m4a
class VoiceRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _currentPath;
  DateTime? _startTime;

  bool get isRecording => _isRecording;

  /// 当前录音已持续时长（仅在录音中有效）
  Duration? get duration => _startTime != null
      ? DateTime.now().difference(_startTime!)
      : null;

  /// 请求麦克风权限
  Future<bool> requestPermission() async {
    return await _recorder.hasPermission();
  }

  /// 开始录音，返回录音文件路径
  ///
  /// 若已在录音中，直接返回当前路径。
  /// 权限被拒绝时抛出 [Exception]。
  Future<String> startRecording() async {
    if (_isRecording) return _currentPath!;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission denied');
    }

    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _currentPath = '${dir.path}/$fileName';
    _startTime = DateTime.now();

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _currentPath!,
    );
    _isRecording = true;
    return _currentPath!;
  }

  /// 停止录音并返回文件路径
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    final path = await _recorder.stop();
    _isRecording = false;
    return path ?? _currentPath;
  }

  /// 取消录音，删除临时文件
  Future<void> cancelRecording() async {
    if (_isRecording) {
      await _recorder.cancel();
      _isRecording = false;
    }
    // 删除临时文件
    if (_currentPath != null) {
      final file = File(_currentPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }
    _currentPath = null;
    _startTime = null;
  }

  /// 获取录音时长（毫秒）
  int getDurationMs() {
    if (_startTime == null) return 0;
    return DateTime.now().difference(_startTime!).inMilliseconds;
  }

  void dispose() {
    _recorder.dispose();
  }
}
