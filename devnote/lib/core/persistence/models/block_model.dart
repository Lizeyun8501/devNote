import 'package:equatable/equatable.dart';

// 持久化层 BlockModel：与 Rust devnote-editor/src/lib.rs Block 结构体字段对齐
// 同时补齐与 features/editor/models/block_model.dart 的字段映射，
// 避免 FFI 路径双向转换时丢失 language/children/createdAt/updatedAt。
class BlockModel extends Equatable {
  final String id;
  final String noteId;
  final String blockType;
  final String content;
  final int position;
  final String? language;
  final List<String> children;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BlockModel({
    required this.id,
    required this.noteId,
    required this.blockType,
    required this.content,
    required this.position,
    this.language,
    this.children = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory BlockModel.fromJson(Map<String, dynamic> json) {
    final childrenRaw = json['children'];
    return BlockModel(
      id: json['id'] as String,
      noteId: (json['note_id'] ?? json['noteId']) as String,
      blockType: (json['block_type'] ?? json['blockType']) as String,
      content: (json['content'] as String?) ?? '',
      position: (json['position'] as num?)?.toInt() ?? 0,
      language: json['language'] as String?,
      children: childrenRaw is List
          ? childrenRaw.map((e) => e.toString()).toList()
          : const <String>[],
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: _parseDate(json['updated_at'] ?? json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'note_id': noteId,
      'block_type': blockType,
      'content': content,
      'position': position,
      'children': children,
    };
    if (language != null) map['language'] = language;
    if (createdAt != null) map['created_at'] = createdAt!.toIso8601String();
    if (updatedAt != null) map['updated_at'] = updatedAt!.toIso8601String();
    return map;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  @override
  List<Object?> get props => [
        id,
        noteId,
        blockType,
        content,
        position,
        language,
        children,
        createdAt,
        updatedAt,
      ];
}
