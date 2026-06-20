import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// 音频块 Widget —— 展示录音播放控件和转写文本
///
/// content 字段为 JSON 字符串：{"url": "...", "duration_ms": 12345, "transcript": "..."}
class AudioBlockWidget extends StatefulWidget {
  final String content; // JSON: {url, duration_ms, transcript}
  final Function(String) onContentChanged;
  final bool isEditing;

  const AudioBlockWidget({
    super.key,
    required this.content,
    required this.onContentChanged,
    this.isEditing = false,
  });

  @override
  State<AudioBlockWidget> createState() => _AudioBlockWidgetState();
}

class _AudioBlockWidgetState extends State<AudioBlockWidget> {
  late Map<String, dynamic> _data;
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _parseContent();
    _setupPlayer();
  }

  void _parseContent() {
    try {
      _data = jsonDecode(widget.content) as Map<String, dynamic>;
    } catch (_) {
      _data = {'url': '', 'duration_ms': 0, 'transcript': ''};
    }
  }

  void _setupPlayer() {
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) {
        setState(() => _duration = d);
      }
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) {
        setState(() => _position = p);
      }
    });
  }

  Future<void> _togglePlay() async {
    final url = _data['url'] as String? ?? '';
    if (url.isEmpty) return;

    if (_isPlaying) {
      await _player.pause();
    } else {
      if (File(url).existsSync()) {
        await _player.play(DeviceFileSource(url));
      }
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transcript = _data['transcript'] as String? ?? '';
    final durationMs = _data['duration_ms'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 播放控制栏
          Row(
            children: [
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle),
                iconSize: 36,
                onPressed: _togglePlay,
              ),
              Expanded(
                child: Column(
                  children: [
                    Slider(
                      value: _position.inMilliseconds.toDouble(),
                      max: (_duration.inMilliseconds > 0
                              ? _duration.inMilliseconds
                              : durationMs)
                          .toDouble(),
                      onChanged: (v) {
                        _player.seek(Duration(milliseconds: v.toInt()));
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(_position)),
                        Text(_formatDuration(_duration)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 转写文本
          if (transcript.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                ),
              ),
              child: SelectableText(
                transcript,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
