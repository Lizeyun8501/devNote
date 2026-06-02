import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:devnote/features/editor/editor_page.dart';
import 'package:devnote/features/notes/notes_page.dart';
import 'package:devnote/features/settings/settings_page.dart';
import 'package:devnote/features/settings/import_export/import_export_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/notes',
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return NotesPage(child: child);
      },
      routes: [
        GoRoute(
          path: '/notes',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: NotesListPlaceholder(),
          ),
        ),
        GoRoute(
          path: '/notes/:id',
          pageBuilder: (context, state) => NoTransitionPage(
            child: EditorPage(
              noteId: state.pathParameters['id'] ?? '',
            ),
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsPage(),
          ),
        ),
        GoRoute(
          path: '/settings/import-export',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ImportExportPage(),
          ),
        ),
      ],
    ),
  ],
);
