import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:devnote/core/observability/app_logger.dart';
import 'package:devnote/features/sync/bloc/sync_event.dart';
import 'package:devnote/features/sync/bloc/sync_state.dart';
import 'package:devnote/features/sync/sync_service.dart';
import 'package:devnote/features/sync/sync_settings_service.dart';
import 'package:devnote/features/sync/conflict/conflict_resolver.dart';
import 'package:devnote/features/sync/retry_policy.dart';
import 'package:devnote/features/sync/offline_queue.dart';

/// 同步业务逻辑组件 (SyncBloc)
/// 负责管理本地与远端同步的全生命周期：初始化、推送、拉取、冲突解决、自动同步。
/// 同步流程：Initialize → Pull → (Conflict? → Resolve) → Push → Complete
/// 离线支持：网络不可用时将操作暂存到 OfflineQueue，恢复后自动回放。
class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final SyncService _syncService;
  // P1 修复 (P1-5): SharedPreferences 副作用外移到 SyncSettingsService
  final SyncSettingsService _settingsService;
  final OfflineQueue _offlineQueue = OfflineQueue();
  Timer? _autoSyncTimer;
  StreamSubscription<SyncServiceState>? _serviceStateSubscription;

  SyncBloc(this._syncService, this._settingsService) : super(const SyncIdle()) {
    on<StartSync>(_onStartSync);
    on<StopSync>(_onStopSync);
    on<PushChanges>(_onPushChanges);
    on<PullChanges>(_onPullChanges);
    on<SyncStatusChanged>(_onStatusChanged);
    on<ResolveConflict>(_onResolveConflict);
    on<AutoSyncToggled>(_onAutoSyncToggled);
    on<SyncIntervalChanged>(_onSyncIntervalChanged);
    // 修复：将构造函数中的直接 emit 改为通过事件驱动
    // BLoC 规范要求 emit 只在事件处理器中使用，构造函数中直接调用
    // 违反状态管理约定，且在某些场景下可能丢失状态
    on<_SyncPrefsLoaded>(_onPrefsLoaded);
    on<_SyncServiceStateChanged>(_onServiceStateChanged);

    _initFromPrefs();
    _listenToServiceState();
  }

  /// 从 SyncSettingsService 初始化同步配置
  /// 修复 (P1-5): 改为通过 Service 读取，避免 BLoC 直接依赖 SharedPreferences
  Future<void> _initFromPrefs() async {
    final snapshot = await _settingsService.loadAll();

    add(_SyncPrefsLoaded(
      autoSyncEnabled: snapshot.autoSyncEnabled,
      syncInterval: snapshot.syncInterval,
      serverAddress: snapshot.serverAddress,
    ));
  }

  /// 处理配置加载事件
  void _onPrefsLoaded(_SyncPrefsLoaded event, Emitter<SyncState> emit) {
    emit(_copyWithBase(
      state,
      autoSyncEnabled: event.autoSyncEnabled,
      syncInterval: event.syncInterval,
      serverAddress: event.serverAddress,
    ));

    if (event.autoSyncEnabled) {
      _startAutoSyncTimer(event.syncInterval);
    }
  }

  /// 监听 SyncService 状态流
  /// 修复：改为通过 add 事件触发，而非直接 emit
  void _listenToServiceState() {
    _serviceStateSubscription = _syncService.stateStream.listen((serviceState) {
      add(_SyncServiceStateChanged(serviceState: serviceState));
    });
  }

  /// 处理服务状态变更事件
  /// 修复(P1-5): 原实现仅处理 conflict/synced 两种状态，idle/syncing/error/offline
  /// 时不 emit 任何状态，导致 UI 卡住无法反映实际同步状态。现为所有状态添加 emit。
  void _onServiceStateChanged(_SyncServiceStateChanged event, Emitter<SyncState> emit) {
    final serviceState = event.serviceState;
    switch (serviceState.status) {
      case SyncServiceStatus.idle:
        emit(SyncIdle(
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
      case SyncServiceStatus.syncing:
        emit(SyncInProgress(
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
      case SyncServiceStatus.synced:
        emit(SyncCompleted(
          lastSyncTime: serviceState.lastSyncedAt ?? DateTime.now(),
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
      case SyncServiceStatus.error:
        emit(SyncError(
          message: serviceState.lastError ?? 'Unknown sync error',
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
      case SyncServiceStatus.offline:
        // 无独立的 SyncOffline 状态，映射为 SyncError 以避免 UI 卡住
        emit(SyncError(
          message: serviceState.lastError ?? '网络离线',
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
      case SyncServiceStatus.conflict:
        final resolver = _syncService.conflictResolver;
        final conflicts = resolver.conflicts;
        emit(SyncConflict(
          conflicts: conflicts,
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
    }
  }

  /// 启动同步
  /// 同步流程: Initialize → Pull → (Conflict? → Resolve) → Complete
  /// - 初始化同步服务，建立连接
  /// - 先拉取远端变更（pull-before-push 策略，避免覆盖冲突）
  /// - 拉取成功后回放离线队列中的待处理操作
  /// - 失败时加入离线队列，等待网络恢复后重试
  Future<void> _onStartSync(StartSync event, Emitter<SyncState> emit) async {
    emit(SyncInProgress(
      pushCount: 0,
      pullCount: 0,
      autoSyncEnabled: state.autoSyncEnabled,
      syncInterval: state.syncInterval,
      serverAddress: state.serverAddress,
    ));

    try {
      // Step 1: 初始化同步服务，建立与远端服务器的连接
      await _withRetry(() => _syncService.initialize());
      // 初始化后检查服务状态，状态异常则中止同步
      final initState = _syncService.state;
      if (initState.status == SyncServiceStatus.error) {
        emit(SyncError(
          message: initState.lastError ?? '初始化同步服务失败',
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
        return;
      }

      // Step 2: 拉取远端变更（pull-before-push 策略）
      await _withRetry(() => _syncService.pullChanges());
      final serviceState = _syncService.state;

      // 拉取结果验证：如果 pullChanges 返回 null 且状态为 error，说明拉取失败
      if (serviceState.status == SyncServiceStatus.error) {
        emit(SyncError(
          message: serviceState.lastError ?? '拉取远端数据失败',
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
        return;
      }

      if (serviceState.status == SyncServiceStatus.conflict) {
        final resolver = _syncService.conflictResolver;
        final conflicts = resolver.conflicts;
        emit(SyncConflict(
          conflicts: conflicts,
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
      } else {
        // 修复(P2): 删除原 160-166 行的 else if (error) 死代码分支——
        // 上方 141 行已检查 error 并 return，此分支永远不可达。
        emit(SyncCompleted(
          lastSyncTime: serviceState.lastSyncedAt ?? DateTime.now(),
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));

        // Step 3: 重连成功，回放离线队列中的待处理操作
        if (_offlineQueue.isNotEmpty) {
          await _offlineQueue.drainQueue((event) async {
            add(event);
          });
        }
      }
    } catch (e) {
      // 同步失败，将当前操作加入离线队列，等待网络恢复后自动重试
      _offlineQueue.addOperation(event);
      emit(SyncError(
        message: e.toString(),
        autoSyncEnabled: state.autoSyncEnabled,
        syncInterval: state.syncInterval,
        serverAddress: state.serverAddress,
      ));
    }
  }

  /// 停止同步
  /// 取消自动同步定时器，切换回空闲状态
  Future<void> _onStopSync(StopSync event, Emitter<SyncState> emit) async {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    emit(SyncIdle(
      autoSyncEnabled: false,
      syncInterval: state.syncInterval,
      serverAddress: state.serverAddress,
    ));
  }

  /// 推送变更到远端
  /// 将本地修改数据推送到同步服务器，失败时加入离线队列
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

/// 拉取远端变更到本地
  /// 从同步服务器获取最新数据，验证结果后应用到本地数据库
  Future<void> _onPullChanges(PullChanges event, Emitter<SyncState> emit) async {
    emit(SyncInProgress(
      pushCount: 0,
      pullCount: 1,
      autoSyncEnabled: state.autoSyncEnabled,
      syncInterval: state.syncInterval,
      serverAddress: state.serverAddress,
    ));

    try {
      // 执行拉取操作
      final result = await _withRetry(() => _syncService.pullChanges());
      final serviceState = _syncService.state;

      // 结果验证：拉取失败时终止流程
      if (serviceState.status == SyncServiceStatus.error) {
        _offlineQueue.addOperation(event);
        emit(SyncError(
          message: serviceState.lastError ?? '拉取失败',
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
        return;
      }

      // 冲突处理：存在冲突时等待用户解决
      if (serviceState.status == SyncServiceStatus.conflict) {
        final resolver = _syncService.conflictResolver;
        final conflicts = resolver.conflicts;
        emit(SyncConflict(
          conflicts: conflicts,
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

      // 拉取成功验证：result 为 null 表示无需应用数据（无变更）
      // result 非 null 表示数据已由 SyncService 返回，需由调用方写入本地数据库
      if (result != null && serviceState.status != SyncServiceStatus.error) {
        AppLogger.i('SyncBloc', '拉取同步完成，数据已返回待应用: ${serviceState.lastSyncedAt}');
      } else if (result == null && serviceState.status != SyncServiceStatus.error) {
        AppLogger.i('SyncBloc', '拉取完成，远端无新数据');
      }
    } catch (e) {
      // 拉取失败，将操作加入离线队列，等待网络恢复后重试
      _offlineQueue.addOperation(event);
      emit(SyncError(
        message: e.toString(),
        autoSyncEnabled: state.autoSyncEnabled,
        syncInterval: state.syncInterval,
        serverAddress: state.serverAddress,
      ));
    }
  }

  /// 处理同步状态变更通知
  /// 修复(P2): 原实现 emit(_copyWithBase(state)) 仅复制当前状态，注释说"切换到空闲状态"
  /// 但实际不切换到 SyncIdle，是 no-op。现根据 statusInfo.label 正确映射到对应 BLoC 状态。
  void _onStatusChanged(SyncStatusChanged event, Emitter<SyncState> emit) {
    final label = event.statusInfo.label;
    // SyncStatusInfo.label 来自 SyncService 的状态字符串映射
    if (label == 'idle') {
      emit(SyncIdle(
        autoSyncEnabled: state.autoSyncEnabled,
        syncInterval: state.syncInterval,
        serverAddress: state.serverAddress,
      ));
    } else if (label == 'syncing') {
      emit(SyncInProgress(
        autoSyncEnabled: state.autoSyncEnabled,
        syncInterval: state.syncInterval,
        serverAddress: state.serverAddress,
      ));
    } else if (label == 'synced') {
      emit(SyncCompleted(
        lastSyncTime: DateTime.now(),
        autoSyncEnabled: state.autoSyncEnabled,
        syncInterval: state.syncInterval,
        serverAddress: state.serverAddress,
      ));
    } else if (label == 'conflict') {
      final resolver = _syncService.conflictResolver;
      emit(SyncConflict(
        conflicts: resolver.conflicts,
        autoSyncEnabled: state.autoSyncEnabled,
        syncInterval: state.syncInterval,
        serverAddress: state.serverAddress,
      ));
    } else if (label == 'error') {
      emit(SyncError(
        message: _syncService.state.lastError ?? '同步错误',
        autoSyncEnabled: state.autoSyncEnabled,
        syncInterval: state.syncInterval,
        serverAddress: state.serverAddress,
      ));
    }
    // 未知 label 不改变状态
  }

  /// 解决冲突
  /// 根据用户选择（保留本地/使用远端）解决指定 block 的冲突
  /// 所有冲突解决后自动完成同步
  /// 修复：原代码始终传 useRemote=true，忽略用户实际选择
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

    // 判断用户选择的是远端还是本地内容
    final currentConflict = currentConflicts
        .where((c) => c.blockId == event.blockId)
        .firstOrNull;
    final useRemote = currentConflict != null &&
        event.resolvedContent == currentConflict.remoteContent;

    await _syncService.resolveConflict(useRemote);

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

  /// 切换自动同步开关
  /// 开启时启动定时器，关闭时取消定时器，配置通过 SyncSettingsService 持久化
  /// 修复 (P1-5): SharedPreferences 写入外移到 SyncSettingsService
  Future<void> _onAutoSyncToggled(
    AutoSyncToggled event,
    Emitter<SyncState> emit,
  ) async {
    await _settingsService.setAutoSyncEnabled(event.enabled);

    if (event.enabled) {
      _startAutoSyncTimer(state.syncInterval);
    } else {
      _autoSyncTimer?.cancel();
      _autoSyncTimer = null;
    }

    // ignore: invalid_use_of_visible_for_testing_member
    emit(_copyWithBase(state, autoSyncEnabled: event.enabled));
  }

  /// 修改同步间隔
  /// 通过 SyncSettingsService 持久化新间隔，若自动同步已开启则重启定时器
  /// 修复 (P1-5): SharedPreferences 写入外移到 SyncSettingsService
  Future<void> _onSyncIntervalChanged(
    SyncIntervalChanged event,
    Emitter<SyncState> emit,
  ) async {
    await _settingsService.setSyncInterval(event.interval);

    if (state.autoSyncEnabled) {
      _startAutoSyncTimer(event.interval);
    }

    // ignore: invalid_use_of_visible_for_testing_member
    emit(_copyWithBase(state, syncInterval: event.interval));
  }

  /// 启动自动同步定时器
  /// 按指定间隔周期性触发 StartSync 事件
  void _startAutoSyncTimer(Duration interval) {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(interval, (_) {
      add(const StartSync());
    });
  }

  /// 状态拷贝辅助方法
  /// 基于当前状态类型创建新状态，保留原有字段，仅更新指定字段
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

  /// 带重试策略的异步操作包装器
  /// - 最大重试次数: 5 次（默认 RetryPolicy 为 3 次，此处增加容错性）
  /// - 退避策略: 指数退避（baseDelay * 2^attempt），最大延迟 30 秒
  /// - 错误分类: 网络错误可重试，认证错误（401/403）不可重试，数据错误视情况
  /// - 参考: go-retryablehttp 的设计模式
  Future<T> _withRetry<T>(Future<T> Function() operation, {RetryPolicy? policy}) async {
    policy ??= const RetryPolicy(maxRetries: 5, baseDelay: Duration(seconds: 1), maxDelay: Duration(seconds: 30));
    int attempt = 0;
    while (true) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        // 错误类型分类：判断是否可重试
        final errorType = _classifyError(e);
        if (errorType == _ErrorType.nonRetryable) {
          rethrow;
        }
        if (attempt >= policy.maxRetries) rethrow;
        // 指数退避: delay = baseDelay * 2^attempt
        final delay = policy.delayForAttempt(attempt - 1);
        // ignore: invalid_use_of_visible_for_testing_member
        emit(SyncRetrying(
          retryAttempt: attempt,
          autoSyncEnabled: state.autoSyncEnabled,
          syncInterval: state.syncInterval,
          serverAddress: state.serverAddress,
        ));
        AppLogger.w('SyncBloc', '同步重试 $attempt/${policy.maxRetries}, 延迟 ${delay.inMilliseconds}ms, 错误类型: $errorType');
        await Future.delayed(delay);
      }
    }
  }

  /// 错误类型分类
  /// 参考: HTTP 标准状态码和 Dart 异常体系
  _ErrorType _classifyError(dynamic error) {
    final msg = error.toString().toLowerCase();
    // 认证/授权错误不可重试
    if (msg.contains('401') || msg.contains('403') || msg.contains('unauthorized')) {
      return _ErrorType.nonRetryable;
    }
    // 客户端错误（4xx，除 401/403 外）通常不可重试
    if (msg.contains('400') || msg.contains('404') || msg.contains('405') || msg.contains('422')) {
      return _ErrorType.nonRetryable;
    }
    // 服务器错误（5xx）和网络错误可重试
    if (msg.contains('500') || msg.contains('502') || msg.contains('503') || msg.contains('504')) {
      return _ErrorType.serverError;
    }
    // 超时、连接错误可重试
    if (msg.contains('timeout') || msg.contains('connection') || msg.contains('socket')) {
      return _ErrorType.networkError;
    }
    // 未知错误默认尝试重试
    return _ErrorType.unknown;
  }

  @override
  Future<void> close() {
    _autoSyncTimer?.cancel();
    _serviceStateSubscription?.cancel();
    // P0 修复: 不在此处调用 _syncService.dispose()。
    // SyncService 是 getIt 单例，被多个 SyncBloc 实例共享
    // （notes_page、sync_settings、conflicts 路由各创建一个 SyncBloc）。
    // 任一 BLoC 销毁时 dispose SyncService 会关闭其 StreamController，
    // 导致其他存活的 BLoC 监听 stateStream 抛 StateError。
    // SyncService 的生命周期应由 disposeSyncModule() 统一管理。
    return super.close();
  }
}

/// 同步错误类型分类
/// 借鉴: go-retryablehttp 的可重试判断逻辑
/// - nonRetryable: 认证/授权/客户端参数错误，不应重试
/// - serverError: 服务端临时故障（5xx），可重试
/// - networkError: 网络层面的超时、连接失败，可重试
/// - unknown: 未知错误，保守策略尝试重试
enum _ErrorType {
  nonRetryable,
  serverError,
  networkError,
  unknown,
}

/// 内部事件：配置加载完成
class _SyncPrefsLoaded extends SyncEvent {
  final bool autoSyncEnabled;
  final Duration syncInterval;
  final String? serverAddress;

  const _SyncPrefsLoaded({
    required this.autoSyncEnabled,
    required this.syncInterval,
    this.serverAddress,
  });

  @override
  List<Object?> get props => [autoSyncEnabled, syncInterval, serverAddress];
}

/// 内部事件：SyncService 状态变更
class _SyncServiceStateChanged extends SyncEvent {
  final SyncServiceState serviceState;

  const _SyncServiceStateChanged({required this.serviceState});

  @override
  List<Object?> get props => [serviceState];
}
