// 确保与 Rust devnote-editor/src/lib.rs Block 结构体字段对齐
// Dart ↔ Rust 序列化映射：BlockModel.id ↔ Block.id, BlockModel.content ↔ Block.content, etc.

import 'package:equatable/equatable.dart';

enum BlockType {
  paragraph,
  heading1,
  heading2,
  heading3,
  heading4,
  heading5,
  heading6,
  codeBlock,
  list,
  orderedList,
  quote,
  tableBlock,
  image,
  latexBlock,
  taskListBlock,
}

class BlockModel extends Equatable {
  final String id;
  final String noteId;
  final BlockType blockType;
  final String content;
  final int position;
  final String? language;
  final List<String> children;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BlockModel({
    required this.id,
    required this.noteId,
    required this.blockType,
    required this.content,
    required this.position,
    this.language,
    this.children = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  BlockModel copyWith({
    String? id,
    String? noteId,
    BlockType? blockType,
    String? content,
    int? position,
    String? language,
    List<String>? children,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BlockModel(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      blockType: blockType ?? this.blockType,
      content: content ?? this.content,
      position: position ?? this.position,
      language: language ?? this.language,
      children: children ?? this.children,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
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