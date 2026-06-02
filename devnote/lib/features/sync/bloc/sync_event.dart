import 'package:equatable/equatable.dart';
import 'package:devnote/features/sync/conflict/conflict_resolver.dart';

abstract class SyncEvent extends Equatable {
  const SyncEvent();

  @override
  List<Object?> get props => [];
}

class StartSync extends SyncEvent {
  const StartSync();
}

class StopSync extends SyncEvent {
  const StopSync();
}

class PushChanges extends SyncEvent {
  final Map<String, dynamic> data;

  const PushChanges(this.data);

  @override
  List<Object?> get props => [data];
}

class PullChanges extends SyncEvent {
  const PullChanges();
}

class SyncStatusChanged extends SyncEvent {
  final SyncStatusInfo statusInfo;

  const SyncStatusChanged(this.statusInfo);

  @override
  List<Object?> get props => [statusInfo];
}

class ResolveConflict extends SyncEvent {
  final String blockId;
  final String resolvedContent;

  const ResolveConflict({required this.blockId, required this.resolvedContent});

  @override
  List<Object?> get props => [blockId, resolvedContent];
}

class AutoSyncToggled extends SyncEvent {
  final bool enabled;

  const AutoSyncToggled(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

class SyncIntervalChanged extends SyncEvent {
  final Duration interval;

  const SyncIntervalChanged(this.interval);

  @override
  List<Object?> get props => [interval];
}

class SyncStatusInfo extends Equatable {
  final String label;
  final bool isActive;

  const SyncStatusInfo({required this.label, required this.isActive});

  @override
  List<Object?> get props => [label, isActive];
}
