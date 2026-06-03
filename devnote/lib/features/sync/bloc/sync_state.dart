import 'package:devnote/features/sync/conflict/conflict_resolver.dart';

sealed class SyncState {
  final bool autoSyncEnabled;
  final Duration syncInterval;
  final String? serverAddress;

  const SyncState({
    this.autoSyncEnabled = false,
    this.syncInterval = const Duration(minutes: 5),
    this.serverAddress,
  });
}

final class SyncIdle extends SyncState {
  const SyncIdle({
    super.autoSyncEnabled,
    super.syncInterval,
    super.serverAddress,
  });
}

final class SyncInProgress extends SyncState {
  final int pushCount;
  final int pullCount;

  const SyncInProgress({
    this.pushCount = 0,
    this.pullCount = 0,
    super.autoSyncEnabled,
    super.syncInterval,
    super.serverAddress,
  });
}

final class SyncCompleted extends SyncState {
  final DateTime lastSyncTime;

  const SyncCompleted({
    required this.lastSyncTime,
    super.autoSyncEnabled,
    super.syncInterval,
    super.serverAddress,
  });
}

final class SyncError extends SyncState {
  final String message;

  const SyncError({
    required this.message,
    super.autoSyncEnabled,
    super.syncInterval,
    super.serverAddress,
  });
}

final class SyncConflict extends SyncState {
  final List<ConflictInfo> conflicts;

  const SyncConflict({
    required this.conflicts,
    super.autoSyncEnabled,
    super.syncInterval,
    super.serverAddress,
  });
}

final class SyncRetrying extends SyncState {
  final int retryAttempt;

  const SyncRetrying({
    required this.retryAttempt,
    super.autoSyncEnabled,
    super.syncInterval,
    super.serverAddress,
  });
}
