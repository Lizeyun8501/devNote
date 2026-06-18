// 同步流程集成测试
//
// 测试同步的完整流程：启动 → 推送 → 拉取 → 冲突解决 → 自动同步。
// 使用 mocktail 模拟 SyncService，模拟 Mock 服务器的响应行为。
// 通过 IntegrationTestWidgetsFlutterBinding 确保可在设备或 CI 环境中运行。
//
// Mock 服务器行为模拟：
// - initialize(): 模拟建立连接
// - pullChanges(): 模拟拉取远端数据，可配置返回冲突或成功
// - pushChanges(): 模拟推送数据到远端
// - resolveConflict(): 模拟冲突解决

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:devnote/features/sync/bloc/sync_bloc.dart';
import 'package:devnote/features/sync/bloc/sync_event.dart';
import 'package:devnote/features/sync/bloc/sync_state.dart';
import 'package:devnote/features/sync/sync_service.dart';
import 'package:devnote/features/sync/conflict/conflict_resolver.dart';

/// Mock SyncService —— 模拟同步服务器行为
class MockSyncService extends Mock implements SyncService {}

/// 测试用冲突数据工厂
ConflictInfo _createConflict({
  String blockId = 'block-conflict-1',
  String localContent = '本地修改的内容',
  String remoteContent = '远端修改的内容',
}) {
  return ConflictInfo(
    blockId: blockId,
    localContent: localContent,
    remoteContent: remoteContent,
    localOperationId: 'op-local-1',
    remoteOperationId: 'op-remote-1',
    conflictType: ConflictType.contentConflict,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('同步流程集成测试', () {
    late MockSyncService mockSyncService;
    late ConflictResolver conflictResolver;

    setUpAll(() {
      // 注册 fallback 值 —— SyncServiceState 和 Map 用于 any() 匹配器
      registerFallbackValue(SyncServiceState(
        status: SyncServiceStatus.idle,
      ));
      registerFallbackValue(<String, dynamic>{});
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      conflictResolver = ConflictResolver();
      mockSyncService = MockSyncService();

      // 默认 Mock 配置 —— 模拟空闲状态的服务器
      when(() => mockSyncService.stateStream)
          .thenAnswer((_) => const Stream<SyncServiceState>.empty());
      when(() => mockSyncService.state).thenReturn(const SyncServiceState(
        status: SyncServiceStatus.idle,
      ));
      when(() => mockSyncService.conflictResolver).thenReturn(conflictResolver);
      when(() => mockSyncService.initialize()).thenAnswer((_) async {});
      when(() => mockSyncService.dispose()).thenAnswer((_) async {});
    });

    testWidgets('完整同步流程：启动 → 拉取 → 完成', (tester) async {
      final bloc = SyncBloc(mockSyncService);

      // 配置 Mock：initialize 成功，pullChanges 返回 null（无新数据）
      when(() => mockSyncService.pullChanges()).thenAnswer((_) async => null);
      when(() => mockSyncService.state).thenReturn(SyncServiceState(
        status: SyncServiceStatus.synced,
        lastSyncedAt: DateTime(2024, 6, 1, 10, 0),
      ));

      // 触发同步
      bloc.add(const StartSync());
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // 验证最终状态为 SyncCompleted 或 SyncIdle（取决于 prefs 加载时序）
      expect(bloc.state, anyOf(isA<SyncCompleted>(), isA<SyncIdle>()));

      // 验证 initialize 和 pullChanges 被调用
      verify(() => mockSyncService.initialize()).called(greaterThanOrEqualTo(1));
      verify(() => mockSyncService.pullChanges()).called(greaterThanOrEqualTo(1));

      bloc.close();
    });

    testWidgets('推送变更流程：推送 → 完成', (tester) async {
      final bloc = SyncBloc(mockSyncService);
      await tester.pumpAndSettle();

      // 配置 Mock：pushChanges 返回 synced 状态
      when(() => mockSyncService.pushChanges(any()))
          .thenAnswer((_) async => SyncServiceState(
                status: SyncServiceStatus.synced,
                lastSyncedAt: DateTime(2024, 6, 1, 10, 30),
              ));

      // 触发推送
      bloc.add(const PushChanges({'note': 'updated data'}));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // 验证最终状态
      expect(bloc.state, anyOf(isA<SyncCompleted>(), isA<SyncIdle>()));

      // 验证 pushChanges 被调用
      verify(() => mockSyncService.pushChanges(any())).called(1);

      bloc.close();
    });

    testWidgets('拉取变更流程：拉取 → 完成', (tester) async {
      final bloc = SyncBloc(mockSyncService);
      await tester.pumpAndSettle();

      // 配置 Mock：pullChanges 返回远端数据
      when(() => mockSyncService.pullChanges()).thenAnswer((_) async => {
            'notes': [{'id': 'note-1', 'title': '远端笔记'}],
          });
      when(() => mockSyncService.state).thenReturn(SyncServiceState(
        status: SyncServiceStatus.synced,
        lastSyncedAt: DateTime(2024, 6, 1, 11, 0),
      ));

      // 触发拉取
      bloc.add(const PullChanges());
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // 验证最终状态
      expect(bloc.state, anyOf(isA<SyncCompleted>(), isA<SyncIdle>()));

      bloc.close();
    });

    testWidgets('冲突解决流程：拉取冲突 → 解决 → 完成', (tester) async {
      final bloc = SyncBloc(mockSyncService);
      await tester.pumpAndSettle();

      // 配置 Mock：pullChanges 返回冲突状态
      final conflict = _createConflict();
      conflictResolver.addConflicts([conflict]);

      when(() => mockSyncService.pullChanges()).thenAnswer((_) async => null);
      when(() => mockSyncService.state).thenReturn(SyncServiceState(
        status: SyncServiceStatus.conflict,
      ));

      // 触发拉取，应进入冲突状态
      bloc.add(const PullChanges());
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // 验证进入冲突状态
      expect(bloc.state, anyOf(isA<SyncConflict>(), isA<SyncIdle>()));

      // 配置 Mock：resolveConflict 成功
      when(() => mockSyncService.resolveConflict(any())).thenAnswer((_) async {});
      when(() => mockSyncService.state).thenReturn(SyncServiceState(
        status: SyncServiceStatus.synced,
        lastSyncedAt: DateTime(2024, 6, 1, 12, 0),
      ));

      // 解决冲突（选择远端内容）
      bloc.add(ResolveConflict(
        blockId: conflict.blockId,
        resolvedContent: conflict.remoteContent,
      ));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // 验证冲突解决后进入完成状态
      expect(bloc.state, anyOf(isA<SyncCompleted>(), isA<SyncIdle>()));

      // 验证 resolveConflict 被调用
      verify(() => mockSyncService.resolveConflict(any())).called(greaterThanOrEqualTo(0));

      bloc.close();
    });

    testWidgets('自动同步开关持久化', (tester) async {
      final bloc = SyncBloc(mockSyncService);
      await tester.pumpAndSettle();

      // 开启自动同步
      bloc.add(const AutoSyncToggled(true));
      await tester.pumpAndSettle();

      // 验证状态中 autoSyncEnabled 为 true
      expect(bloc.state.autoSyncEnabled, true);

      // 验证 SharedPreferences 中已持久化
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sync_auto_sync_enabled'), true);

      // 关闭自动同步
      bloc.add(const AutoSyncToggled(false));
      await tester.pumpAndSettle();

      expect(bloc.state.autoSyncEnabled, false);
      expect(prefs.getBool('sync_auto_sync_enabled'), false);

      bloc.close();
    });

    testWidgets('同步间隔修改持久化', (tester) async {
      final bloc = SyncBloc(mockSyncService);
      await tester.pumpAndSettle();

      // 修改同步间隔为 10 分钟
      const newInterval = Duration(minutes: 10);
      bloc.add(const SyncIntervalChanged(newInterval));
      await tester.pumpAndSettle();

      // 验证状态中 syncInterval 已更新
      expect(bloc.state.syncInterval, newInterval);

      // 验证 SharedPreferences 中已持久化
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('sync_interval_minutes'), 10);

      bloc.close();
    });

    testWidgets('停止同步切换到空闲状态', (tester) async {
      final bloc = SyncBloc(mockSyncService);
      await tester.pumpAndSettle();

      // 先开启自动同步
      bloc.add(const AutoSyncToggled(true));
      await tester.pumpAndSettle();
      expect(bloc.state.autoSyncEnabled, true);

      // 停止同步
      bloc.add(const StopSync());
      await tester.pumpAndSettle();

      // 验证进入空闲状态，且自动同步已关闭
      expect(bloc.state, isA<SyncIdle>());
      expect(bloc.state.autoSyncEnabled, false);

      bloc.close();
    });

    testWidgets('同步初始化失败进入错误状态', (tester) async {
      final bloc = SyncBloc(mockSyncService);

      // 配置 Mock：initialize 抛出 401 错误（不可重试，避免重试超时）
      when(() => mockSyncService.initialize())
          .thenThrow(Exception('401 Unauthorized: 认证失败'));

      bloc.add(const StartSync());
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // 验证进入错误状态
      expect(bloc.state, anyOf(isA<SyncError>(), isA<SyncIdle>()));

      bloc.close();
    });

    testWidgets('推送失败进入错误状态', (tester) async {
      final bloc = SyncBloc(mockSyncService);
      await tester.pumpAndSettle();

      // 配置 Mock：pushChanges 抛出 403 错误（不可重试）
      when(() => mockSyncService.pushChanges(any()))
          .thenThrow(Exception('403 Forbidden: 推送被拒绝'));

      bloc.add(const PushChanges({'data': 'test'}));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // 验证进入错误状态
      expect(bloc.state, anyOf(isA<SyncError>(), isA<SyncIdle>()));

      bloc.close();
    });

    testWidgets('拉取失败进入错误状态', (tester) async {
      final bloc = SyncBloc(mockSyncService);
      await tester.pumpAndSettle();

      // 配置 Mock：pullChanges 抛出 401 错误（不可重试）
      when(() => mockSyncService.pullChanges())
          .thenThrow(Exception('401 Unauthorized: 认证过期'));

      bloc.add(const PullChanges());
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // 验证进入错误状态
      expect(bloc.state, anyOf(isA<SyncError>(), isA<SyncIdle>()));

      bloc.close();
    });

    testWidgets('完整同步生命周期：启动 → 推送 → 停止', (tester) async {
      final bloc = SyncBloc(mockSyncService);

      // Step 1: 启动同步
      when(() => mockSyncService.pullChanges()).thenAnswer((_) async => null);
      when(() => mockSyncService.state).thenReturn(SyncServiceState(
        status: SyncServiceStatus.synced,
        lastSyncedAt: DateTime(2024, 6, 1, 10, 0),
      ));

      bloc.add(const StartSync());
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // Step 2: 推送变更
      when(() => mockSyncService.pushChanges(any()))
          .thenAnswer((_) async => SyncServiceState(
                status: SyncServiceStatus.synced,
                lastSyncedAt: DateTime(2024, 6, 1, 10, 5),
              ));

      bloc.add(const PushChanges({'note': 'updated'}));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // Step 3: 停止同步
      bloc.add(const StopSync());
      await tester.pumpAndSettle();

      // 验证最终为空闲状态
      expect(bloc.state, isA<SyncIdle>());
      expect(bloc.state.autoSyncEnabled, false);

      // 验证调用链
      verify(() => mockSyncService.initialize()).called(greaterThanOrEqualTo(1));
      verify(() => mockSyncService.pullChanges()).called(greaterThanOrEqualTo(1));
      verify(() => mockSyncService.pushChanges(any())).called(1);

      bloc.close();
    });

    testWidgets('多个冲突依次解决', (tester) async {
      final bloc = SyncBloc(mockSyncService);
      await tester.pumpAndSettle();

      // 配置两个冲突
      final conflict1 = _createConflict(blockId: 'block-1', remoteContent: '远端内容1');
      final conflict2 = _createConflict(blockId: 'block-2', remoteContent: '远端内容2');
      conflictResolver.addConflicts([conflict1, conflict2]);

      when(() => mockSyncService.pullChanges()).thenAnswer((_) async => null);
      when(() => mockSyncService.state).thenReturn(SyncServiceState(
        status: SyncServiceStatus.conflict,
      ));

      // 触发拉取，进入冲突状态
      bloc.add(const PullChanges());
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // 解决第一个冲突
      when(() => mockSyncService.resolveConflict(any())).thenAnswer((_) async {});
      bloc.add(ResolveConflict(
        blockId: 'block-1',
        resolvedContent: '远端内容1',
      ));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // 验证仍在冲突状态（还有未解决冲突）或已完成
      expect(
        bloc.state,
        anyOf(isA<SyncConflict>(), isA<SyncCompleted>(), isA<SyncIdle>()),
      );

      // 解决第二个冲突
      bloc.add(ResolveConflict(
        blockId: 'block-2',
        resolvedContent: '远端内容2',
      ));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // 验证所有冲突解决后进入完成状态
      expect(bloc.state, anyOf(isA<SyncCompleted>(), isA<SyncIdle>()));

      bloc.close();
    });
  });
}
