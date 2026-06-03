import 'package:equatable/equatable.dart';
import 'package:devnote/features/sync/conflict/conflict_resolver.dart';

abstract class SyncState extends Equatable {
  final bool autoSyncEnabled;
  final Duration syncInterval;
  final String? serverAddress;

  const SyncState({
    this.autoSyncEnabled = false,
    this.syncInterval = const Duration(minutes: 5),
    this.serverAddress,
  });

  @override
  List<Object?> get props => [autoSyncEnabled, syncInterval, serverAddress];
}

class SyncIdle extends SyncState {
  const SyncIdle({
    super.autoSyncEnabled,
    super.syncInterval,
    super.serverAddress,
  });
}

class SyncInProgress extends SyncState {
  final int pushCount;
  final int pullCount;

  const SyncInProgress({
    this.pushCount = 0,
    this.pullCount = 0,
    super.autoSyncEnabled,
    super.syncInterval,
    super.serverAddress,
  });

  @override
  List<Object?> get props => [pushCount, pullCount, ...super.props];
}

class SyncCompleted extends SyncState {
  final DateTime lastSyncTime;

  const SyncCompleted({
    required this.lastSyncTime,
    super.autoSyncEnabled,
    super.syncInterval,
    super.serverAddress,
  });

  @override
  List<Object?> get props => [lastSyncTime, ...super.props];
}

class SyncError extends SyncState {
  final String message;

  const SyncError({
    required this.message,
    super.autoSyncEnabled,
    super.syncInterval,
    super.serverAddress,
  });

  @override
  List<Object?> get props => [message, ...super.props];
}

class SyncConflict extends SyncState {
  final List<ConflictInfo> conflicts;

  const SyncConflict({
    required this.conflicts,
    super.autoSyncEnabled,
    super.syncInterval,
    super.serverAddress,
  });

  @override
  List<Object?> get props => [conflicts, ...super.props];
}

class SyncRetrying extends SyncState {
  final int retryAttempt;

  const SyncRetrying({
    required this.retryAttempt,
    super.autoSyncEnabled,
    super.syncInterval,
    super.serverAddress,
  });

  @override
  List<Object?> get props => [retryAttempt, ...super.props];
}
