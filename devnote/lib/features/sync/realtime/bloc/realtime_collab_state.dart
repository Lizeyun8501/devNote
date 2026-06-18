// 实时协作 BLoC 状态定义
//
// 借鉴现有 SyncState 的 sealed class 风格，与 RealtimeCollabStatus 对齐
// 但携带业务语义（如 Connected 携带在线协作者列表）。

import 'package:devnote/features/sync/realtime/realtime_collab_service.dart';

sealed class RealtimeCollabState {
  const RealtimeCollabState();
}

/// 初始状态（未连接）
final class RealtimeCollabInitial extends RealtimeCollabState {
  const RealtimeCollabInitial();
}

/// 正在连接协作会话
final class RealtimeCollabConnecting extends RealtimeCollabState {
  final String noteId;

  const RealtimeCollabConnecting(this.noteId);
}

/// 已连接协作会话，携带当前在线协作者列表
final class RealtimeCollabConnected extends RealtimeCollabState {
  final String noteId;

  /// 当前在线协作者列表（不含自己）
  final List<PresenceState> presences;

  const RealtimeCollabConnected({
    required this.noteId,
    this.presences = const [],
  });

  RealtimeCollabConnected copyWith({
    String? noteId,
    List<PresenceState>? presences,
  }) {
    return RealtimeCollabConnected(
      noteId: noteId ?? this.noteId,
      presences: presences ?? this.presences,
    );
  }
}

/// 已断开协作会话
final class RealtimeCollabDisconnected extends RealtimeCollabState {
  const RealtimeCollabDisconnected();
}

/// 协作会话错误
final class RealtimeCollabError extends RealtimeCollabState {
  final String message;

  const RealtimeCollabError(this.message);
}
