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
import 'package:devnote/core/persistence/folder_repository.dart';
import 'package:devnote/core/persistence/note_repository.dart';
import 'package:devnote/core/services/locale_service.dart';
import 'package:devnote/features/editor/services/math_ink_service.dart';
import 'package:devnote/features/notes/services/ocr_service.dart';
import 'package:devnote/features/notes/services/share_service.dart';
import 'package:devnote/features/notes/services/version_history_service.dart';
import 'package:devnote/features/settings/import_export/onenote_import_service.dart';

/// 修复(P1): 移除所有 features/* 导入，消除 core → features 的反向依赖。
/// 原实现导入了 13 个 features 模块，违反依赖倒置原则。
/// features 层各自提供 register<Module>Dependencies() 和 dispose<Module>() 函数
/// （如 ai_module.dart），由 main.dart 在 setupDependencies() 之后顺序调用。

final GetIt getIt = GetIt.instance;

/// 注册 core 层依赖（bridges / dispatch / performance / database / config / logger）。
/// features 层依赖由各自的 *_module.dart register 函数注册，由 main.dart 调用。
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

  // P2-7: 多语言扩展 —— 语言设置服务（持久化用户语言偏好）
  getIt.registerLazySingleton<LocaleService>(() => LocaleService());

  // P0-2: OCR 文字识别 + 图片搜索服务
  getIt.registerLazySingleton<OcrService>(() => OcrService());

  // P1-4: 版本历史服务
  getIt.registerLazySingleton<VersionHistoryService>(() => VersionHistoryService());

  // P2-1: 笔记公开分享/发布服务
  getIt.registerLazySingleton<ShareService>(() => ShareService());

  // P2-9: 手写公式识别（数学墨迹）服务
  if (!getIt.isRegistered<MathInkService>()) {
    getIt.registerLazySingleton<MathInkService>(() => MathInkService());
  }

  // P2-8: OneNote 导入工具
  // OneNoteGraphImporter: 通过 Microsoft Graph API 导入（OAuth2 授权流程）
  // OneNoteHtmlImporter: 通过导出的 HTML 文件导入（本地文件解析）
  if (!getIt.isRegistered<OneNoteGraphImporter>()) {
    getIt.registerLazySingleton<OneNoteGraphImporter>(() => OneNoteGraphImporter());
  }
  if (!getIt.isRegistered<OneNoteHtmlImporter>()) {
    getIt.registerLazySingleton<OneNoteHtmlImporter>(() {
      final dbHelper = getIt<DatabaseHelper>();
      return OneNoteHtmlImporter(
        noteRepository: SqliteNoteRepository(dbHelper),
        folderRepository: SqliteFolderRepository(dbHelper),
      );
    });
  }
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
  if (getIt.isRegistered<WebSocketBridge>()) {
    getIt<WebSocketBridge>().dispose();
  }
  if (getIt.isRegistered<FFIBridge>()) {
    getIt<FFIBridge>().dispose();
  }
}
