// 实时协作 BLoC 事件定义
//
// 借鉴现有 SyncBloc 的事件划分风格（Equatable + 具名事件类），
// 与 EditorBloc 解耦：EditorBloc 通过 add(LocalOperationApplied) 通知
// RealtimeCollabBloc 广播操作，RealtimeCollabBloc 通过状态变更通知 UI。

import 'package:equatable/equatable.dart';

import 'package:devnote/features/sync/realtime/realtime_collab_service.dart';

abstract class RealtimeCollabEvent extends Equatable {
  const RealtimeCollabEvent();

  @override
  List<Object?> get props => [];
}

/// 加入笔记协作会话
class Connect extends RealtimeCollabEvent {
  final String noteId;

  const Connect(this.noteId);

  @override
  List<Object?> get props => [noteId];
}

/// 离开当前协作会话
class Disconnect extends RealtimeCollabEvent {
  const Disconnect();
}

/// 本地操作已应用，请求广播给其他协作者
class LocalOperationApplied extends RealtimeCollabEvent {
  /// 目标 block ID
  final String blockId;

  /// 操作类型
  final CollabOperationType opType;

  /// 操作负载（如 update 时为 {"content": "..."}，move 时为 {"newPosition": 1}）
  final Map<String, dynamic> payload;

  const LocalOperationApplied({
    required this.blockId,
    required this.opType,
    required this.payload,
  });

  @override
  List<Object?> get props => [blockId, opType, payload];
}

/// 更新本地光标并广播
class UpdateCursor extends RealtimeCollabEvent {
  final String blockId;
  final int offset;
  final int length;

  const UpdateCursor({
    required this.blockId,
    required this.offset,
    this.length = 0,
  });

  @override
  List<Object?> get props => [blockId, offset, length];
}

/// 请求当前在线协作者列表（presence）
class PresenceRequested extends RealtimeCollabEvent {
  const PresenceRequested();
}
