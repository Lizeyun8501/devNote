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

  const BlockModel({
    required this.id,
    required this.noteId,
    required this.blockType,
    required this.content,
    required this.position,
    this.language,
  });

  BlockModel copyWith({
    String? id,
    String? noteId,
    BlockType? blockType,
    String? content,
    int? position,
    String? language,
  }) {
    return BlockModel(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      blockType: blockType ?? this.blockType,
      content: content ?? this.content,
      position: position ?? this.position,
      language: language ?? this.language,
    );
  }

  @override
  List<Object?> get props => [id, noteId, blockType, content, position, language];
}
