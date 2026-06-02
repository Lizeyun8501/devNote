import 'package:flutter/material.dart';
import 'package:devnote/core/theme/app_theme.dart';
import 'package:devnote/core/router/app_router.dart';

void main() {
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
