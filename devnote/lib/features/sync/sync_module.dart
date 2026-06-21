// 修复(P1): 将 features 层的依赖注册从 core/di/injection.dart 迁移至此，
// 消除 core → features 的反向依赖。

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/sync/crypto/e2e_crypto_service.dart';
import 'package:devnote/features/sync/incremental_sync_service.dart';
import 'package:devnote/features/sync/p2p/p2p_service.dart';
import 'package:devnote/features/sync/realtime/realtime_collab_service.dart';
import 'package:devnote/features/sync/sync_service.dart';
import 'package:devnote/features/sync/sync_settings_service.dart';

/// 注册 Sync 模块依赖
/// 实时协作服务借鉴 Anytype any-sync 与 Logseq RTC 的实时协作架构，
/// 注册为单例，全局共享一个 WebSocket 连接与操作日志缓冲区。
Future<void> registerSyncDependencies() async {
  getIt.registerLazySingleton<E2ECryptoService>(() => E2ECryptoService());
  getIt.registerLazySingleton<P2PService>(() => P2PService());
  getIt.registerLazySingleton<SyncService>(() => SyncService());
  getIt.registerLazySingleton<IncrementalSyncService>(
    () => IncrementalSyncService(),
  );
  // P1 修复 (P1-5): 同步设置服务 —— 封装 SharedPreferences 读写，
  // 供 SyncBloc 通过构造函数注入，避免 BLoC 直接依赖持久化细节。
  getIt.registerLazySingleton<SyncSettingsService>(
    () => SyncSettingsService(),
  );

  // 实时协作服务需要异步初始化
  final realtimeCollabService = RealtimeCollabService();
  await realtimeCollabService.initialize();
  getIt.registerSingleton<RealtimeCollabService>(realtimeCollabService);
}

/// 释放 Sync 模块资源
void disposeSyncModule() {
  if (getIt.isRegistered<SyncService>()) {
    getIt<SyncService>().dispose();
  }
  if (getIt.isRegistered<IncrementalSyncService>()) {
    getIt<IncrementalSyncService>().dispose();
  }
  if (getIt.isRegistered<P2PService>()) {
    getIt<P2PService>().dispose();
  }
  if (getIt.isRegistered<RealtimeCollabService>()) {
    getIt<RealtimeCollabService>().dispose();
  }
}
