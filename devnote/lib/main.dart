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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize dependency injection
  await setupDependencies();

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
class _DevNoteAppState extends State<DevNoteApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disposeAll();
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    // 应用退出前释放所有单例资源
    disposeAll();
    return AppExitResponse.exit;
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
