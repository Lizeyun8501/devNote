import 'package:flutter/material.dart';
import 'package:devnote/core/theme/app_theme.dart';
import 'package:devnote/core/router/app_router.dart';
import 'package:devnote/core/performance/startup_manager.dart';
import 'package:devnote/core/performance/cache_manager.dart';
import 'package:devnote/core/performance/memory_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final startupManager = StartupManager();

  startupManager.registerCritical('initTheme', () async {
    AppTheme.lightTheme;
    AppTheme.darkTheme;
  });

  startupManager.registerCritical('initRouter', () async {
    appRouter;
  });

  startupManager.registerNormal('initCache', () async {
    final cacheManager = CacheManager();
    cacheManager.configure(CacheType.noteContent, maxSize: 50, ttl: const Duration(minutes: 30));
    cacheManager.configure(CacheType.image, maxSize: 100, ttl: const Duration(hours: 1));
    cacheManager.configure(CacheType.searchResult, maxSize: 30, ttl: const Duration(minutes: 10));
  });

  startupManager.registerLazy('initMemoryManager', () async {
    MemoryManager().setMemoryLimit(100 * 1024 * 1024);
  });

  await startupManager.runStartup();

  runApp(const DevNoteApp());
}

class DevNoteApp extends StatelessWidget {
  const DevNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'DevNote',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
