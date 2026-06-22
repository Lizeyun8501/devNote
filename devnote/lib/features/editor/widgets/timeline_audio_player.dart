import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../models/timeline_marker.dart';

/// 带时间轴标记的音频播放器
/// 显示录音时间轴，标记文本块对应的时间点
/// 点击标记可跳转到对应文本块；点击文本块可跳转到录音对应时间
class TimelineAudioPlayer extends StatefulWidget {
  final String audioPath;
  final int durationMs;
  final String transcript;
  final List<TimelineMarker> markers;
  final Function(String blockId)? onMarkerTap; // 点击标记跳转到文本块

  const TimelineAudioPlayer({
    super.key,
    required this.audioPath,
    required this.durationMs,
    required this.transcript,
    required this.markers,
    this.onMarkerTap,
  });

  @override
  State<TimelineAudioPlayer> createState() => _TimelineAudioPlayerState();
}

class _TimelineAudioPlayerState extends State<TimelineAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _setupPlayer();
    _duration = Duration(milliseconds: widget.durationMs);
  }

  void _setupPlayer() {
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
  }

  Future<void> _togglePlay() async {
    if (widget.audioPath.isEmpty) return;
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play(DeviceFileSource(widget.audioPath));
    }
  }

  /// 跳转到指定时间点
  Future<void> _seekTo(int timestampMs) async {
    await _player.seek(Duration(milliseconds: timestampMs));
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 播放控制
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
                    // 时间轴 + 标记
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final totalMs = _duration.inMilliseconds.toDouble();
                        return SizedBox(
                          height: 40,
                          child: Stack(
                            children: [
                              // 进度条
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: LinearProgressIndicator(
                                    value: totalMs > 0
                                        ? _position.inMilliseconds / totalMs
                                        : 0,
                                    backgroundColor:
                                        Theme.of(context).colorScheme.surface,
                                  ),
                                ),
                              ),
                              // 时间轴标记
                              ...widget.markers.map((marker) {
                                final left = totalMs > 0
                                    ? (marker.timestampMs / totalMs) *
                                        constraints.maxWidth
                                    : 0.0;
                                return Positioned(
                                  left: left - 6,
                                  top: 8,
                                  child: GestureDetector(
                                    onTap: () {
                                      _seekTo(marker.timestampMs);
                                      widget.onMarkerTap?.call(marker.blockId);
                                    },
                                    child: Tooltip(
                                      message: _formatDuration(
                                          Duration(milliseconds: marker.timestampMs)),
                                      child: Container(
                                        width: 12,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color:
                                              Theme.of(context).colorScheme.primary,
                                          shape: BoxShape.rectangle,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
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
          if (widget.transcript.isNotEmpty) ...[
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
                widget.transcript,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
