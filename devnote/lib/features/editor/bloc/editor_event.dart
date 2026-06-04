import 'package:equatable/equatable.dart';
import 'package:devnote/features/editor/models/block_model.dart';

abstract class EditorEvent extends Equatable {
  const EditorEvent();

  @override
  List<Object?> get props => [];
}

class LoadNote extends EditorEvent {
  final String noteId;

  const LoadNote(this.noteId);

  @override
  List<Object?> get props => [noteId];
}

class InsertBlock extends EditorEvent {
  final String noteId;
  final BlockType blockType;
  final String content;
  final int position;

  const InsertBlock({
    required this.noteId,
    required this.blockType,
    required this.content,
    required this.position,
  });

  @override
  List<Object?> get props => [noteId, blockType, content, position];
}

class UpdateBlock extends EditorEvent {
  final String blockId;
  final String content;

  const UpdateBlock({
    required this.blockId,
    required this.content,
  });

  @override
  List<Object?> get props => [blockId, content];
}

class DeleteBlock extends EditorEvent {
  final String blockId;

  const DeleteBlock(this.blockId);

  @override
  List<Object?> get props => [blockId];
}

class MoveBlock extends EditorEvent {
  final String blockId;
  final int newPosition;

  const MoveBlock({
    required this.blockId,
    required this.newPosition,
  });

  @override
  List<Object?> get props => [blockId, newPosition];
}

class ToggleBlockType extends EditorEvent {
  final String blockId;
  final BlockType newType;

  const ToggleBlockType({
    required this.blockId,
    required this.newType,
  });

  @override
  List<Object?> get props => [blockId, newType];
}

class UndoEvent extends EditorEvent {}

class RedoEvent extends EditorEvent {}

class SelectBlock extends EditorEvent {
  final String blockId;

  const SelectBlock(this.blockId);

  @override
  List<Object?> get props => [blockId];
}
