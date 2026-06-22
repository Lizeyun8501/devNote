import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/core/observability/app_logger.dart';
import 'package:devnote/features/editor/bloc/editor_event.dart';
import 'package:devnote/features/editor/bloc/editor_state.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import 'package:devnote/features/editor/models/timeline_marker.dart';
import 'package:devnote/features/editor/services/editor_service.dart';
import 'package:devnote/features/editor/services/timeline_recorder_service.dart';
import 'package:devnote/features/sync/conflict/conflict_resolver.dart';
import 'package:devnote/features/sync/realtime/realtime_collab_service.dart';

/// 编辑器业务逻辑组件 (EditorBloc)
/// 管理笔记的 block 级别编辑操作：加载、插入、更新、删除、移动、撤销/重做、选中
/// 借鉴思源笔记风格：本地优先持久化，block 粒度编辑，支持历史记录
///
/// 实时协作集成：
/// - 本地编辑操作时通过 RealtimeCollabService 广播 CollabOperation
/// - 监听 incomingOperations 流，应用远端操作（复用 ConflictResolver 的
///   VectorClock 合并逻辑）
/// - 远端操作应用时不再次广播，避免回环
class EditorBloc extends Bloc<EditorEvent, EditorState> {
  final EditorService _editorService;

  /// 实时协作服务（可选注入，未注入时退化为单机编辑）
  final RealtimeCollabService? _collabService;

  /// 时间轴录音服务（可选注入，未注入时时间轴录音功能不可用）
  final TimelineRecorderService? _timelineRecorderService;

  /// 当前时间轴录音的音频文件路径（开始录音时捕获，停止时用于写入 content JSON）
  String? _timelineAudioPath;

  /// 冲突解决器（复用现有 VectorClock 合并逻辑）
  final ConflictResolver _conflictResolver = ConflictResolver();

  /// 远端操作流订阅
  StreamSubscription<CollabOperation>? _remoteOpSubscription;

  /// 标记当前是否正在应用远端操作（避免远端操作触发本地广播回环）
  bool _applyingRemoteOperation = false;

  EditorBloc(
    this._editorService, {
    RealtimeCollabService? collabService,
    TimelineRecorderService? timelineRecorderService,
  })  : _collabService = collabService,
        _timelineRecorderService = timelineRecorderService,
        super(const EditorInitial()) {
    on<LoadNote>(_onLoadNote);
    on<InsertBlock>(_onInsertBlock);
    on<UpdateBlock>(_onUpdateBlock);
    on<DeleteBlock>(_onDeleteBlock);
    on<MoveBlock>(_onMoveBlock);
    on<ToggleBlockType>(_onToggleBlockType);
    on<UndoEvent>(_onUndo);
    on<RedoEvent>(_onRedo);
    on<SelectBlock>(_onSelectBlock);
    on<RestoreContent>(_onRestoreContent);

    // 时间轴录音相关事件
    on<StartTimelineRecording>(_onStartTimelineRecording);
    on<StopTimelineRecording>(_onStopTimelineRecording);
    on<CancelTimelineRecording>(_onCancelTimelineRecording);
    on<MarkTimelineBlock>(_onMarkTimelineBlock);
    on<SeekToTimelineMarker>(_onSeekToTimelineMarker);

    // 订阅远端操作流（若注入了协作服务）
    _subscribeToRemoteOperations();
  }

