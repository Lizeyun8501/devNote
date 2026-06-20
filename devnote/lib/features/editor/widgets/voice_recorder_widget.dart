import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/speech_to_text_service.dart';
import '../services/voice_recorder_service.dart';

/// 语音录音 UI 组件
///
/// 提供录音开始/停止按钮和实时时长显示。
/// 录音停止后自动调用语音转文字服务，转写完成后通过 [onRecordingComplete]
/// 回调返回 JSON 格式的 content（{url, duration_ms, transcript}）。
class VoiceRecorderWidget extends StatefulWidget {
  final Function(String content) onRecordingComplete;

  const VoiceRecorderWidget({
    super.key,
    required this.onRecordingComplete,
  });

  @override
  State<VoiceRecorderWidget> createState() => _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends State<VoiceRecorderWidget> {
  final VoiceRecorderService _recorderService = VoiceRecorderService();
  final SpeechToTextService _sttService = SpeechToTextService();
  bool _isRecording = false;
  Duration _duration = Duration.zero;
  bool _transcribing = false;

  void _startTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (_isRecording && _recorderService.duration != null) {
        setState(() => _duration = _recorderService.duration!);
        _startTimer();
      }
    });
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _recorderService.stopRecording();
      final durationMs = _recorderService.getDurationMs();
      setState(() {
        _isRecording = false;
        _transcribing = true;
      });

      if (path != null) {
        // 转写语音
        try {
          final result = await _sttService.transcribe(
            filePath: path,
            lang: 'zh',
          );
          final content = {
            'url': path,
            'duration_ms': durationMs,
            'transcript': result.text,
          };
          widget.onRecordingComplete(jsonEncode(content));
        } catch (e) {
          // 转写失败，仅保存音频
          final content = {
            'url': path,
            'duration_ms': durationMs,
            'transcript': '',
          };
          widget.onRecordingComplete(jsonEncode(content));
        }
      }
      setState(() => _transcribing = false);
    } else {
      try {
        await _recorderService.startRecording();
        setState(() {
          _isRecording = true;
          _duration = Duration.zero;
        });
        _startTimer();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('录音失败: $e')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _recorderService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // 录音按钮
          GestureDetector(
            onTap: _transcribing ? null : _toggleRecording,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording
                    ? Colors.red
                    : Theme.of(context).colorScheme.primary,
              ),
              child: _transcribing
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      color: Colors.white,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // 录音状态/时长
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _transcribing
                      ? '正在转写...'
                      : _isRecording
                          ? '正在录音... ${_duration.inMinutes.toString().padLeft(2, '0')}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}'
                          : '点击开始录音',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (_isRecording)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(
                      value: null,
                      backgroundColor: Colors.red.withAlpha(30),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
