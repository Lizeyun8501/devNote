import 'package:get_it/get_it.dart';

import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/config/app_config.dart';
import 'package:devnote/core/observability/app_logger.dart';
import 'package:devnote/core/performance/cache_manager.dart';
import 'package:devnote/core/performance/memory_manager.dart';
import 'package:devnote/core/performance/startup_manager.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/core/services/locale_service.dart';

/// core 层仅注册 core 层依赖。
/// features 层依赖由各自的 *_module.dart register 函数注册，由 main.dart 调用。
/// 此文件不导入任何 features/* 路径，确保 core → features 无反向依赖。
///
/// Phase 1 死代码清理: 移除 GrpcBridge/WebSocketBridge（注册但从未被业务代码调用）。

final GetIt getIt = GetIt.instance;

/// 注册 core 层依赖（bridges / dispatch / performance / database / config / logger）。
/// features 层依赖由各自的 *_module.dart register 函数注册，由 main.dart 调用。
Future<void> setupDependencies() async {
  // Core bridges (eager singletons)
  getIt.registerSingleton<FFIBridge>(FFIBridge());

  // Dispatch (depends on bridges)
  getIt.registerSingleton<Dispatch>(Dispatch());

  // Performance managers
  getIt.registerSingleton<CacheManager>(CacheManager());
  getIt.registerSingleton<MemoryManager>(MemoryManager());
  getIt.registerSingleton<StartupManager>(StartupManager());

  // Database
  getIt.registerLazySingleton<DatabaseHelper>(() => DatabaseHelper());

  // 统一配置管理
  getIt.registerSingleton<AppConfig>(AppConfig.instance);
  await getIt<AppConfig>().init();

  // 统一日志模块
  getIt.registerSingleton<AppLogger>(AppLogger.instance);

  // P2-7: 多语言扩展 —— 语言设置服务（持久化用户语言偏好）
  getIt.registerLazySingleton<LocaleService>(() => LocaleService());
}

/// 释放 core 层已注册单例的资源。
/// features 层服务的释放由各自的 dispose<Module>() 函数负责，由 main.dart 调用。
///
/// 调用时机：
/// - 应用退出前（通过 WidgetsBindingObserver.didRequestAppExit）
/// - 测试 tearDown 中清理全局状态
///
/// 修复(P2-16): 改为 async 以 await DatabaseHelper.close()，确保数据库句柄
/// 在 getIt.reset() 之前被正确关闭，避免 "database is locked" 或文件句柄泄漏。
Future<void> disposeCore() async {
  if (!getIt.isRegistered<FFIBridge>()) return;

  // 释放 core 层缓存
  if (getIt.isRegistered<CacheManager>()) {
    getIt<CacheManager>().clearAll();
  }

  // 关闭数据库连接（必须在 getIt.reset() 之前完成）
  if (getIt.isRegistered<DatabaseHelper>()) {
    await getIt<DatabaseHelper>().close();
  }

  // 释放核心桥接层（逆序）
  if (getIt.isRegistered<Dispatch>()) {
    getIt<Dispatch>().dispose();
  }
  if (getIt.isRegistered<FFIBridge>()) {
    getIt<FFIBridge>().dispose();
  }
}
