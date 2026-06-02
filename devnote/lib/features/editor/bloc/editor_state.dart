import 'package:equatable/equatable.dart';
import 'package:devnote/features/editor/models/block_model.dart';

abstract class EditorState extends Equatable {
  const EditorState();

  @override
  List<Object?> get props => [];
}

class EditorInitial extends EditorState {
  const EditorInitial();
}

class EditorLoading extends EditorState {
  const EditorLoading();
}

class EditorLoaded extends EditorState {
  final String noteId;
  final List<BlockModel> blocks;
  final String? activeBlockId;

  const EditorLoaded({
    required this.noteId,
    required this.blocks,
    this.activeBlockId,
  });

  EditorLoaded copyWith({
    String? noteId,
    List<BlockModel>? blocks,
    String? activeBlockId,
  }) {
    return EditorLoaded(
      noteId: noteId ?? this.noteId,
      blocks: blocks ?? this.blocks,
      activeBlockId: activeBlockId ?? this.activeBlockId,
    );
  }

  @override
  List<Object?> get props => [noteId, blocks, activeBlockId];
}

class EditorError extends EditorState {
  final String message;

  const EditorError(this.message);

  @override
  List<Object?> get props => [message];
}
