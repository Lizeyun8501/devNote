import 'package:flutter/material.dart';
import 'package:devnote/core/theme/app_theme.dart';
import 'package:devnote/core/router/app_router.dart';
import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/performance/startup_manager.dart';
import 'package:devnote/core/performance/cache_manager.dart';
import 'package:devnote/core/performance/memory_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Rust FFI bridge
  try {
    await FFIBridge.instance.init();
  } catch (e) {
    debugPrint('Warning: FFI bridge initialization failed: $e');
    // Continue without FFI - graceful degradation
  }

  // Initialize performance systems
  await StartupManager.instance.initialize();

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
