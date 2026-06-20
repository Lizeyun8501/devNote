import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/features/editor/editor_page.dart';
import 'package:devnote/features/notes/notes_page.dart';
import 'package:devnote/features/notes/daily_notes_page.dart';
import 'package:devnote/features/settings/settings_page.dart';
import 'package:devnote/features/settings/language_settings_page.dart';
import 'package:devnote/features/settings/daily_notes_settings_page.dart';
import 'package:devnote/features/settings/email_settings_page.dart';
import 'package:devnote/features/settings/import_export/import_export_page.dart';
import 'package:devnote/features/settings/import_export/onenote_import_page.dart';
import 'package:devnote/features/sync/bloc/sync_bloc.dart';
import 'package:devnote/features/sync/bloc/sync_event.dart';
import 'package:devnote/features/sync/sync_service.dart';
import 'package:devnote/features/sync/sync_settings_page.dart';
import 'package:devnote/features/canvas/canvas_page.dart';
import 'package:devnote/features/freeform/freeform_page.dart';
import 'package:devnote/features/whiteboard/whiteboard_page.dart';
import 'package:devnote/features/sync/conflict_resolution_page.dart';
import 'package:devnote/features/plugins/plugin_marketplace_page.dart';
import 'package:devnote/features/plugins/plugin_settings_page.dart';
import 'package:devnote/features/plugins/bloc/plugin_bloc.dart';
import 'package:devnote/features/plugins/plugin_service.dart';
import 'package:devnote/features/database/database_page.dart';
import 'package:devnote/features/object/object_graph_page.dart';
import 'package:devnote/features/object/object_type_manager_page.dart';
import 'package:devnote/features/workflow/workflow_settings_page.dart';
import 'package:devnote/features/workflow/git_history_page.dart';
import 'package:devnote/features/knowledge/learning_stats/learning_stats_page.dart';
import 'package:devnote/features/knowledge/learning_stats/learning_report_page.dart';
import 'package:devnote/features/knowledge/knowledge_map/knowledge_map_page.dart';
import 'package:devnote/features/knowledge/dashboard/dashboard_page.dart';
import 'package:devnote/features/knowledge_graph/knowledge_graph_page.dart';
import 'package:devnote/features/flashcard/deck_list_page.dart';
import 'package:devnote/features/flashcard/review_page.dart';
import 'package:devnote/features/flashcard/create_card_page.dart';
import 'package:devnote/features/flashcard/review_stats_page.dart';
import 'package:devnote/features/ai/pages/ai_settings_page.dart';
import 'package:devnote/features/vault/vault_page.dart';
import 'package:devnote/features/todo/todo_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/notes',
  // ============================================================
  // 路由导航守卫 —— 借鉴 Vue Router 的 beforeEach 守卫模式
  // 来源: https://router.vuejs.org/guide/advanced/navigation-guards.html
  // 借鉴内容: 全局前置守卫 (global before guard)，用于权限校验和重定向
  // ============================================================
  redirect: (context, state) {
    final currentPath = state.matchedLocation;
    // 需要同步初始化完成才能访问的受保护路由
    final protectedPaths = [
      '/settings/sync',
      '/sync/conflicts',
      '/canvas',
      '/workflow/settings',
      '/workflow/git-history',
    ];
    final isProtected = protectedPaths.any((p) => currentPath.startsWith(p));
    if (isProtected) {
      // 检查 FFI 桥接是否可用，不可用则重定向到首页
      try {
        final bridge = getIt<FFIBridge>();
        if (!bridge.isAvailable) {
          return '/notes';
        }
      } catch (_) {
        return '/notes';
      }
    }
    return null; // 无需重定向
  },
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
          path: '/daily-notes',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DailyNotesPage(),
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsPage(),
          ),
        ),
        GoRoute(
          path: '/settings/language',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: LanguageSettingsPage(),
          ),
        ),
        GoRoute(
          path: '/settings/daily-notes',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DailyNotesSettingsPage(),
          ),
        ),
        GoRoute(
          path: '/settings/email',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: EmailSettingsPage(),
          ),
        ),
        GoRoute(
          path: '/settings/import-export',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ImportExportPage(),
          ),
        ),
        GoRoute(
          path: '/settings/import/onenote',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: OnenoteImportPage(),
          ),
        ),
        GoRoute(
          path: '/settings/ai',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: AISettingsPage(),
          ),
        ),
        GoRoute(
          path: '/settings/sync',
          pageBuilder: (context, state) => NoTransitionPage(
            child: BlocProvider(
              create: (_) => SyncBloc(getIt<SyncService>())..add(const StartSync()),
              child: const SyncSettingsPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/sync/conflicts',
          pageBuilder: (context, state) => NoTransitionPage(
            child: BlocProvider(
              create: (_) => SyncBloc(getIt<SyncService>()),
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
          path: '/freeform/:id',
          pageBuilder: (context, state) => NoTransitionPage(
            child: FreeformPage(
              pageId: state.pathParameters['id'] ?? '',
              pageTitle: state.uri.queryParameters['title'] ?? '',
            ),
          ),
        ),
        GoRoute(
          path: '/whiteboard/:noteId',
          pageBuilder: (context, state) => NoTransitionPage(
            child: WhiteboardPage(
              noteId: state.pathParameters['noteId'] ?? '',
            ),
          ),
        ),
        GoRoute(
          path: '/plugins/marketplace',
          pageBuilder: (context, state) => NoTransitionPage(
            child: BlocProvider(
              create: (_) => PluginBloc(getIt<PluginService>()),
              child: const PluginMarketplacePage(),
            ),
          ),
        ),
        GoRoute(
          path: '/plugins/settings',
          pageBuilder: (context, state) => NoTransitionPage(
            child: BlocProvider(
              create: (_) => PluginBloc(getIt<PluginService>()),
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
        GoRoute(
          path: '/workflow/settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: WorkflowSettingsPage(),
          ),
        ),
        GoRoute(
          path: '/workflow/git-history',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: GitHistoryPage(),
          ),
        ),
        GoRoute(
          path: '/knowledge/stats',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: LearningStatsPage(),
          ),
        ),
        GoRoute(
          path: '/knowledge/report',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: LearningReportPage(),
          ),
        ),
        GoRoute(
          path: '/knowledge/map',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: KnowledgeMapPage(),
          ),
        ),
        GoRoute(
          path: '/knowledge/dashboard',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DashboardPage(),
          ),
        ),
        GoRoute(
          path: '/knowledge-graph',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: KnowledgeGraphPage(),
          ),
        ),
        GoRoute(
          path: '/flashcard',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DeckListPage(),
          ),
        ),
        GoRoute(
          path: '/flashcard/review/:deckId',
          pageBuilder: (context, state) => NoTransitionPage(
            child: ReviewPage(
              deckId: state.pathParameters['deckId'] ?? '',
            ),
          ),
        ),
        GoRoute(
          path: '/flashcard/create',
          pageBuilder: (context, state) => NoTransitionPage(
            child: CreateCardPage(
              deckId: state.uri.queryParameters['deckId'],
            ),
          ),
        ),
        GoRoute(
          path: '/flashcard/stats/:deckId',
          pageBuilder: (context, state) => NoTransitionPage(
            child: ReviewStatsPage(
              deckId: state.pathParameters['deckId'] ?? '',
            ),
          ),
        ),
        GoRoute(
          path: '/vault',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: VaultPage(),
          ),
        ),
        GoRoute(
          path: '/todo',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: TodoPage(),
          ),
        ),
      ],
    ),
  ],
);
