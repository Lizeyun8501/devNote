import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/editor/bloc/editor_event.dart';
import 'package:devnote/features/editor/bloc/editor_state.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import 'package:devnote/features/editor/services/editor_service.dart';

class EditorBloc extends Bloc<EditorEvent, EditorState> {
  final EditorService _editorService;

  EditorBloc(this._editorService) : super(const EditorInitial()) {
    on<LoadNote>(_onLoadNote);
    on<InsertBlock>(_onInsertBlock);
    on<UpdateBlock>(_onUpdateBlock);
    on<DeleteBlock>(_onDeleteBlock);
    on<MoveBlock>(_onMoveBlock);
    on<ToggleBlockType>(_onToggleBlockType);
  }

  Future<void> _onLoadNote(LoadNote event, Emitter<EditorState> emit) async {
    emit(const EditorLoading());
    try {
      final blocks = await _editorService.listBlocks(event.noteId);
      if (blocks.isEmpty) {
        final newBlock = await _editorService.createBlock(
          noteId: event.noteId,
          blockType: BlockType.paragraph,
          content: '',
          position: 0,
        );
        emit(EditorLoaded(noteId: event.noteId, blocks: [newBlock]));
      } else {
        emit(EditorLoaded(noteId: event.noteId, blocks: blocks));
      }
    } catch (e) {
      emit(EditorError(e.toString()));
    }
  }

  Future<void> _onInsertBlock(InsertBlock event, Emitter<EditorState> emit) async {
    try {
      final newBlock = await _editorService.createBlock(
        noteId: event.noteId,
        blockType: event.blockType,
        content: event.content,
        position: event.position,
      );
      final state = this.state;
      if (state is EditorLoaded) {
        final blocks = List<BlockModel>.from(state.blocks);
        blocks.insert(event.position, newBlock);
        for (var i = event.position + 1; i < blocks.length; i++) {
          blocks[i] = blocks[i].copyWith(position: i);
        }
        emit(state.copyWith(blocks: blocks, activeBlockId: newBlock.id));
      }
    } catch (e) {
      emit(EditorError(e.toString()));
    }
  }

  Future<void> _onUpdateBlock(UpdateBlock event, Emitter<EditorState> emit) async {
    try {
      await _editorService.updateBlock(blockId: event.blockId, content: event.content);
      final state = this.state;
      if (state is EditorLoaded) {
        final blocks = state.blocks.map((b) {
          if (b.id == event.blockId) {
            return b.copyWith(content: event.content);
          }
          return b;
        }).toList();
        emit(state.copyWith(blocks: blocks));
      }
    } catch (e) {
      emit(EditorError(e.toString()));
    }
  }

  Future<void> _onDeleteBlock(DeleteBlock event, Emitter<EditorState> emit) async {
    try {
      await _editorService.deleteBlock(event.blockId);
      final state = this.state;
      if (state is EditorLoaded) {
        final blocks = state.blocks.where((b) => b.id != event.blockId).toList();
        for (var i = 0; i < blocks.length; i++) {
          blocks[i] = blocks[i].copyWith(position: i);
        }
        if (blocks.isEmpty) {
          final newBlock = await _editorService.createBlock(
            noteId: state.noteId,
            blockType: BlockType.paragraph,
            content: '',
            position: 0,
          );
          emit(state.copyWith(blocks: [newBlock], activeBlockId: newBlock.id));
        } else {
          emit(state.copyWith(blocks: blocks));
        }
      }
    } catch (e) {
      emit(EditorError(e.toString()));
    }
  }

  Future<void> _onMoveBlock(MoveBlock event, Emitter<EditorState> emit) async {
    try {
      await _editorService.moveBlock(blockId: event.blockId, newPosition: event.newPosition);
      final state = this.state;
      if (state is EditorLoaded) {
        final blocks = List<BlockModel>.from(state.blocks);
        final index = blocks.indexWhere((b) => b.id == event.blockId);
        if (index != -1) {
          final block = blocks.removeAt(index);
          final insertAt = event.newPosition.clamp(0, blocks.length);
          blocks.insert(insertAt, block);
          for (var i = 0; i < blocks.length; i++) {
            blocks[i] = blocks[i].copyWith(position: i);
          }
        }
        emit(state.copyWith(blocks: blocks));
      }
    } catch (e) {
      emit(EditorError(e.toString()));
    }
  }

  Future<void> _onToggleBlockType(ToggleBlockType event, Emitter<EditorState> emit) async {
    try {
      final state = this.state;
      if (state is EditorLoaded) {
        final blocks = state.blocks.map((b) {
          if (b.id == event.blockId) {
            return b.copyWith(blockType: event.newType);
          }
          return b;
        }).toList();
        emit(state.copyWith(blocks: blocks));
      }
    } catch (e) {
      emit(EditorError(e.toString()));
    }
  }
}
