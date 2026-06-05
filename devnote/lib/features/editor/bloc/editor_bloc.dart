import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/editor/bloc/editor_event.dart';
import 'package:devnote/features/editor/bloc/editor_state.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import 'package:devnote/features/editor/services/editor_service.dart';

/// 编辑器业务逻辑组件 (EditorBloc)
/// 管理笔记的 block 级别编辑操作：加载、插入、更新、删除、移动、撤销/重做、选中
/// 借鉴思源笔记风格：本地优先持久化，block 粒度编辑，支持历史记录
class EditorBloc extends Bloc<EditorEvent, EditorState> {
  final EditorService _editorService;

  EditorBloc(this._editorService) : super(const EditorInitial()) {
    on<LoadNote>(_onLoadNote);
    on<InsertBlock>(_onInsertBlock);
    on<UpdateBlock>(_onUpdateBlock);
    on<DeleteBlock>(_onDeleteBlock);
    on<MoveBlock>(_onMoveBlock);
    on<ToggleBlockType>(_onToggleBlockType);
    on<UndoEvent>(_onUndo);
    on<RedoEvent>(_onRedo);
    on<SelectBlock>(_onSelectBlock);
  }

  /// 加载笔记
  /// 优先从 SQLite 本地加载 block 数据（思源笔记风格：本地优先持久化）
  /// 加载失败时使用降级策略：创建默认空白段落 block 保证编辑器可用
  /// 空笔记自动创建默认段落
  Future<void> _onLoadNote(LoadNote event, Emitter<EditorState> emit) async {
    emit(const EditorLoading());
    try {
      // 打开笔记时先从 SQLite 加载 block 数据到内存缓存（思源笔记风格：本地优先持久化）
      await _editorService.loadBlocks(event.noteId);
      final blocks = await _editorService.listBlocks(event.noteId);
      if (blocks.isEmpty) {
        // 空笔记：自动创建默认段落
        final newBlock = await _editorService.createBlock(
          noteId: event.noteId,
          blockType: BlockType.paragraph,
          content: '',
          position: 0,
        );
        if (newBlock == null) {
          emit(const EditorError('创建默认块失败'));
          return;
        }
        emit(EditorLoaded(noteId: event.noteId, blocks: [newBlock]));
      } else {
        emit(EditorLoaded(noteId: event.noteId, blocks: blocks));
      }
    } catch (e) {
      // 降级策略：加载失败时创建默认空白笔记，确保编辑器仍可用
      try {
        final defaultBlock = await _editorService.createBlock(
          noteId: event.noteId,
          blockType: BlockType.paragraph,
          content: '',
          position: 0,
        );
        if (defaultBlock != null) {
          emit(EditorLoaded(noteId: event.noteId, blocks: [defaultBlock]));
        } else {
          emit(EditorError('加载笔记失败: ${e.toString()}'));
        }
      } catch (_) {
        emit(EditorError('加载笔记失败: ${e.toString()}'));
      }
    }
  }

  /// 插入新 block
  /// 在指定位置创建新 block，后续 block 自动调整位置
  /// 创建失败时保留原有 block 列表，不破坏编辑器状态
  Future<void> _onInsertBlock(InsertBlock event, Emitter<EditorState> emit) async {
    try {
      final newBlock = await _editorService.createBlock(
        noteId: event.noteId,
        blockType: event.blockType,
        content: event.content,
        position: event.position,
      );
      // 错误处理：block 创建失败时中止操作，保留原有状态
      if (newBlock == null) {
        emit(const EditorError('创建块失败'));
        return;
      }
      final state = this.state;
      if (state is EditorLoaded) {
        final blocks = List<BlockModel>.from(state.blocks);
        final insertAt = event.position.clamp(0, blocks.length);
        blocks.insert(insertAt, newBlock);
        for (var i = insertAt + 1; i < blocks.length; i++) {
          blocks[i] = blocks[i].copyWith(position: i);
        }
        emit(state.pushUndo(state.blocks).copyWith(blocks: blocks, activeBlockId: newBlock.id));
      }
    } catch (e) {
      emit(EditorError(e.toString()));
    }
  }

  /// 更新 block 内容
  /// 修改指定 block 的文本内容，操作前保存历史记录用于撤销
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
        emit(state.pushUndo(state.blocks).copyWith(blocks: blocks));
      }
    } catch (e) {
      emit(EditorError(e.toString()));
    }
  }

  /// 删除 block
  /// 删除指定 block，自动调整后续 block 位置
  /// 删除后若为空列表，自动创建默认空段落 block
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
          // 空列表：自动创建默认段落，保证编辑器始终有内容
          final newBlock = await _editorService.createBlock(
            noteId: state.noteId,
            blockType: BlockType.paragraph,
            content: '',
            position: 0,
          );
          if (newBlock == null) {
            emit(const EditorError('创建默认块失败'));
            return;
          }
          emit(state.pushUndo(state.blocks).copyWith(blocks: [newBlock], activeBlockId: newBlock.id));
        } else {
          emit(state.pushUndo(state.blocks).copyWith(blocks: blocks));
        }
      }
    } catch (e) {
      emit(EditorError(e.toString()));
    }
  }

  /// 移动 block
  /// 将指定 block 移动到新位置，自动调整所有受影响 block 的位置
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
        emit(state.pushUndo(state.blocks).copyWith(blocks: blocks));
      }
    } catch (e) {
      emit(EditorError(e.toString()));
    }
  }

  /// 切换 block 类型
  /// 例如：paragraph → heading、heading → bullet_list 等
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
        emit(state.pushUndo(state.blocks).copyWith(blocks: blocks));
      }
    } catch (e) {
      emit(EditorError(e.toString()));
    }
  }

  /// 撤销操作
  void _onUndo(UndoEvent event, Emitter<EditorState> emit) {
    final state = this.state;
    if (state is EditorLoaded) {
      emit(state.undo(state.blocks));
    }
  }

  /// 重做操作
  void _onRedo(RedoEvent event, Emitter<EditorState> emit) {
    final state = this.state;
    if (state is EditorLoaded) {
      emit(state.redo(state.blocks));
    }
  }

  /// 选中 block
  void _onSelectBlock(SelectBlock event, Emitter<EditorState> emit) {
    final state = this.state;
    if (state is EditorLoaded) {
      emit(state.copyWith(activeBlockId: event.blockId));
    }
  }
}
