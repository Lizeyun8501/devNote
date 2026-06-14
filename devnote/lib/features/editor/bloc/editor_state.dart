import 'package:devnote/features/editor/models/block_model.dart';

sealed class EditorState {
  const EditorState();
}

final class EditorInitial extends EditorState {
  const EditorInitial();
}

final class EditorLoading extends EditorState {
  const EditorLoading();
}

final class EditorLoaded extends EditorState {
  final String noteId;
  final List<BlockModel> blocks;
  final String? activeBlockId;
  final List<List<BlockModel>> undoStack;
  final List<List<BlockModel>> redoStack;
  final int maxUndoLevels;

  const EditorLoaded({
    required this.noteId,
    required this.blocks,
    this.activeBlockId,
    this.undoStack = const [],
    this.redoStack = const [],
    this.maxUndoLevels = 50,
  });

  EditorLoaded pushUndo(List<BlockModel> previousBlocks) {
    final newUndoStack = List<List<BlockModel>>.from(undoStack)..add(previousBlocks);
    if (newUndoStack.length > maxUndoLevels) {
      newUndoStack.removeAt(0);
    }
    return copyWith(blocks: blocks, undoStack: newUndoStack, redoStack: []);
  }

  EditorLoaded undo(List<BlockModel> currentBlocks) {
    if (undoStack.isEmpty) return this;
    final previous = undoStack.last;
    final newUndoStack = List<List<BlockModel>>.from(undoStack)..removeLast();
    final newRedoStack = List<List<BlockModel>>.from(redoStack)..add(currentBlocks);
    return copyWith(blocks: previous, undoStack: newUndoStack, redoStack: newRedoStack);
  }

  EditorLoaded redo(List<BlockModel> currentBlocks) {
    if (redoStack.isEmpty) return this;
    final next = redoStack.last;
    final newRedoStack = List<List<BlockModel>>.from(redoStack)..removeLast();
    final newUndoStack = List<List<BlockModel>>.from(undoStack)..add(currentBlocks);
    return copyWith(blocks: next, undoStack: newUndoStack, redoStack: newRedoStack);
  }

  /// 修复：copyWith 使用 _Sentinel 模式支持清除 activeBlockId
  /// 原代码 `activeBlockId ?? this.activeBlockId` 无法传 null 取消选中
  EditorLoaded copyWith({
    String? noteId,
    List<BlockModel>? blocks,
    Object? activeBlockId = _sentinel,
    List<List<BlockModel>>? undoStack,
    List<List<BlockModel>>? redoStack,
    int? maxUndoLevels,
  }) {
    return EditorLoaded(
      noteId: noteId ?? this.noteId,
      blocks: blocks ?? this.blocks,
      activeBlockId: activeBlockId == _sentinel ? this.activeBlockId : activeBlockId as String?,
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
      maxUndoLevels: maxUndoLevels ?? this.maxUndoLevels,
    );
  }
}

/// Sentinel 值用于区分"未传参"和"显式传 null"
const _sentinel = Object();

final class EditorError extends EditorState {
  final String message;

  const EditorError(this.message);
}
