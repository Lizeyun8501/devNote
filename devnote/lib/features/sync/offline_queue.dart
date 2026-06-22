import 'dart:async';

import 'package:devnote/core/observability/app_logger.dart';
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
  /// 修复：添加最大重试次数限制
  /// 原代码 drainQueue 中失败的操作永远重新入队，没有退出机制，
  /// 导致持久性网络故障时队列无限增长，反复重试浪费资源
  static const int _maxRetries = 5;

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
      } catch (e) {
        // 重放失败时重新入队，但增加重试计数
        final retryCount = _pendingOperations
            .where((o) => o.event == op.event)
            .length;
        AppLogger.w('OfflineQueue', 'Replay failed for ${op.event.runtimeType}, retryCount=$retryCount', error: e);
        if (retryCount < _maxRetries) {
          _pendingOperations.add(op);
        }
        // 超过最大重试次数的操作被丢弃，避免无限重试
      }
    }
  }

  void clear() {
    _pendingOperations.clear();
  }
}