import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:devnote/features/sync/bloc/sync_event.dart';
import 'package:devnote/features/sync/bloc/sync_state.dart';
import 'package:devnote/features/sync/sync_service.dart';
import 'package:devnote/features/sync/conflict/conflict_resolver.dart';
import 'package:devnote/features/sync/retry_policy.dart';

class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final SyncService _syncService;
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
    _syncService.state;
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

      if (serviceState.status == SyncServiceStatus.conflict) {
        final resolver = ConflictResolver();
        emit(SyncConflict(
          conflicts: resolver.conflicts,
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
      }
    } catch (e) {
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

      if (serviceState.status == SyncServiceStatus.conflict) {
        final resolver = ConflictResolver();
        emit(SyncConflict(
          conflicts: resolver.conflicts,
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

      result;
    } catch (e) {
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
