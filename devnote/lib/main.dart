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

import 'dart:async';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:devnote/core/i18n/app_localizations.dart';
import 'package:devnote/core/theme/app_theme.dart';
import 'package:devnote/core/router/app_router.dart';
import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/router/route_registry.dart';
import 'package:devnote/core/observability/app_logger.dart';
import 'package:devnote/core/observability/sentry_config.dart';
import 'package:devnote/core/performance/startup_manager.dart';
import 'package:devnote/core/performance/cache_manager.dart';
import 'package:devnote/core/performance/memory_manager.dart';
import 'package:devnote/core/platform/platform_channel.dart';
import 'package:devnote/core/services/locale_service.dart';
import 'package:devnote/features/feature_routes.dart';

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
// P1-7: Vault 保险库（敏感笔记二次加密）
import 'package:devnote/features/vault/vault_module.dart';
// P2-4: Daily Notes 每日笔记
import 'package:devnote/features/notes/notes_module.dart';
// P2-5: 全局待办/提醒系统（本地通知 + 时区调度）
import 'package:devnote/features/todo/todo_module.dart';
import 'package:devnote/features/todo/services/notification_service.dart';
// P2-6: 手绘画布白板（Excalidraw 风格）
import 'package:devnote/features/whiteboard/whiteboard_module.dart';
// P2-3: 补全缺失模块的 module.dart（freeform/knowledge/object）
import 'package:devnote/features/freeform/freeform_module.dart';
import 'package:devnote/features/knowledge/knowledge_module.dart';
import 'package:devnote/features/object/object_module.dart';

void main() {
  // 全局错误边界：捕获同步异常和 Flutter 框架异常
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.e('FlutterError', 'Flutter framework error', error: details.exception, stackTrace: details.stack);
  };

  // runZonedGuarded 捕获所有未处理的异步异常
  runZonedGuarded<Future<void>>(() async {
    await _initializeApp();
    runApp(const DevNoteApp());
  }, (error, stack) {
    AppLogger.e('Zone', 'Unhandled async error', error: error, stackTrace: stack);
  });
}

/// 应用初始化流程
Future<void> _initializeApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize core dependency injection (core layer only)
  await setupDependencies();

  // P2-7: 多语言扩展 —— 读取用户上次选择的语言并应用到 LocaleProvider
  try {
    final localeService = getIt<LocaleService>();
    final savedLocale = await localeService.getCurrentLocale();
    if (savedLocale != null) {
      LocaleProvider.instance.setLocale(savedLocale);
    }
  } catch (e) {
    AppLogger.w('Locale', 'Failed to load saved locale', error: e);
  }

  // 修复: Sentry 初始化提前到所有 feature 注册之前，确保注册过程中的异常能被捕获
  await setupSentry();

  // P1 架构修复: FFIBridge.init() 提前到 feature 模块注册之前。
  // 原问题: 多个 feature service（OcrService/VaultService/SpeechToTextService/MathInkService）
  // 依赖 FFIBridge，但 init() 在 feature 注册之后才调用，若注册过程中触发 FFI 调用
  // 会因 isAvailable=false 而失败。
  //
  // FRB v2 迁移: init() 现在调用 RustLib.init() 加载 native 动态库 + 初始化 SSE 编解码器，
  // 然后调用 initEngines() 初始化所有 Rust 核心引擎（持久化/搜索/同步等）。
  try {
    await getIt<FFIBridge>().init();
  } catch (e) {
    AppLogger.w('FFIBridge', 'FFI bridge initialization failed', error: e);
  }

  // features 层依赖由各自模块注册，消除 core → features 反向依赖
  await registerPluginsDependencies();
  await registerSettingsDependencies();
  await registerSyncDependencies();
  await registerWorkflowDependencies();
  await registerAIDependencies();
  await registerEditorDependencies();
  await registerSearchDependencies();
  await registerCanvasDependencies();
  await registerDatabaseDependencies();
  await registerGraphDependencies();
  await registerFlashcardDependencies();
  await registerTemplatesDependencies();
  // Daily Notes 依赖 TemplateService，须在 templates 之后
  await registerNotesDependencies();
  await registerVaultDependencies();
  await registerTodoDependencies();
  await registerWhiteboardDependencies();
  // P2-3: 补全缺失模块注册
  await registerFreeformDependencies();
  await registerKnowledgeDependencies();
  await registerObjectDependencies();

  // P2-5: 初始化本地通知服务（失败时降级为无通知模式，不阻断启动）
  try {
    await getIt<NotificationService>().init();
  } catch (e) {
    AppLogger.w('Notification', 'Notification service initialization failed', error: e);
  }

  // Initialize platform channel
  try {
    final platformChannel = DevNotePlatformChannel();
    final deviceInfo = await platformChannel.getDeviceInfo();
    AppLogger.i('PlatformChannel', 'Platform channel initialized. Device info: $deviceInfo');
  } catch (e) {
    AppLogger.w('PlatformChannel', 'Platform channel initialization failed', error: e);
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

  // P2-2: 路由注册表模式 —— 所有 feature 依赖注册完成后，注册路由配置。
  // 必须在 buildAppRouter() 之前完成，部分路由依赖 getIt 中的服务（SyncBloc/PluginBloc）。
  registerFeatureRoutes();
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
  /// 修复竞态: dispose() 与 didRequestAppExit() 可能并发调用 _disposeAll()，
  /// 通过单例 Future 保证清理逻辑只执行一次，后续调用复用同一 Future。
  /// 避免第二次 getIt.reset() 抛 StateError。
  Future<void>? _disposeFuture;

  /// P2-2: 路由器在 initState 中构建，确保 RouteRegistry 已完成注册。
  /// （_initializeApp 在 runApp 之前完成，initState 在 runApp 之后触发）
  late final GoRouter _appRouter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appRouter = buildAppRouter();
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
  ///
  /// 修复竞态: 通过 _disposeFuture 单例化，确保 _doDisposeAll 只执行一次。
  Future<void> _disposeAll() {
    return _disposeFuture ??= _doDisposeAll();
  }

  Future<void> _doDisposeAll() async {
    // 修复(P2-1): 释放新增 feature 模块资源（逆序，features 在 core 之前释放）
    // P2-5: Todo 模块最后注册，故最先释放（取消所有已调度通知）
    disposeTodoModule();
    // P2-6: 白板模块（无外部资源，仅占位）
    disposeWhiteboardModule();
    // P2-3: 新增模块释放（逆序）
    disposeObjectModule();
    disposeKnowledgeModule();
    disposeFreeformModule();
    // P1-7: Vault 保险库最后注册，故最先释放（锁定以清除内存中的密码）
    disposeVaultModule();
    // P1-3: 模板系统
    disposeTemplatesModule();
    // P2-4: Daily Notes（在 templates 之后释放）
    disposeNotesModule();
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
    // P2-2: 清空路由注册表，避免热重载时重复注册
    RouteRegistry.reset();
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
          routerConfig: _appRouter,
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
