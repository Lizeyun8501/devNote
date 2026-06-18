// 实时协作 BLoC
//
// 借鉴现有 SyncBloc 的事件驱动模式（构造函数中订阅服务状态流，通过 add
// 转发为 BLoC 事件，避免在监听器中直接 emit）。
//
// 职责：
// - 将 RealtimeCollabService 的状态/操作/presence 流转换为 BLoC 状态
// - 处理 Connect / Disconnect / LocalOperationApplied / UpdateCursor 事件
// - 暴露 Connected(presences) 状态供 UI 渲染协作者光标
//
// 与 EditorBloc 的协作：
// - EditorBloc 在本地编辑后 add(LocalOperationApplied) → 本 BLoC 广播
// - 本 BLoC 收到远端操作时不直接修改编辑器，而是通过
//   RealtimeCollabService.incomingOperations 流供 EditorBloc 订阅应用

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:devnote/core/observability/app_logger.dart';
import 'package:devnote/features/sync/realtime/bloc/realtime_collab_event.dart';
import 'package:devnote/features/sync/realtime/bloc/realtime_collab_state.dart';
import 'package:devnote/features/sync/realtime/realtime_collab_service.dart';

class RealtimeCollabBloc
    extends Bloc<RealtimeCollabEvent, RealtimeCollabState> {
  RealtimeCollabBloc(this._service) : super(const RealtimeCollabInitial()) {
    on<Connect>(_onConnect);
    on<Disconnect>(_onDisconnect);
    on<LocalOperationApplied>(_onLocalOperationApplied);
    on<UpdateCursor>(_onUpdateCursor);
    on<PresenceRequested>(_onPresenceRequested);
    // 内部事件：服务状态变更
    on<_ServiceStatusChanged>(_onServiceStatusChanged);
    on<_PresenceUpdated>(_onPresenceUpdated);

    _listenToService();
  }

  final RealtimeCollabService _service;

  static const String _tag = 'RealtimeCollabBloc';

  StreamSubscription<RealtimeCollabStatus>? _statusSubscription;
  StreamSubscription<PresenceState>? _presenceSubscription;

  /// 当前会话 noteId（用于状态转换时保留上下文）
  String? _currentNoteId;

  /// 订阅服务状态流与 presence 流
  ///
  /// 借鉴 SyncBloc 的模式：监听器中通过 add 转发，避免直接 emit。
  void _listenToService() {
    _statusSubscription = _service.statusStream.listen((status) {
      add(_ServiceStatusChanged(status: status));
    });
    _presenceSubscription = _service.presenceUpdates.listen((presence) {
      add(_PresenceUpdated(presence: presence));
    });
  }

  /// 处理 Connect 事件：加入协作会话
  Future<void> _onConnect(Connect event, Emitter<RealtimeCollabState> emit) async {
    _currentNoteId = event.noteId;
    emit(RealtimeCollabConnecting(event.noteId));
    try {
      await _service.connect(event.noteId);
      // 连接成功后状态由 _ServiceStatusChanged 推进到 Connected
    } catch (e, st) {
      AppLogger.e(_tag, '加入协作会话失败', error: e, stackTrace: st);
      emit(RealtimeCollabError('加入协作会话失败: $e'));
    }
  }

  /// 处理 Disconnect 事件：离开协作会话
  Future<void> _onDisconnect(
    Disconnect event,
    Emitter<RealtimeCollabState> emit,
  ) async {
    try {
      await _service.disconnect();
    } catch (e) {
      AppLogger.w(_tag, '断开协作会话异常: $e');
    }
    _currentNoteId = null;
    emit(const RealtimeCollabDisconnected());
  }

  /// 处理本地操作已应用事件：广播给其他协作者
  Future<void> _onLocalOperationApplied(
    LocalOperationApplied event,
    Emitter<RealtimeCollabState> emit,
  ) async {
    try {
      await _service.emitLocalOperation(
        blockId: event.blockId,
        opType: event.opType,
        payload: event.payload,
      );
    } catch (e) {
      AppLogger.w(_tag, '广播本地操作失败: $e');
    }
    // 保持当前状态（Connected），仅刷新 presence 列表
    _emitCurrentWithPresences(emit);
  }

  /// 处理光标更新事件
  Future<void> _onUpdateCursor(
    UpdateCursor event,
    Emitter<RealtimeCollabState> emit,
  ) async {
    try {
      await _service.updateCursor(
        blockId: event.blockId,
        offset: event.offset,
        length: event.length,
      );
    } catch (e) {
      AppLogger.w(_tag, '更新光标失败: $e');
    }
    _emitCurrentWithPresences(emit);
  }

  /// 处理 presence 请求事件：刷新当前协作者列表
  void _onPresenceRequested(
    PresenceRequested event,
    Emitter<RealtimeCollabState> emit,
  ) {
    _emitCurrentWithPresences(emit);
  }

  /// 处理服务状态变更（内部事件）
  void _onServiceStatusChanged(
    _ServiceStatusChanged event,
    Emitter<RealtimeCollabState> emit,
  ) {
    switch (event.status) {
      case RealtimeCollabStatus.disconnected:
        emit(const RealtimeCollabDisconnected());
        break;
      case RealtimeCollabStatus.connecting:
        if (_currentNoteId != null) {
          emit(RealtimeCollabConnecting(_currentNoteId!));
        }
        break;
      case RealtimeCollabStatus.connected:
        if (_currentNoteId != null) {
          emit(RealtimeCollabConnected(
            noteId: _currentNoteId!,
            presences: _service.presences,
          ));
        }
        break;
      case RealtimeCollabStatus.reconnecting:
        if (_currentNoteId != null) {
          emit(RealtimeCollabConnecting(_currentNoteId!));
        }
        break;
      case RealtimeCollabStatus.error:
        emit(RealtimeCollabError('协作连接错误'));
        break;
    }
  }

  /// 处理 presence 更新（内部事件）
  void _onPresenceUpdated(
    _PresenceUpdated event,
    Emitter<RealtimeCollabState> emit,
  ) {
    _emitCurrentWithPresences(emit);
  }

  /// 基于当前状态发射带最新 presence 列表的状态
  void _emitCurrentWithPresences(Emitter<RealtimeCollabState> emit) {
    final state = this.state;
    if (state is RealtimeCollabConnected) {
      emit(state.copyWith(presences: _service.presences));
    }
  }

  @override
  Future<void> close() {
    _statusSubscription?.cancel();
    _presenceSubscription?.cancel();
    return super.close();
  }
}

/// 内部事件：服务状态变更
class _ServiceStatusChanged extends RealtimeCollabEvent {
  final RealtimeCollabStatus status;

  const _ServiceStatusChanged({required this.status});

  @override
  List<Object?> get props => [status];
}

/// 内部事件：presence 更新
class _PresenceUpdated extends RealtimeCollabEvent {
  final PresenceState presence;

  const _PresenceUpdated({required this.presence});

  @override
  List<Object?> get props => [presence];
}
