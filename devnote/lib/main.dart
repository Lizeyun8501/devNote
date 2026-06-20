// DevNote 应用入口 —— 本地优先的跨平台云笔记应用
// 架构借鉴: AppFlowy (Flutter+Rust), SiYuan (块编辑+知识图谱), Anytype (对象化模型)
//
// 借鉴 AppFlowy 的 Flutter+Rust 混合架构
// 来源: https://github.com/AppFlowy-IO/AppFlowy
// 借鉴内容: Flutter 前端 + Rust 核心引擎 + FFI 桥接的分层架构模式
//
// 借鉴思源笔记的块编辑+知识图谱
// 来源: https://github.com/siyuan-note/siyuan
// 借鉴内容: 块级编辑器设计理念、知识图谱可视化
//
// 借鉴 Anytype 的对象化模型
// 来源: https://github.com/anyproto/anytype-kb
// 借鉴内容: 以对象(Object)为原语的数据建模方式

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:devnote/core/i18n/app_localizations.dart';
import 'package:devnote/core/theme/app_theme.dart';
import 'package:devnote/core/router/app_router.dart';
import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/observability/sentry_config.dart';
import 'package:devnote/core/performance/startup_manager.dart';
import 'package:devnote/core/performance/cache_manager.dart';
import 'package:devnote/core/performance/memory_manager.dart';
import 'package:devnote/core/platform/platform_channel.dart';

// 修复(P1): features 层依赖注册从 core/di 迁移至各 feature 模块自注册，
// 消除 core → features 的反向依赖。
import 'package:devnote/features/ai/ai_module.dart';
import 'package:devnote/features/plugins/plugins_module.dart';
import 'package:devnote/features/settings/settings_module.dart';
import 'package:devnote/features/sync/sync_module.dart';
import 'package:devnote/features/workflow/workflow_module.dart';
// 修复(P2-1): 新增 feature 模块注册，消除页面中直接 new Service 绕过 DI 的问题
import 'package:devnote/features/editor/editor_module.dart';
import 'package:devnote/features/search/search_module.dart';
import 'package:devnote/features/canvas/canvas_module.dart';
import 'package:devnote/features/database/database_module.dart';
import 'package:devnote/features/knowledge_graph/knowledge_graph_module.dart';
import 'package:devnote/features/flashcard/flashcard_module.dart';
// P1-3: 模板系统 + 模板市场
import 'package:devnote/features/templates/templates_module.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize core dependency injection (core layer only)
  await setupDependencies();

  // 修复(P1): features 层依赖由各自模块注册，消除 core → features 反向依赖
  await registerPluginsDependencies();
  await registerSettingsDependencies();
  await registerSyncDependencies();
  await registerWorkflowDependencies();
  await registerAIDependencies();
  // 修复(P2-1): 注册 Editor/Search/Canvas/Database/Graph/Flashcard 服务到 DI
  await registerEditorDependencies();
  await registerSearchDependencies();
  await registerCanvasDependencies();
  await registerDatabaseDependencies();
  await registerGraphDependencies();
  await registerFlashcardDependencies();
  // P1-3: 注册模板系统服务到 DI
  await registerTemplatesDependencies();

  // 修复：Sentry 初始化提前到 FFI Bridge 之前，确保 FFI 初始化过程中的
  // 错误能被 Sentry 捕获上报，防止启动阶段异常丢失
  await setupSentry();

  // Initialize Rust FFI bridge
  try {
    await getIt<FFIBridge>().init();
  } catch (e) {
    debugPrint('Warning: FFI bridge initialization failed: $e');
    // Continue without FFI - graceful degradation
  }

  // Initialize platform channel
  try {
    final platformChannel = DevNotePlatformChannel();
    final deviceInfo = await platformChannel.getDeviceInfo();
    debugPrint('Platform channel initialized. Device info: $deviceInfo');
  } catch (e) {
    debugPrint('Warning: Platform channel initialization failed: $e');
    // Continue without platform channel - graceful degradation
  }

  // Initialize performance systems
  await getIt<StartupManager>().initialize();

  // Configure caches
  final cacheManager = getIt<CacheManager>();
  cacheManager.configure(CacheType.noteContent, maxSize: 50, ttl: const Duration(minutes: 30));
  cacheManager.configure(CacheType.image, maxSize: 100, ttl: const Duration(hours: 1));
  cacheManager.configure(CacheType.searchResult, maxSize: 30, ttl: const Duration(minutes: 10));

  // Set memory limit
  getIt<MemoryManager>().setMemoryLimit(100 * 1024 * 1024);

  runApp(const DevNoteApp());
}

class DevNoteApp extends StatefulWidget {
  const DevNoteApp({super.key});

  @override
  State<DevNoteApp> createState() => _DevNoteAppState();
}

/// 修复：添加 WidgetsBindingObserver 监听应用退出事件
/// 原代码应用退出时不调用 disposeAll()，导致 SyncService/P2PService 等
/// 单例资源未释放，可能造成数据丢失（如未完成的同步操作）
///
/// 修复(P1): disposeAll 拆分为各 feature 模块的 dispose 函数 + disposeCore()，
/// 消除 core/di 对 features 的反向依赖。
class _DevNoteAppState extends State<DevNoteApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // dispose() 是同步 void，无法 await 异步清理。
    // 使用 fire-and-forget 模式：正常退出路径走 didRequestAppExit()（会 await），
    // 此处主要覆盖 hot-reload 场景。
    _disposeAll();
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    // 应用退出前释放所有单例资源
    await _disposeAll();
    return AppExitResponse.exit;
  }

  /// 统一释放所有模块资源：先释放 features 层（逆序），再释放 core 层。
  ///
  /// 修复(P2-16): 改为 async 以 await disposeCore() 中的 DatabaseHelper.close()，
  /// 确保数据库句柄在 getIt.reset() 之前被正确关闭。
  Future<void> _disposeAll() async {
    // 修复(P2-1): 释放新增 feature 模块资源（逆序，features 在 core 之前释放）
    // P1-3: 模板系统最后注册，故最先释放
    disposeTemplatesModule();
    disposeFlashcardModule();
    disposeGraphModule();
    disposeDatabaseModule();
    disposeCanvasModule();
    disposeSearchModule();
    disposeEditorModule();
    disposeAIModule();
    disposeWorkflowModule();
    disposeSyncModule();
    await disposeCore();
    getIt.reset();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LocaleProvider.instance,
      builder: (context, locale, child) {
        return MaterialApp.router(
          title: 'DevNote',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          routerConfig: appRouter,
          locale: locale,
          supportedLocales: LocaleProvider.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        );
      },
    );
  }
}
