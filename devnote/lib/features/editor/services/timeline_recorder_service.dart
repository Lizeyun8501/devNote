import 'dart:async';
import 'voice_recorder_service.dart';
import '../models/timeline_marker.dart';
import 'package:uuid/uuid.dart';

/// 带时间轴同步的录音服务
/// 录音过程中记录每个文本块的创建/修改时间点
class TimelineRecorderService {
  final VoiceRecorderService _recorderService;
  final List<TimelineMarker> _markers = [];
  final _markerController = StreamController<TimelineMarker>.broadcast();
  bool _isRecording = false;
  String? _currentAudioBlockId;
  DateTime? _startTime;

  TimelineRecorderService(this._recorderService);

  Stream<TimelineMarker> get markerStream => _markerController.stream;
  bool get isRecording => _isRecording;
  List<TimelineMarker> get markers => List.unmodifiable(_markers);

  /// 开始带时间轴的录音
  Future<String> startRecording(String audioBlockId) async {
    if (_isRecording) return _currentAudioBlockId!;

    _currentAudioBlockId = audioBlockId;
    _markers.clear();
    _startTime = DateTime.now();

    final path = await _recorderService.startRecording();
    _isRecording = true;
    return path;
  }

  /// 停止录音，返回所有时间轴标记
  Future<List<TimelineMarker>> stopRecording() async {
    if (!_isRecording) return [];

    await _recorderService.stopRecording();
    _isRecording = false;
    return List.from(_markers);
  }

  /// 取消录音
  Future<void> cancelRecording() async {
    await _recorderService.cancelRecording();
    _isRecording = false;
    _markers.clear();
    _currentAudioBlockId = null;
    _startTime = null;
  }

  /// 记录一个时间轴标记（当用户输入文本时调用）
  void markBlock(String blockId, {String? noteText}) {
    if (!_isRecording || _currentAudioBlockId == null || _startTime == null) {
      return;
    }

    final timestampMs = DateTime.now().difference(_startTime!).inMilliseconds;
    final marker = TimelineMarker(
      id: const Uuid().v4(),
      blockId: blockId,
      audioBlockId: _currentAudioBlockId!,
      timestampMs: timestampMs,
      noteText: noteText,
    );

    _markers.add(marker);
    _markerController.add(marker);
  }

  /// 获取当前录音时长（毫秒）
  int get currentDurationMs {
    if (_startTime == null) return 0;
    return DateTime.now().difference(_startTime!).inMilliseconds;
  }

  void dispose() {
    _markerController.close();
  }
}
