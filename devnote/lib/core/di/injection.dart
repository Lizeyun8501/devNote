import 'package:get_it/get_it.dart';

import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/bridge/grpc_bridge.dart';
import 'package:devnote/core/bridge/websocket_bridge.dart';
import 'package:devnote/core/config/app_config.dart';
import 'package:devnote/core/observability/app_logger.dart';
import 'package:devnote/core/performance/cache_manager.dart';
import 'package:devnote/core/performance/memory_manager.dart';
import 'package:devnote/core/performance/startup_manager.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/features/plugins/plugin_service.dart';
import 'package:devnote/features/settings/crypto/crypto_service.dart';
import 'package:devnote/features/sync/crypto/e2e_crypto_service.dart';
import 'package:devnote/features/sync/p2p/p2p_service.dart';
import 'package:devnote/features/sync/sync_service.dart';

final GetIt getIt = GetIt.instance;

Future<void> setupDependencies() async {
  // Core bridges (eager singletons)
  getIt.registerSingleton<FFIBridge>(FFIBridge());
  getIt.registerSingleton<GrpcBridge>(GrpcBridge());
  getIt.registerSingleton<WebSocketBridge>(WebSocketBridge());

  // Dispatch (depends on bridges)
  getIt.registerSingleton<Dispatch>(Dispatch());

  // Performance managers
  getIt.registerSingleton<CacheManager>(CacheManager());
  getIt.registerSingleton<MemoryManager>(MemoryManager());
  getIt.registerSingleton<StartupManager>(StartupManager());

  // Database
  getIt.registerLazySingleton<DatabaseHelper>(() => DatabaseHelper());

  // 统一配置管理 —— 借鉴 1Password 的集中配置管理思想
  getIt.registerSingleton<AppConfig>(AppConfig.instance);
  await getIt<AppConfig>().init();

  // 统一日志模块 —— 借鉴 log4j 的日志级别设计
  getIt.registerSingleton<AppLogger>(AppLogger.instance);

  // Services
  getIt.registerLazySingleton<PluginService>(() => PluginService());
  getIt.registerLazySingleton<CryptoService>(() => CryptoService());
  getIt.registerLazySingleton<E2ECryptoService>(() => E2ECryptoService());
  getIt.registerLazySingleton<P2PService>(() => P2PService());
  getIt.registerLazySingleton<SyncService>(() => SyncService());
}
