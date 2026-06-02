import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:devnote/features/editor/editor_page.dart';
import 'package:devnote/features/notes/notes_page.dart';
import 'package:devnote/features/settings/settings_page.dart';
import 'package:devnote/features/settings/import_export/import_export_page.dart';
import 'package:devnote/features/sync/bloc/sync_bloc.dart';
import 'package:devnote/features/sync/bloc/sync_event.dart';
import 'package:devnote/features/sync/sync_service.dart';
import 'package:devnote/features/sync/sync_settings_page.dart';
import 'package:devnote/features/canvas/canvas_page.dart';
import 'package:devnote/features/sync/conflict_resolution_page.dart';
import 'package:devnote/features/plugins/plugin_marketplace_page.dart';
import 'package:devnote/features/plugins/plugin_settings_page.dart';
import 'package:devnote/features/plugins/bloc/plugin_bloc.dart';
import 'package:devnote/features/plugins/plugin_service.dart';
import 'package:devnote/features/database/database_page.dart';
import 'package:devnote/features/object/object_graph_page.dart';
import 'package:devnote/features/object/object_type_manager_page.dart';

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
        GoRoute(
          path: '/settings/sync',
          pageBuilder: (context, state) => NoTransitionPage(
            child: BlocProvider(
              create: (_) => SyncBloc(SyncService.instance)..add(const StartSync()),
              child: const SyncSettingsPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/sync/conflicts',
          pageBuilder: (context, state) => NoTransitionPage(
            child: BlocProvider(
              create: (_) => SyncBloc(SyncService.instance),
              child: const ConflictResolutionPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/canvas',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: CanvasPage(),
          ),
        ),
        GoRoute(
          path: '/plugins/marketplace',
          pageBuilder: (context, state) => NoTransitionPage(
            child: BlocProvider(
              create: (_) => PluginBloc(PluginService.instance),
              child: const PluginMarketplacePage(),
            ),
          ),
        ),
        GoRoute(
          path: '/plugins/settings',
          pageBuilder: (context, state) => NoTransitionPage(
            child: BlocProvider(
              create: (_) => PluginBloc(PluginService.instance),
              child: const PluginSettingsPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/database/:id',
          pageBuilder: (context, state) => NoTransitionPage(
            child: DatabasePage(
              databaseId: state.pathParameters['id'] ?? '',
            ),
          ),
        ),
        GoRoute(
          path: '/object-graph',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ObjectGraphPage(),
          ),
        ),
        GoRoute(
          path: '/object-types',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ObjectTypeManagerPage(),
          ),
        ),
      ],
    ),
  ],
);
