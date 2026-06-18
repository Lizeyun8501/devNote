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
import 'package:devnote/features/ai/ai_service.dart';
import 'package:devnote/features/ai/embedding_service.dart';
import 'package:devnote/features/ai/ollama_client.dart';
import 'package:devnote/features/ai/semantic_search_service.dart';
import 'package:devnote/features/plugins/plugin_service.dart';
import 'package:devnote/features/settings/crypto/crypto_service.dart';
import 'package:devnote/features/sync/crypto/e2e_crypto_service.dart';
import 'package:devnote/features/sync/incremental_sync_service.dart';
import 'package:devnote/features/sync/p2p/p2p_service.dart';
import 'package:devnote/features/sync/realtime/realtime_collab_service.dart';
import 'package:devnote/features/sync/sync_service.dart';
import 'package:devnote/features/workflow/external_editor_sync.dart';
import 'package:devnote/features/workflow/file_watcher_service.dart';

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
  getIt.registerLazySingleton<IncrementalSyncService>(
    () => IncrementalSyncService(),
  );
  getIt.registerLazySingleton<FileWatcherService>(() => FileWatcherService());
  getIt.registerLazySingleton<ExternalEditorSyncService>(
    () => ExternalEditorSyncService(),
  );

  // ============================================================
  // AI 服务层 —— 借鉴 AppFlowy Vault 的本地 Ollama 集成
  // 注册顺序：OllamaClient → EmbeddingService → AIService → SemanticSearchService
  // 所有 AI 功能默认关闭，需用户在 AI 设置页配置 Ollama 后显式启用
  // ============================================================
  getIt.registerLazySingleton<OllamaClient>(
    () => OllamaClient(baseUrl: 'http://localhost:11434', model: 'llama3'),
  );
  getIt.registerLazySingleton<EmbeddingService>(
    () => EmbeddingService(ollamaClient: getIt<OllamaClient>()),
  );
  getIt.registerLazySingleton<AIService>(
    () => AIService(ollamaClient: getIt<OllamaClient>()),
  );
  getIt.registerLazySingleton<SemanticSearchService>(
    () => SemanticSearchService(
      databaseHelper: getIt<DatabaseHelper>(),
      embeddingService: getIt<EmbeddingService>(),
    ),
  );

  // 实时协作服务 —— 借鉴 Anytype any-sync 与 Logseq RTC 的实时协作架构
  // 注册为单例，全局共享一个 WebSocket 连接与操作日志缓冲区
  final realtimeCollabService = RealtimeCollabService();
  await realtimeCollabService.initialize();
  getIt.registerSingleton<RealtimeCollabService>(realtimeCollabService);
}

/// 统一释放所有已注册单例的资源
///
/// 调用时机：
/// - 应用退出前（通过 WidgetsBindingObserver.didRequestAppExit）
/// - 测试 tearDown 中清理全局状态
///
/// 借鉴 Flutter 官方 dispose 模式：按注册顺序逆序释放，避免依赖倒置
void disposeAll() {
  if (!getIt.isRegistered<FFIBridge>()) return;

  // 先释放有 dispose/close 方法的高级服务
  if (getIt.isRegistered<SyncService>()) {
    getIt<SyncService>().dispose();
  }
  if (getIt.isRegistered<IncrementalSyncService>()) {
    getIt<IncrementalSyncService>().dispose();
  }
  if (getIt.isRegistered<P2PService>()) {
    getIt<P2PService>().dispose();
  }
  if (getIt.isRegistered<ExternalEditorSyncService>()) {
    getIt<ExternalEditorSyncService>().dispose();
  }
  if (getIt.isRegistered<FileWatcherService>()) {
    getIt<FileWatcherService>().dispose();
  }
  // 释放实时协作服务（关闭 WebSocket 连接、持久化操作缓冲区）
  if (getIt.isRegistered<RealtimeCollabService>()) {
    getIt<RealtimeCollabService>().dispose();
  }
  // 释放 AI 服务层资源（关闭 Ollama HTTP 客户端、状态流）
  if (getIt.isRegistered<AIService>()) {
    getIt<AIService>().dispose();
  }
  if (getIt.isRegistered<OllamaClient>()) {
    getIt<OllamaClient>().dispose();
  }
  // 修复：释放 CacheManager 缓存资源
  if (getIt.isRegistered<CacheManager>()) {
    getIt<CacheManager>().clearAll();
  }

  // 释放核心桥接层（逆序）
  if (getIt.isRegistered<Dispatch>()) {
    getIt<Dispatch>().dispose();
  }
  if (getIt.isRegistered<WebSocketBridge>()) {
    getIt<WebSocketBridge>().dispose();
  }
  if (getIt.isRegistered<FFIBridge>()) {
    getIt<FFIBridge>().dispose();
  }

  // 清空 GetIt 容器
  getIt.reset();
}