  /// 订阅远端操作流
  ///
  /// 借鉴 SyncBloc 的事件驱动模式：监听器中通过 add 转发，避免直接 emit。
  void _subscribeToRemoteOperations() {
    final service = _collabService;
    if (service == null) return;
    _remoteOpSubscription = service.incomingOperations.listen((op) {
      // 通过 add 转发为内部事件，确保在 BLoC 事件循环中处理
      add(_RemoteOperationReceived(op));
    });
    on<_RemoteOperationReceived>(_onRemoteOperation);
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
        emit(EditorLoaded(noteId: event.noteId, blocks: [defaultBlock]));
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
      final state = this.state;
      if (state is EditorLoaded) {
        final blocks = List<BlockModel>.from(state.blocks);
        final insertAt = event.position.clamp(0, blocks.length);
        // 修复：更新 newBlock 的 position 为实际插入位置 insertAt
        // 原代码 newBlock.position 保留为 event.position，
        // 当 event.position 被 clamp 截断时（超出数组长度），
        // newBlock.position 与列表索引不一致
        blocks.insert(insertAt, newBlock.copyWith(position: insertAt));
        for (var i = insertAt + 1; i < blocks.length; i++) {
          blocks[i] = blocks[i].copyWith(position: i);
        }

        // 时间轴录音中：为新建的文本块记录一个时间轴标记
        // 仅在插入新块时标记（每个块对应一个时间点），避免逐字符标记导致标记泛滥
        List<TimelineMarker> updatedMarkers = state.timelineMarkers;
        if (state.isTimelineRecording && _timelineRecorderService != null) {
          _timelineRecorderService!.markBlock(newBlock.id);
          updatedMarkers = _timelineRecorderService!.markers;
        }

        emit(state.pushUndo(state.blocks).copyWith(
          blocks: blocks,
          activeBlockId: newBlock.id,
          timelineMarkers: updatedMarkers,
        ));
        // 实时协作：广播 insert 操作（远端操作应用时不广播，避免回环）
        _broadcastLocalOperation(
          blockId: newBlock.id,
          opType: CollabOperationType.insert,
          payload: {
            'noteId': event.noteId,
            'blockType': event.blockType.name,
            'content': event.content,
            'position': insertAt,
          },
        );
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
        // 实时协作：广播 update 操作
        _broadcastLocalOperation(
          blockId: event.blockId,
          opType: CollabOperationType.update,
          payload: {'content': event.content},
        );
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
          emit(state.pushUndo(state.blocks).copyWith(blocks: [newBlock], activeBlockId: newBlock.id));
        } else {
          emit(state.pushUndo(state.blocks).copyWith(blocks: blocks));
        }
        // 实时协作：广播 delete 操作
        _broadcastLocalOperation(
          blockId: event.blockId,
          opType: CollabOperationType.delete,
          payload: const <String, dynamic>{},
        );
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
        // 实时协作：广播 move 操作
        _broadcastLocalOperation(
          blockId: event.blockId,
          opType: CollabOperationType.move,
          payload: {'newPosition': event.newPosition},
        );
      }
    } catch (e) {
      emit(EditorError(e.toString()));
    }
  }

  /// 切换 block 类型
  /// 例如：paragraph → heading、heading → bullet_list 等
  /// 同时将类型变更持久化到 SQLite
  Future<void> _onToggleBlockType(ToggleBlockType event, Emitter<EditorState> emit) async {
    try {
      final state = this.state;
      if (state is EditorLoaded) {
        // 持久化 block_type 变更到 SQLite
        await _editorService.updateBlockType(blockId: event.blockId, newType: event.newType);
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

  /// 恢复笔记内容到指定版本
  /// 将版本历史中的纯文本内容解析为 blocks 并替换当前所有 blocks
  /// （EditorService.parseMarkdown 内部会清空旧 blocks 并持久化新 blocks）
  Future<void> _onRestoreContent(RestoreContent event, Emitter<EditorState> emit) async {
    try {
      final state = this.state;
      if (state is! EditorLoaded) return;
      final blocks = await _editorService.parseMarkdown(
        content: event.content,
        noteId: state.noteId,
      );
      emit(state.pushUndo(state.blocks).copyWith(blocks: blocks));
    } catch (e) {
      emit(EditorError(e.toString()));
    }
  }

  /// 开始时间轴录音
  /// 调用 TimelineRecorderService.startRecording，捕获音频文件路径供停止时使用
  Future<void> _onStartTimelineRecording(
    StartTimelineRecording event,
    Emitter<EditorState> emit,
  ) async {
    final service = _timelineRecorderService;
    if (service == null) return;
    final state = this.state;
    if (state is! EditorLoaded) return;

    try {
      _timelineAudioPath = await service.startRecording(event.audioBlockId);
      emit(state.copyWith(
        isTimelineRecording: true,
        currentAudioBlockId: event.audioBlockId,
        timelineMarkers: const [],
      ));
    } catch (e) {
      emit(EditorError(e.toString()));
    }
  }

  /// 停止时间轴录音
  /// 将 markers 序列化后写入新建 audio block 的 content JSON：
  /// {url, duration_ms, transcript, markers: [...]}
  Future<void> _onStopTimelineRecording(
    StopTimelineRecording event,
    Emitter<EditorState> emit,
  ) async {
    final service = _timelineRecorderService;
    if (service == null) return;
    final state = this.state;
    if (state is! EditorLoaded) return;

    try {
      // 在停止前捕获时长（stopRecording 不会重置 _startTime）
      final durationMs = service.currentDurationMs;
      final markers = await service.stopRecording();
      final path = _timelineAudioPath ?? '';

      final content = {
        'url': path,
        'duration_ms': durationMs,
        'transcript': '',
        'markers': markers.map((m) => m.toJson()).toList(),
      };
      final contentJson = jsonEncode(content);

      // 插入 audio block（直接调用 service，不经过 InsertBlock 事件，避免被标记）
      final newBlock = await _editorService.createBlock(
        noteId: state.noteId,
        blockType: BlockType.audio,
        content: contentJson,
        position: state.blocks.length,
      );
      final blocks = List<BlockModel>.from(state.blocks)
        ..add(newBlock.copyWith(position: state.blocks.length));

      emit(state.copyWith(
        blocks: blocks,
        isTimelineRecording: false,
        currentAudioBlockId: null,
        timelineMarkers: markers,
      ));
      _timelineAudioPath = null;
    } catch (e) {
      emit(EditorError(e.toString()));
    }
  }

  /// 取消时间轴录音
  Future<void> _onCancelTimelineRecording(
    CancelTimelineRecording event,
    Emitter<EditorState> emit,
  ) async {
    final service = _timelineRecorderService;
    if (service == null) return;
    final state = this.state;
    if (state is! EditorLoaded) return;

    await service.cancelRecording();
    _timelineAudioPath = null;
    emit(state.copyWith(
      isTimelineRecording: false,
      currentAudioBlockId: null,
      timelineMarkers: const [],
    ));
  }

  /// 为指定文本块记录时间轴标记（显式调用，用于录音中标记当前编辑位置）
  void _onMarkTimelineBlock(
    MarkTimelineBlock event,
    Emitter<EditorState> emit,
  ) {
    final service = _timelineRecorderService;
    if (service == null) return;
    final state = this.state;
    if (state is! EditorLoaded) return;

    service.markBlock(event.blockId, noteText: event.noteText);
    emit(state.copyWith(timelineMarkers: service.markers));
  }

  /// 跳转到时间轴标记对应的文本块（设置 activeBlockId，由 UI 层滚动定位）
  void _onSeekToTimelineMarker(
    SeekToTimelineMarker event,
    Emitter<EditorState> emit,
  ) {
    final state = this.state;
    if (state is! EditorLoaded) return;
    emit(state.copyWith(activeBlockId: event.blockId));
  }

  /// 广播本地操作到协作会话
  ///
  /// 仅在以下条件同时满足时广播：
  /// 1. 注入了 RealtimeCollabService
  /// 2. 当前不在应用远端操作（避免回环）
  /// 3. 当前状态为 EditorLoaded（有 noteId 上下文）
  ///
  /// 广播为异步操作，使用 unawaited 不阻塞当前事件处理。
  void _broadcastLocalOperation({
    required String blockId,
    required CollabOperationType opType,
    required Map<String, dynamic> payload,
  }) {
    if (_applyingRemoteOperation) return;
    final service = _collabService;
    if (service == null) return;
    final state = this.state;
    if (state is! EditorLoaded) return;

    try {
      // 异步广播，不阻塞当前事件处理
      unawaited(
        service
            .emitLocalOperation(
              blockId: blockId,
              opType: opType,
              payload: payload,
            )
            .then((_) {})
            .catchError((Object e) {
          AppLogger.w('EditorBloc', '广播本地操作失败: $e');
        }),
      );
    } catch (e) {
      AppLogger.w('EditorBloc', '广播本地操作同步异常: $e');
    }
  }

  /// 处理远端操作（内部事件）
  ///
  /// 复用现有 ConflictResolver 的 VectorClock 合并逻辑：
  /// 1. 调用 RealtimeCollabService.applyRemoteOperation 维护 OpLog 与向量时钟
  /// 2. 标记 _applyingRemoteOperation = true，避免本地广播回环
  /// 3. 根据 opType 调用对应的 EditorService 方法应用变更
  /// 4. 调用 ConflictResolver.mergeWithVectorClocks 进行 CRDT 合并
  /// 5. 更新本地状态并发射
  Future<void> _onRemoteOperation(
    _RemoteOperationReceived event,
    Emitter<EditorState> emit,
  ) async {
    final op = event.operation;
    final state = this.state;
    if (state is! EditorLoaded) return;

    // 忽略自己发起的操作（服务器可能回环广播）
    final service = _collabService;
    if (service == null) return;
    if (op.deviceId == service.deviceId) return;

    // 调用服务层维护 OpLog 与向量时钟（去重，返回 false 表示重复操作）
    if (!service.applyRemoteOperation(op, _conflictResolver)) {
      return;
    }

    _applyingRemoteOperation = true;
    try {
      switch (op.opType) {
        case CollabOperationType.insert:
          await _applyRemoteInsert(op, state, emit);
          break;
        case CollabOperationType.update:
          await _applyRemoteUpdate(op, state, emit);
          break;
        case CollabOperationType.delete:
          await _applyRemoteDelete(op, state, emit);
          break;
        case CollabOperationType.move:
          await _applyRemoteMove(op, state, emit);
          break;
        case CollabOperationType.cursor:
          // cursor 操作由 presence 流处理，此处不修改文档
          break;
      }
    } catch (e, st) {
      AppLogger.e('EditorBloc', '应用远端操作失败: opId=${op.opId}',
          error: e, stackTrace: st);
    } finally {
      _applyingRemoteOperation = false;
    }
  }

  /// 应用远端 insert 操作
  Future<void> _applyRemoteInsert(
    CollabOperation op,
    EditorLoaded state,
    Emitter<EditorState> emit,
  ) async {
    final payload = op.payload;
    final noteId = payload['noteId'] as String? ?? state.noteId;
    final blockTypeStr = payload['blockType'] as String? ?? 'paragraph';
    final blockType = BlockType.values.firstWhere(
      (t) => t.name == blockTypeStr,
      orElse: () => BlockType.paragraph,
    );
    final content = payload['content'] as String? ?? '';
    final position = (payload['position'] as num?)?.toInt() ?? 0;

    final newBlock = await _editorService.createBlock(
      noteId: noteId,
      blockType: blockType,
      content: content,
      position: position,
    );
    final blocks = List<BlockModel>.from(state.blocks);
    final insertAt = position.clamp(0, blocks.length);
    blocks.insert(insertAt, newBlock.copyWith(position: insertAt));
    for (var i = insertAt + 1; i < blocks.length; i++) {
      blocks[i] = blocks[i].copyWith(position: i);
    }
    emit(state.copyWith(blocks: blocks));
  }

  /// 应用远端 update 操作
  ///
  /// 复用 ConflictResolver.mergeWithVectorClocks 进行 CRDT 合并：
  /// - 若本地与远端向量时钟存在因果关系，采用较新的一方
  /// - 若并发，文本块字符级合并，非文本块 last-write-wins
  Future<void> _applyRemoteUpdate(
    CollabOperation op,
    EditorLoaded state,
    Emitter<EditorState> emit,
  ) async {
    final remoteContent = op.payload['content'] as String? ?? '';
    final localBlock = state.blocks
        .where((b) => b.id == op.blockId)
        .firstOrNull;
    if (localBlock == null) {
      // 本地不存在该 block，直接采用远端内容创建
      await _editorService.updateBlock(
        blockId: op.blockId,
        content: remoteContent,
      );
      return;
    }

    // 复用 ConflictResolver 的 VectorClock 合并逻辑
    // localClock: 服务层维护的本地向量时钟（已包含历史操作）
    // remoteClock: 远端操作携带的向量时钟
    final remoteBlock = localBlock.copyWith(
      content: remoteContent,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(op.timestamp),
    );
    final service = _collabService;
    final localClock =
        service != null ? service.localVectorClock : VectorClock();
    final remoteClock = op.vectorClock;
    final baseClock = VectorClock();

    final results = _conflictResolver.mergeWithVectorClocks(
      [localBlock],
      [remoteBlock],
      localClock,
      remoteClock,
      baseClock,
    );

    if (results.isNotEmpty) {
      final merged = results.first.block;
      await _editorService.updateBlock(
        blockId: merged.id,
        content: merged.content,
      );
      final blocks = state.blocks.map((b) {
        if (b.id == merged.id) {
          return merged;
        }
        return b;
      }).toList();
      emit(state.copyWith(blocks: blocks));
    }
  }

  /// 应用远端 delete 操作
  Future<void> _applyRemoteDelete(
    CollabOperation op,
    EditorLoaded state,
    Emitter<EditorState> emit,
  ) async {
    await _editorService.deleteBlock(op.blockId);
    final blocks = state.blocks.where((b) => b.id != op.blockId).toList();
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
      emit(state.copyWith(blocks: [newBlock], activeBlockId: newBlock.id));
    } else {
      emit(state.copyWith(blocks: blocks));
    }
  }

  /// 应用远端 move 操作
  Future<void> _applyRemoteMove(
    CollabOperation op,
    EditorLoaded state,
    Emitter<EditorState> emit,
  ) async {
    final newPosition = (op.payload['newPosition'] as num?)?.toInt() ?? 0;
    await _editorService.moveBlock(
      blockId: op.blockId,
      newPosition: newPosition,
    );
    final blocks = List<BlockModel>.from(state.blocks);
    final index = blocks.indexWhere((b) => b.id == op.blockId);
    if (index != -1) {
      final block = blocks.removeAt(index);
      final insertAt = newPosition.clamp(0, blocks.length);
      blocks.insert(insertAt, block);
      for (var i = 0; i < blocks.length; i++) {
        blocks[i] = blocks[i].copyWith(position: i);
      }
      emit(state.copyWith(blocks: blocks));
    }
  }

  @override
  Future<void> close() {
    _remoteOpSubscription?.cancel();
    return super.close();
  }
}

/// 内部事件：收到远端操作
///
/// 借鉴 SyncBloc 的 _SyncServiceStateChanged 模式：将服务流事件转发为
/// BLoC 事件，确保在事件循环中处理。
class _RemoteOperationReceived extends EditorEvent {
  final CollabOperation operation;

  const _RemoteOperationReceived(this.operation);

  @override
  List<Object?> get props => [operation];
}
