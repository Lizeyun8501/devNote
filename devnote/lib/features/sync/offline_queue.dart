import 'dart:async';

import 'package:devnote/features/sync/bloc/sync_event.dart';

class OfflineOperation {
  final SyncEvent event;
  final DateTime timestamp;

  const OfflineOperation({
    required this.event,
    required this.timestamp,
  });
}

class OfflineQueue {
  final List<OfflineOperation> _pendingOperations = [];

  List<OfflineOperation> get pendingOperations =>
      List.unmodifiable(_pendingOperations);

  int get length => _pendingOperations.length;

  bool get isEmpty => _pendingOperations.isEmpty;

  bool get isNotEmpty => _pendingOperations.isNotEmpty;

  void addOperation(SyncEvent event) {
    _pendingOperations.add(OfflineOperation(
      event: event,
      timestamp: DateTime.now(),
    ));
  }

  Future<void> drainQueue(
    Future<void> Function(SyncEvent event) replayFn,
  ) async {
    final operations = List<OfflineOperation>.from(_pendingOperations);
    _pendingOperations.clear();

    for (final op in operations) {
      try {
        await replayFn(op.event);
      } catch (_) {
        // 重放失败时重新入队，保留待重试
        _pendingOperations.add(op);
      }
    }
  }

  void clear() {
    _pendingOperations.clear();
  }
}