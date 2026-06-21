// Feature 路由集中注册 —— 将各 feature 页面注册到 RouteRegistry。
//
// P2-2 路由层改注册表模式：
//   - 本文件是 features 层 → core 层（RouteRegistry）的合法依赖方向
//   - app_router.dart 不再 import 任何 features 页面，消除反向依赖
//   - 由 main.dart 在所有 register*Dependencies() 之后调用 registerFeatureRoutes()
//
// 组织方式：按 feature 分组，每组注册该 feature 拥有的路由。
// 需要 BlocProvider 的路由在此处创建，依赖 getIt 中已注册的服务。

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/router/route_registry.dart';

// ---- 页面 imports（仅本文件持有，core/router 不再持有） ----
import 'package:devnote/features/notes/notes_page.dart';
import 'package:devnote/features/notes/daily_notes_page.dart';
import 'package:devnote/features/editor/editor_page.dart';
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
import 'package:devnote/features/sync/conflict_resolution_page.dart';
import 'package:devnote/features/canvas/canvas_page.dart';
import 'package:devnote/features/freeform/freeform_page.dart';
import 'package:devnote/features/whiteboard/whiteboard_page.dart';
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

/// 注册所有 feature 路由到 [RouteRegistry]。
///
/// 必须在所有 `register*Dependencies()` 完成后调用（部分路由依赖 getIt 中的服务）。
/// 重复调用会累积重复路由，热重载/测试场景应先调用 [RouteRegistry.reset]。
void registerFeatureRoutes() {
  // Shell 容器：应用主框架（NotesPage 作为 Shell，承载侧边栏 + 子路由内容）
  RouteRegistry.registerShell((context, state, child) {
    return NotesPage(child: child);
  });

  RouteRegistry.registerRoutes([
    // ---- Notes ----
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

    // ---- Settings ----
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

    // ---- Sync（需要 BlocProvider） ----
    GoRoute(
      path: '/settings/sync',
      pageBuilder: (context, state) => NoTransitionPage(
        child: BlocProvider(
          create: (_) =>
              SyncBloc(getIt<SyncService>())..add(const StartSync()),
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

    // ---- Canvas / Freeform / Whiteboard ----
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

    // ---- Plugins（需要 BlocProvider） ----
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

    // ---- Database ----
    GoRoute(
      path: '/database/:id',
      pageBuilder: (context, state) => NoTransitionPage(
        child: DatabasePage(
          databaseId: state.pathParameters['id'] ?? '',
        ),
      ),
    ),

    // ---- Object ----
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

    // ---- Workflow ----
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

    // ---- Knowledge ----
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

    // ---- Knowledge Graph ----
    GoRoute(
      path: '/knowledge-graph',
      pageBuilder: (context, state) => const NoTransitionPage(
        child: KnowledgeGraphPage(),
      ),
    ),

    // ---- Flashcard ----
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

    // ---- Vault ----
    GoRoute(
      path: '/vault',
      pageBuilder: (context, state) => const NoTransitionPage(
        child: VaultPage(),
      ),
    ),

    // ---- Todo ----
    GoRoute(
      path: '/todo',
      pageBuilder: (context, state) => const NoTransitionPage(
        child: TodoPage(),
      ),
    ),
  ]);
}
