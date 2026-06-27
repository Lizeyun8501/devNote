import 'dart:async';

import 'package:devnote/core/observability/app_logger.dart';
import 'package:devnote/features/sync/bloc/sync_event.dart';

class OfflineOperation {
  final SyncEvent event;
  final DateTime timestamp;
  /// P1 修复 (F1): 记录该操作已被重放的次数，用于限制重试。
  /// 原实现通过统计 _pendingOperations 中与 op.event 相等的条目数推断
  /// 重试次数，但 drainQueue 开头即清空队列，导致计数恒为 0，重试上限失效。
  final int retryCount;

  const OfflineOperation({
    required this.event,
    required this.timestamp,
    this.retryCount = 0,
  });

  /// 返回重试计数 +1 的新实例（保持不可变性）
  OfflineOperation withIncrementedRetry() => OfflineOperation(
        event: event,
        timestamp: timestamp,
        retryCount: retryCount + 1,
      );
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
        // P1 修复 (F1): 原实现统计 _pendingOperations 中相等条目数推断重试次数，
        // 但队列已在上方清空，计数恒为 0，重试上限形同虚设。
        // 现改为基于 op 自身的 retryCount 字段判断，并在重新入队时递增。
        final nextRetry = op.retryCount + 1;
        AppLogger.w('OfflineQueue', 'Replay failed for ${op.event.runtimeType}, retryCount=${op.retryCount}', error: e);
        if (nextRetry <= _maxRetries) {
          _pendingOperations.add(op.withIncrementedRetry());
        }
        // 超过最大重试次数的操作被丢弃，避免无限重试
      }
    }
  }

  void clear() {
    _pendingOperations.clear();
  }
}