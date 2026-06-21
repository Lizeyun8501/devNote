// NoteModel —— Dart 端笔记模型
//
// P1 修复 (P1-6 数据模型跨端对齐):
// 原实现仅 6 字段，与 Rust Note 模型（10 字段）不对齐，导致：
//   - Rust 写入的 blocks/tags/is_pinned/is_encrypted 字段 Dart 读取时忽略
//   - 再写回时丢失这些字段
// 现补齐 blocks/tags/is_pinned/is_encrypted 字段，与 Rust 端对齐。
//
// 注意：原使用 freezed 但未生成 .freezed.dart/.g.dart 文件，改为手动实现。

import 'dart:convert';

class NoteModel {
  final String id;
  final String title;
  final String content;
  final String folderId;
  final DateTime createdAt;
  final DateTime updatedAt;

  // P1 修复: 补齐与 Rust Note 模型对齐的字段
  /// block 列表 JSON（与 Rust blocks 字段对齐）
  /// Dart 端 EditorService 单独管理 blocks 表，此字段用于跨端同步时携带
  final String? blocksJson;
  /// tag ID 列表（与 Rust tags 字段对齐）
  final List<String> tagIds;
  final bool isPinned;
  final bool isEncrypted;

  const NoteModel({
    required this.id,
    required this.title,
    required this.content,
    required this.folderId,
    required this.createdAt,
    required this.updatedAt,
    this.blocksJson,
    this.tagIds = const [],
    this.isPinned = false,
    this.isEncrypted = false,
  });

  NoteModel copyWith({
    String? id,
    String? title,
    String? content,
    String? folderId,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? blocksJson,
    List<String>? tagIds,
    bool? isPinned,
    bool? isEncrypted,
  }) {
    return NoteModel(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      folderId: folderId ?? this.folderId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      blocksJson: blocksJson ?? this.blocksJson,
      tagIds: tagIds ?? this.tagIds,
      isPinned: isPinned ?? this.isPinned,
      isEncrypted: isEncrypted ?? this.isEncrypted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'folder_id': folderId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        // P1 修复: 序列化新增字段，确保跨端同步时不丢失
        if (blocksJson != null) 'blocks': blocksJson,
        'tags': tagIds,
        'is_pinned': isPinned,
        'is_encrypted': isEncrypted,
      };

  /// P1 修复 (P1-6): 用于 sqflite 持久化的 JSON 表示。
  /// 排除 `tags`（List<String>，由 note_tags 关联表管理）和
  /// `blocks`（由 blocks 表管理），这些字段不能直接存入 notes 表。
  /// 包含 `is_pinned`/`is_encrypted`（note 级元数据，需存入 notes 表）。
  Map<String, dynamic> toSqfliteJson() => {
        'id': id,
        'title': title,
        'content': content,
        'folder_id': folderId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'is_pinned': isPinned ? 1 : 0,
        'is_encrypted': isEncrypted ? 1 : 0,
      };

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    // P1 修复: is_pinned/is_encrypted 兼容 bool 和 int 两种表示
    // sqflite 存储 0/1，FFI/同步服务返回 true/false
    bool parseBool(dynamic value, {bool defaultValue = false}) {
      if (value is bool) return value;
      if (value is int) return value != 0;
      if (value is num) return value != 0;
      return defaultValue;
    }

    return NoteModel(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      folderId: json['folder_id'] as String? ?? '',
      createdAt: json['created_at'] is String
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] is String
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      // P1 修复: 反序列化新增字段，兼容旧数据（字段不存在时用默认值）
      blocksJson: json['blocks'] is String
          ? json['blocks'] as String
          : (json['blocks'] is List ? jsonEncode(json['blocks']) : null),
      tagIds: (json['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isPinned: parseBool(json['is_pinned']),
      isEncrypted: parseBool(json['is_encrypted']),
    );
  }

  @override
  String toString() =>
      'NoteModel(id: $id, title: $title, folderId: $folderId, isPinned: $isPinned, isEncrypted: $isEncrypted)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
