// SyncService 单元测试
//
// 测试同步服务的状态管理、生命周期、冲突解决、增量同步协调逻辑。
// 由于 SyncService 通过 getIt 硬编码注入 E2ECryptoService 和 IncrementalSyncService，
// 测试中需先在 getIt 中注册 Mock 实例，再构造 SyncService。
// 使用 SharedPreferences mock 持久化状态，避免真实 IO。
// 对于依赖 HTTP 的方法（pushChanges/pullChanges），仅测试加密失败分支与状态转换，
// 不测试实际 HTTP 调用（避免引入复杂的 http mock）。

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:devnote/api/devnote_api_client.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/sync/crypto/e2e_crypto_service.dart';
import 'package:devnote/features/sync/incremental_sync_service.dart';
import 'package:devnote/features/sync/sync_service.dart';

// Mock E2ECryptoService —— 避免对真实加密/SecureKeyStorage 的依赖
class MockE2ECryptoService extends Mock implements E2ECryptoService {}

// Mock IncrementalSyncService —— 避免对 HTTP/rdiff 的依赖
class MockIncrementalSyncService extends Mock implements IncrementalSyncService {}

void main() {
  late MockE2ECryptoService mockCryptoService;
  late MockIncrementalSyncService mockIncrementalSync;
  late SyncService syncService;

  setUpAll(() {
    // 注册 fallback 值，供 mocktail 的 any() 匹配非空类型参数使用
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(false);
  });

  setUp(() {
    // 每个测试前重置 SharedPreferences mock
    SharedPreferences.setMockInitialValues({});

    // 重置 getIt，确保上一个测试注册的单例不残留
    getIt.reset();

    // 创建 Mock 实例
    mockCryptoService = MockE2ECryptoService();
    mockIncrementalSync = MockIncrementalSyncService();

    // 默认 mock 行为：加密服务未配置，initialize 为空操作
    when(() => mockCryptoService.initialize()).thenAnswer((_) async {});
    when(() => mockCryptoService.state).thenReturn(
      const E2ECryptoState(status: E2ECryptoStatus.notConfigured),
    );

    // 默认 mock 行为：增量同步服务 initialize 为空操作
    when(() => mockIncrementalSync.initialize()).thenAnswer((_) async {});

    // 注册到 getIt —— 必须在构造 SyncService 之前完成
    // SyncService 的字段初始化器会调用 getIt<E2ECryptoService>()
    getIt.registerSingleton<E2ECryptoService>(mockCryptoService);
    getIt.registerSingleton<IncrementalSyncService>(mockIncrementalSync);

    // P1-1: 注册 DevNoteApiClient —— SyncService 字段初始化器会调用 getIt<DevNoteApiClient>()
    // 本测试不发起真实 HTTP 调用（仅测试加密失败分支与状态转换），
    // 故使用占位 URL 注册真实实例即可。
    getIt.registerLazySingleton<DevNoteApiClient>(
      () => DevNoteApiClient(
        syncServerUrl: 'http://localhost:0',
        businessServerUrl: 'http://localhost:0',
      ),
    );

    // 构造 SyncService（构造时从 getIt 取依赖）
    syncService = SyncService();
  });

  tearDown(() {
    // 释放 SyncService 的 StreamController，避免资源泄漏
    syncService.dispose();
  });

  group('SyncService - 初始状态', () {
    test('新建 SyncService 后状态为 idle', () {
      expect(syncService.state.status, SyncServiceStatus.idle);
      expect(syncService.state.pendingChanges, 0);
      expect(syncService.state.lastSyncedAt, isNull);
      expect(syncService.state.encryptionEnabled, isFalse);
      expect(syncService.state.lastError, isNull);
    });

    test('conflictResolver 已初始化', () {
      expect(syncService.conflictResolver, isNotNull);
    });
  });

  group('SyncService - initialize', () {
    test('从 SharedPreferences 读取 lastSyncTime 和 pendingChanges', () async {
      // 预置持久化数据
      SharedPreferences.setMockInitialValues({
        'sync_last_sync_time': 1700000000000,
        'sync_pending_changes': 5,
      });

      await syncService.initialize();

      expect(syncService.state.pendingChanges, 5);
      expect(syncService.state.lastSyncedAt, isNotNull);
      expect(
        syncService.state.lastSyncedAt!.millisecondsSinceEpoch,
        1700000000000,
      );
    });

    test('未持久化数据时 pendingChanges 默认为 0 且 lastSyncedAt 为 null', () async {
      await syncService.initialize();

      expect(syncService.state.pendingChanges, 0);
      expect(syncService.state.lastSyncedAt, isNull);
    });

    test('加密服务已配置时 encryptionEnabled 为 true', () async {
      when(() => mockCryptoService.state).thenReturn(
        const E2ECryptoState(status: E2ECryptoStatus.configured),
      );

      await syncService.initialize();

      expect(syncService.state.encryptionEnabled, isTrue);
    });

    test('加密服务未配置时 encryptionEnabled 为 false', () async {
      when(() => mockCryptoService.state).thenReturn(
        const E2ECryptoState(status: E2ECryptoStatus.notConfigured),
      );

      await syncService.initialize();

      expect(syncService.state.encryptionEnabled, isFalse);
    });

    test('initialize 调用加密服务和增量同步服务的 initialize', () async {
      await syncService.initialize();

      verify(() => mockCryptoService.initialize()).called(1);
      verify(() => mockIncrementalSync.initialize()).called(1);
    });
  });

  group('SyncService - isEncryptionReady', () {
    test('加密服务状态为 notConfigured 时返回 false', () {
      when(() => mockCryptoService.state).thenReturn(
        const E2ECryptoState(status: E2ECryptoStatus.notConfigured),
      );

      expect(syncService.isEncryptionReady(), isFalse);
    });

    test('加密服务状态为 configured 时返回 true', () {
      when(() => mockCryptoService.state).thenReturn(
        const E2ECryptoState(status: E2ECryptoStatus.configured),
      );

      expect(syncService.isEncryptionReady(), isTrue);
    });

    test('加密服务状态为 active 时返回 true', () {
      when(() => mockCryptoService.state).thenReturn(
        const E2ECryptoState(status: E2ECryptoStatus.active),
      );

      expect(syncService.isEncryptionReady(), isTrue);
    });
  });

  group('SyncService - markPendingChange', () {
    test('调用后 pendingChanges 递增', () {
      expect(syncService.state.pendingChanges, 0);

      syncService.markPendingChange();
      expect(syncService.state.pendingChanges, 1);

      syncService.markPendingChange();
      expect(syncService.state.pendingChanges, 2);

      syncService.markPendingChange();
      expect(syncService.state.pendingChanges, 3);
    });

    test('markPendingChange 不改变 status', () {
      syncService.markPendingChange();
      expect(syncService.state.status, SyncServiceStatus.idle);
    });
  });

  group('SyncService - stateStream', () {
    test('resolveConflict 后状态流发射 synced 状态', () async {
      final states = <SyncServiceState>[];
      final subscription = syncService.stateStream.listen(states.add);

      await syncService.resolveConflict(false);

      // 等待广播流事件传播
      await Future.delayed(Duration.zero);

      expect(states, isNotEmpty);
      expect(states.last.status, SyncServiceStatus.synced);
      subscription.cancel();
    });

    test('pushChanges 加密失败时状态流依次发射 syncing → error', () async {
      // 配置加密服务：已配置但加密返回 null
      when(() => mockCryptoService.state).thenReturn(
        const E2ECryptoState(status: E2ECryptoStatus.configured),
      );
      when(() => mockCryptoService.encryptSyncData(any())).thenReturn(null);

      final states = <SyncServiceState>[];
      final subscription = syncService.stateStream.listen(states.add);

      await syncService.pushChanges({'key': 'value'});

      await Future.delayed(Duration.zero);

      // 应先发射 syncing，再发射 error
      expect(states.length, greaterThanOrEqualTo(2));
      expect(states.first.status, SyncServiceStatus.syncing);
      expect(states.last.status, SyncServiceStatus.error);
      expect(states.last.lastError, '加密失败');
      subscription.cancel();
    });
  });

  group('SyncService - resolveConflict', () {
    test('useRemote=true 时清零 pendingChanges 并设状态为 synced', () async {
      // 预置 pendingChanges
      syncService.markPendingChange();
      syncService.markPendingChange();
      expect(syncService.state.pendingChanges, 2);

      await syncService.resolveConflict(true);

      expect(syncService.state.status, SyncServiceStatus.synced);
      expect(syncService.state.pendingChanges, 0);
      expect(syncService.state.lastError, isNull);
    });

    test('useRemote=false 时保持 pendingChanges 并设状态为 synced', () async {
      syncService.markPendingChange();
      syncService.markPendingChange();
      syncService.markPendingChange();
      expect(syncService.state.pendingChanges, 3);

      await syncService.resolveConflict(false);

      expect(syncService.state.status, SyncServiceStatus.synced);
      expect(syncService.state.pendingChanges, 3);
    });

    test('useRemote=true 时持久化 pendingChanges=0 到 SharedPreferences', () async {
      syncService.markPendingChange();
      await syncService.resolveConflict(true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('sync_pending_changes'), 0);
    });

    test('不传 conflictId 时不发起 HTTP 请求，仅更新本地状态', () async {
      await syncService.resolveConflict(true);

      expect(syncService.state.status, SyncServiceStatus.synced);
    });
  });

  group('SyncService - pushChanges 异常处理', () {
    test('加密就绪但 encryptSyncData 返回 null 时状态变为 error', () async {
      when(() => mockCryptoService.state).thenReturn(
        const E2ECryptoState(status: E2ECryptoStatus.configured),
      );
      when(() => mockCryptoService.encryptSyncData(any())).thenReturn(null);

      final result = await syncService.pushChanges({'key': 'value'});

      expect(result.status, SyncServiceStatus.error);
      expect(result.lastError, '加密失败');
      expect(syncService.state.status, SyncServiceStatus.error);
      expect(syncService.state.lastError, '加密失败');
    });

    test('加密失败时提前返回，不进入 HTTP 推送流程', () async {
      when(() => mockCryptoService.state).thenReturn(
        const E2ECryptoState(status: E2ECryptoStatus.configured),
      );
      when(() => mockCryptoService.encryptSyncData(any())).thenReturn(null);

      await syncService.pushChanges({'key': 'value'});

      // encryptSyncData 被调用一次后即返回，未进入 _performPush
      verify(() => mockCryptoService.encryptSyncData(any())).called(1);
      expect(syncService.state.status, SyncServiceStatus.error);
    });
  });

  group('SyncService - pushIncremental', () {
    test('增量推送成功时状态变为 synced 并清零 pendingChanges', () async {
      when(() => mockIncrementalSync.pushIncremental(any(), encrypt: any(named: 'encrypt')))
          .thenAnswer((_) async => const IncrementalSyncResult(success: true));

      syncService.markPendingChange();
      expect(syncService.state.pendingChanges, 1);

      final result = await syncService.pushIncremental({'key': 'value'});

      expect(result.success, isTrue);
      expect(syncService.state.status, SyncServiceStatus.synced);
      expect(syncService.state.pendingChanges, 0);
      expect(syncService.state.lastSyncedAt, isNotNull);
    });

    test('增量推送失败时状态变为 error 并记录错误', () async {
      when(() => mockIncrementalSync.pushIncremental(any(), encrypt: any(named: 'encrypt')))
          .thenAnswer((_) async => const IncrementalSyncResult(
                success: false,
                error: '分块上传失败',
              ));

      final result = await syncService.pushIncremental({'key': 'value'});

      expect(result.success, isFalse);
      expect(syncService.state.status, SyncServiceStatus.error);
      expect(syncService.state.lastError, '分块上传失败');
    });

    test('增量推送前状态先变为 syncing', () async {
      final states = <SyncServiceStatus>[];
      final subscription = syncService.stateStream.listen((s) {
        states.add(s.status);
      });

      when(() => mockIncrementalSync.pushIncremental(any(), encrypt: any(named: 'encrypt')))
          .thenAnswer((_) async => const IncrementalSyncResult(success: true));

      await syncService.pushIncremental({'key': 'value'});
      await Future.delayed(Duration.zero);

      expect(states.first, SyncServiceStatus.syncing);
      expect(states.last, SyncServiceStatus.synced);
      subscription.cancel();
    });

    test('成功后持久化 lastSyncTime 和 pendingChanges=0', () async {
      when(() => mockIncrementalSync.pushIncremental(any(), encrypt: any(named: 'encrypt')))
          .thenAnswer((_) async => const IncrementalSyncResult(success: true));

      await syncService.pushIncremental({'key': 'value'});

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('sync_last_sync_time'), isNotNull);
      expect(prefs.getInt('sync_pending_changes'), 0);
    });
  });

  group('SyncService - resumeIncrementalPush', () {
    test('无可恢复会话时直接返回失败结果，不进入 syncing', () async {
      when(() => mockIncrementalSync.hasResumableSession).thenReturn(false);

      final result = await syncService.resumeIncrementalPush({'key': 'value'});

      expect(result.success, isFalse);
      expect(result.error, '无可恢复的同步会话');
      expect(syncService.state.status, SyncServiceStatus.idle);
    });

    test('有可恢复会话时调用增量推送并成功', () async {
      when(() => mockIncrementalSync.hasResumableSession).thenReturn(true);
      when(() => mockIncrementalSync.pushIncremental(any(), encrypt: any(named: 'encrypt')))
          .thenAnswer((_) async => const IncrementalSyncResult(success: true));

      final result = await syncService.resumeIncrementalPush({'key': 'value'});

      expect(result.success, isTrue);
      expect(syncService.state.status, SyncServiceStatus.synced);
    });
  });

  group('SyncService - abortIncrementalSession', () {
    test('调用增量服务的 abortSession 并将状态置为 idle', () async {
      when(() => mockIncrementalSync.abortSession()).thenAnswer((_) async {});

      await syncService.abortIncrementalSession();

      verify(() => mockIncrementalSync.abortSession()).called(1);
      expect(syncService.state.status, SyncServiceStatus.idle);
    });
  });

  group('SyncService - 增量同步代理 getter', () {
    test('incrementalSyncProgress 代理到 IncrementalSyncService.currentProgress', () {
      when(() => mockIncrementalSync.currentProgress).thenReturn(0.75);

      expect(syncService.incrementalSyncProgress, 0.75);
    });

    test('hasResumableSession 代理到 IncrementalSyncService.hasResumableSession', () {
      when(() => mockIncrementalSync.hasResumableSession).thenReturn(true);

      expect(syncService.hasResumableSession, isTrue);
    });
  });

  group('SyncService - dispose', () {
    test('dispose 后状态流关闭', () async {
      // 创建独立的 SyncService 避免影响 tearDown
      final newService = SyncService();
      final doneCompleter = Completer<bool>();

      newService.stateStream.listen(
        (_) {},
        onDone: () => doneCompleter.complete(true),
      );

      newService.dispose();

      expect(await doneCompleter.future, isTrue);
    });
  });
}
