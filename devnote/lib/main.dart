import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:devnote/core/theme/app_theme.dart';
import 'package:devnote/core/router/app_router.dart';
import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/performance/startup_manager.dart';
import 'package:devnote/core/performance/cache_manager.dart';
import 'package:devnote/core/performance/memory_manager.dart';
import 'package:devnote/core/i18n/app_localizations.dart' show LocaleProvider;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize dependency injection
  await setupDependencies();

  // Initialize Rust FFI bridge
  try {
    await getIt<FFIBridge>().init();
  } catch (e) {
    debugPrint('Warning: FFI bridge initialization failed: $e');
    // Continue without FFI - graceful degradation
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

class DevNoteApp extends StatelessWidget {
  const DevNoteApp({super.key});

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
