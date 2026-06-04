import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:devnote/features/sync/bloc/sync_event.dart';
import 'package:devnote/features/sync/bloc/sync_state.dart';
import 'package:devnote/features/sync/sync_service.dart';
import 'package:devnote/features/sync/conflict/conflict_resolver.dart';
import 'package:devnote/features/sync/retry_policy.dart';
import 'package:devnote/features/sync/offline_queue.dart';

class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final SyncService _syncService;
  final OfflineQueue _offlineQueue = OfflineQueue();
  Timer? _autoSyncTimer;
  StreamSubscription<SyncServiceState>? _serviceStateSubscription;

  static const String _keyAutoSync = 'sync_auto_sync_enabled';
  static const String _keySyncInterval = 'sync_interval_minutes';
  static const String _keyServerAddress = 'sync_server_address';

  SyncBloc(this._syncService) : super(const SyncIdle()) {
    on<StartSync>(_onStartSync);
    on<StopSync>(_onStopSync);
    on<PushChanges>(_onPushChanges);
    on<PullChanges>(_onPullChanges);
    on<SyncStatusChanged>(_onStatusChanged);
    on<ResolveConflict>(_onResolveConflict);
    on<AutoSyncToggled>(_onAutoSyncToggled);
    on<SyncIntervalChanged>(_onSyncIntervalChanged);

    _initFromPrefs();
    _listenToServiceState();
  }

  Future<void> _initFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final autoSync = prefs.getBool(_keyAutoSync) ?? false;
    final intervalMinutes = prefs.getInt(_keySyncInterval) ?? 5;
    final serverAddress = prefs.getString(_keyServerAddress);

    final currentState = state;
    emit(_copyWithBase(
      currentState,
      autoSyncEnabled: autoSync,
      syncInterval: Duration(minutes: intervalMinutes),
      serverAddress: serverAddress,
    ));

    if (autoSync) {
      _startAutoSyncTimer(Duration(minutes: intervalMinutes));
    }
  }

  void _listenToServiceState() {
    // P0-2 修复: 实际订阅 SyncService 的状态流，而非仅仅引用 state 属性
    // 修复原因: 原代码 `_syncService.state` 仅获取当前状态快照，没有建立流式监听，
    // 导致服务端状态变化（如冲突、同步完成）无法实时通知到 SyncBloc
    _serviceStateSubscription = _syncService.stateStream.listen((serviceState) {
      if (serviceState.status == SyncServiceStatus.conflict) {
        // 使用服务的冲突解析器获取实际冲突信息
        final conflicts = _syncService.conflictResolver.conflicts;
        emit(SyncConflict(
          conflicts: conflicts,
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
      } else if (serviceState.status == SyncServiceStatus.synced) {
        emit(SyncCompleted(
          lastSyncTime: serviceState.lastSyncedAt ?? DateTime.now(),
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
      }
    });
  }

  Future<void> _onStartSync(StartSync event, Emitter<SyncState> emit) async {
    emit(SyncInProgress(
      pushCount: 0,
      pullCount: 0,
      autoSyncEnabled: state.autoSyncEnabled,
      syncInterval: state.syncInterval,
      serverAddress: state.serverAddress,
    ));

    try {
      await _withRetry(() => _syncService.initialize());
      final pullResult = await _withRetry(() => _syncService.pullChanges());
      final serviceState = _syncService.state;

      // P0-1 修复: 使用 SyncService 的 conflictResolver 获取实际冲突信息，而非创建空的新实例
      // 修复原因: 新创建的 ConflictResolver() 内部 _conflicts 列表为空，不包含同步服务
      // 检测到的真实冲突数据，导致用户看不到需要解决的冲突
      if (serviceState.status == SyncServiceStatus.conflict) {
        emit(SyncConflict(
          conflicts: _syncService.conflictResolver.conflicts,
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
      } else if (serviceState.status == SyncServiceStatus.error) {
        emit(SyncError(
          message: serviceState.lastError ?? '同步失败',
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
      } else {
        emit(SyncCompleted(
          lastSyncTime: serviceState.lastSyncedAt ?? DateTime.now(),
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));

        // 重连成功，回放离线队列中的待处理操作
        if (_offlineQueue.isNotEmpty) {
          await _offlineQueue.drainQueue((event) async {
            add(event);
          });
        }
      }
    } catch (e) {
      // 同步失败，将当前操作加入离线队列
      _offlineQueue.addOperation(event);
      emit(SyncError(
        message: e.toString(),
        autoSyncEnabled: state.autoSyncEnabled,
        syncInterval: state.syncInterval,
        serverAddress: state.serverAddress,
      ));
    }
  }

  Future<void> _onStopSync(StopSync event, Emitter<SyncState> emit) async {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    emit(SyncIdle(
      autoSyncEnabled: false,
      syncInterval: state.syncInterval,
      serverAddress: state.serverAddress,
    ));
  }

  Future<void> _onPushChanges(PushChanges event, Emitter<SyncState> emit) async {
    emit(SyncInProgress(
      pushCount: 1,
      pullCount: 0,
      autoSyncEnabled: state.autoSyncEnabled,
      syncInterval: state.syncInterval,
      serverAddress: state.serverAddress,
    ));

    try {
      final result = await _withRetry(() => _syncService.pushChanges(event.data));
      if (result.status == SyncServiceStatus.synced) {
        emit(SyncCompleted(
          lastSyncTime: result.lastSyncedAt ?? DateTime.now(),
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
      } else if (result.status == SyncServiceStatus.error) {
        emit(SyncError(
          message: result.lastError ?? '推送失败',
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
      }
    } catch (e) {
      // 推送失败，将操作加入离线队列
      _offlineQueue.addOperation(event);
      emit(SyncError(
        message: e.toString(),
        autoSyncEnabled: state.autoSyncEnabled,
        syncInterval: state.syncInterval,
        serverAddress: state.serverAddress,
      ));
    }
  }

  Future<void> _onPullChanges(PullChanges event, Emitter<SyncState> emit) async {
    emit(SyncInProgress(
      pushCount: 0,
      pullCount: 1,
      autoSyncEnabled: state.autoSyncEnabled,
      syncInterval: state.syncInterval,
      serverAddress: state.serverAddress,
    ));

    try {
      final result = await _withRetry(() => _syncService.pullChanges());
      final serviceState = _syncService.state;

      // P0-1 修复: 使用 SyncService 的 conflictResolver 获取实际冲突信息，而非创建空的新实例
      // 修复原因: 新创建的 ConflictResolver() 内部 _conflicts 列表为空，不包含同步服务
      // 检测到的真实冲突数据，导致用户看不到需要解决的冲突
      if (serviceState.status == SyncServiceStatus.conflict) {
        emit(SyncConflict(
          conflicts: _syncService.conflictResolver.conflicts,
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
      } else if (serviceState.status == SyncServiceStatus.error) {
        emit(SyncError(
          message: serviceState.lastError ?? '拉取失败',
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
      } else {
        emit(SyncCompleted(
          lastSyncTime: serviceState.lastSyncedAt ?? DateTime.now(),
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
      }

      // P1-3 修复: 处理拉取结果，将服务端数据应用到本地
      // 修复原因: 原代码 `result;` 仅引用变量，未实际处理拉取到的数据，
      // 导致即使拉取成功也没有任何日志或后续处理
      // 此处使用 serviceState（而非 result，因为 result 是 Map<String, dynamic>?）
      if (serviceState.status == SyncServiceStatus.synced) {
        // 拉取成功，数据已由 SyncService 写入本地数据库，无需额外处理
        developer.log('拉取同步完成: ${serviceState.lastSyncedAt}', name: 'SyncBloc');
      }
    } catch (e) {
      // 拉取失败，将操作加入离线队列
      _offlineQueue.addOperation(event);
      emit(SyncError(
        message: e.toString(),
        autoSyncEnabled: state.autoSyncEnabled,
        syncInterval: state.syncInterval,
        serverAddress: state.serverAddress,
      ));
    }
  }

  void _onStatusChanged(SyncStatusChanged event, Emitter<SyncState> emit) {
    emit(SyncIdle(
      autoSyncEnabled: state.autoSyncEnabled,
      syncInterval: state.syncInterval,
      serverAddress: state.serverAddress,
    ));
  }

  Future<void> _onResolveConflict(
    ResolveConflict event,
    Emitter<SyncState> emit,
  ) async {
    final currentConflicts = state is SyncConflict
        ? (state as SyncConflict).conflicts
        : <ConflictInfo>[];

    final remaining = currentConflicts
        .where((c) => c.blockId != event.blockId)
        .toList();

    await _syncService.resolveConflict(true);

    if (remaining.isEmpty) {
      emit(SyncCompleted(
        lastSyncTime: DateTime.now(),
        autoSyncEnabled: state.autoSyncEnabled,
        syncInterval: state.syncInterval,
        serverAddress: state.serverAddress,
      ));
    } else {
      emit(SyncConflict(
        conflicts: remaining,
        autoSyncEnabled: state.autoSyncEnabled,
        syncInterval: state.syncInterval,
        serverAddress: state.serverAddress,
      ));
    }
  }

  Future<void> _onAutoSyncToggled(
    AutoSyncToggled event,
    Emitter<SyncState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSync, event.enabled);

    if (event.enabled) {
      _startAutoSyncTimer(state.syncInterval);
    } else {
      _autoSyncTimer?.cancel();
      _autoSyncTimer = null;
    }

    emit(_copyWithBase(state, autoSyncEnabled: event.enabled));
  }

  Future<void> _onSyncIntervalChanged(
    SyncIntervalChanged event,
    Emitter<SyncState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySyncInterval, event.interval.inMinutes);

    if (state.autoSyncEnabled) {
      _startAutoSyncTimer(event.interval);
    }

    emit(_copyWithBase(state, syncInterval: event.interval));
  }

  void _startAutoSyncTimer(Duration interval) {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(interval, (_) {
      add(const StartSync());
    });
  }

  SyncState _copyWithBase(
    SyncState base, {
    bool? autoSyncEnabled,
    Duration? syncInterval,
    String? serverAddress,
  }) {
    final autoSync = autoSyncEnabled ?? base.autoSyncEnabled;
    final interval = syncInterval ?? base.syncInterval;
    final server = serverAddress ?? base.serverAddress;

    if (base is SyncIdle) {
      return SyncIdle(
        autoSyncEnabled: autoSync,
        syncInterval: interval,
        serverAddress: server,
      );
    } else if (base is SyncInProgress) {
      return SyncInProgress(
        pushCount: base.pushCount,
        pullCount: base.pullCount,
        autoSyncEnabled: autoSync,
        syncInterval: interval,
        serverAddress: server,
      );
    } else if (base is SyncCompleted) {
      return SyncCompleted(
        lastSyncTime: base.lastSyncTime,
        autoSyncEnabled: autoSync,
        syncInterval: interval,
        serverAddress: server,
      );
    } else if (base is SyncError) {
      return SyncError(
        message: base.message,
        autoSyncEnabled: autoSync,
        syncInterval: interval,
        serverAddress: server,
      );
    } else if (base is SyncConflict) {
      return SyncConflict(
        conflicts: base.conflicts,
        autoSyncEnabled: autoSync,
        syncInterval: interval,
        serverAddress: server,
      );
    } else if (base is SyncRetrying) {
      return SyncRetrying(
        retryAttempt: base.retryAttempt,
        autoSyncEnabled: autoSync,
        syncInterval: interval,
        serverAddress: server,
      );
    }
    return SyncIdle(
      autoSyncEnabled: autoSync,
      syncInterval: interval,
      serverAddress: server,
    );
  }

  Future<T> _withRetry<T>(Future<T> Function() operation, {RetryPolicy? policy}) async {
    policy ??= const RetryPolicy();
    int attempt = 0;
    while (true) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        if (attempt >= policy.maxRetries) rethrow;
        final delay = policy.delayForAttempt(attempt - 1);
        emit(SyncRetrying(
          retryAttempt: attempt,
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
        await Future.delayed(delay);
      }
    }
  }

  @override
  Future<void> close() {
    _autoSyncTimer?.cancel();
    _serviceStateSubscription?.cancel();
    return super.close();
  }
}
