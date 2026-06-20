import 'dart:convert';

/// 时间轴标记 — 关联文本块与录音时间点
class TimelineMarker {
  final String id;
  final String blockId;      // 关联的文本块 ID
  final String audioBlockId; // 关联的音频块 ID
  final int timestampMs;     // 录音中的时间点（毫秒）
  final String? noteText;    // 标记时的文本快照

  TimelineMarker({
    required this.id,
    required this.blockId,
    required this.audioBlockId,
    required this.timestampMs,
    this.noteText,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'block_id': blockId,
        'audio_block_id': audioBlockId,
        'timestamp_ms': timestampMs,
        'note_text': noteText,
      };

  factory TimelineMarker.fromJson(Map<String, dynamic> json) => TimelineMarker(
        id: json['id'] as String,
        blockId: json['block_id'] as String,
        audioBlockId: json['audio_block_id'] as String,
        timestampMs: (json['timestamp_ms'] as num).toInt(),
        noteText: json['note_text'] as String?,
      );

  static List<TimelineMarker> fromJsonList(String jsonStr) {
    final list = jsonDecode(jsonStr) as List;
    return list
        .map((e) => TimelineMarker.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String toJsonList(List<TimelineMarker> markers) {
    return jsonEncode(markers.map((m) => m.toJson()).toList());
  }
}
