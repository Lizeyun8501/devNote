import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:devnote/core/constants/app_constants.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/core/persistence/folder_repository.dart';
import 'package:devnote/core/persistence/note_repository.dart';
// P1 修复 (P1-3): 通过 NoteBlockCreationPort 接口依赖 editor 实现，
// 不再直接 import editor 模块，打破 notes ↔ editor 循环依赖。
import 'package:devnote/core/services/note_block_creation_port.dart';
import 'package:devnote/features/notes/bloc/notes_bloc.dart';
import 'package:devnote/features/notes/bloc/notes_event.dart';
import 'package:devnote/features/notes/bloc/folder_bloc.dart';
import 'package:devnote/features/notes/bloc/folder_event.dart';
import 'package:devnote/features/notes/bloc/folder_state.dart';
import 'package:devnote/features/notes/widgets/folder_tree.dart';
import 'package:devnote/features/notes/widgets/note_list.dart';
import 'package:devnote/features/sync/bloc/sync_bloc.dart';
import 'package:devnote/features/sync/sync_service.dart';
import 'package:devnote/features/sync/sync_settings_service.dart';
import 'package:devnote/features/sync/sync_status_widget.dart';
import 'package:devnote/features/templates/template_picker_page.dart';

class NotesPage extends StatelessWidget {
  const NotesPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 修复: 使用 getIt 中的单例 DatabaseHelper,避免每次 rebuild 创建新实例
    final dbHelper = getIt<DatabaseHelper>();
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => FolderBloc(SqliteFolderRepository(dbHelper))..add(const LoadFolders()),
        ),
        BlocProvider(
          // P1 修复 (P1-5): 注入 FolderRepository 和 NoteBlockCreationPort
          // P1 修复 (P1-3): 通过接口注入，不依赖 editor 具体类
          create: (_) => NotesBloc(
            SqliteNoteRepository(dbHelper),
            SqliteFolderRepository(dbHelper),
            getIt<NoteBlockCreationPort>(),
          ),
        ),
        BlocProvider(
          create: (_) => SyncBloc(
            getIt<SyncService>(),
            getIt<SyncSettingsService>(),
          ),
        ),
      ],
      child: Scaffold(
        body: Row(
          children: [
            const _DirectoryTreePanel(),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _DirectoryTreePanel extends StatelessWidget {
  const _DirectoryTreePanel();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppConstants.sidebarWidth,
      child: ColoredBox(
        color: Theme.of(context).navigationRailTheme.backgroundColor ??
            Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            Expanded(
              child: Column(
                children: [
                  const Expanded(child: FolderTree()),
                  const Divider(height: 1),
                  _buildFolderActions(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Semantics(
            label: '笔记列表',
            child: Icon(
              Icons.description_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            AppConstants.appName,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Semantics(
            label: '新建文件夹',
            hint: '创建新的文件夹',
            child: IconButton(
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              tooltip: '新建文件夹',
              onPressed: () => _showCreateFolderDialog(context),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                final currentState = context.read<FolderBloc>().state;
                String? parentId;
                if (currentState is FolderLoaded) {
                  parentId = currentState.selectedFolderId;
                }
                context.read<FolderBloc>().add(
                      CreateFolder(name: controller.text, parentId: parentId),
                    );
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}

class NotesListPlaceholder extends StatelessWidget {
  const NotesListPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<FolderBloc, FolderState>(
      listener: (context, folderState) {
        if (folderState is FolderLoaded && folderState.selectedFolderId != null) {
          context.read<NotesBloc>().add(LoadNotes(folderState.selectedFolderId!));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('笔记列表'),
          actions: [
            const SyncStatusWidget(),
            Semantics(
              label: 'Daily Notes',
              hint: '打开每日笔记',
              child: IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: () => context.go('/daily-notes'),
              ),
            ),
            Semantics(
              label: '搜索笔记',
              hint: '搜索你的笔记',
              child: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => context.go('/search'),
              ),
            ),
            // P2-5: 全局待办/提醒系统入口
            Semantics(
              label: '待办',
              hint: '打开全局待办列表',
              child: IconButton(
                icon: const Icon(Icons.checklist),
                onPressed: () => context.go('/todo'),
              ),
            ),
            Semantics(
              label: '设置',
              hint: '打开设置页面',
              child: IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.go('/settings'),
              ),
            ),
          ],
        ),
        body: const NoteList(),
        floatingActionButton: Semantics(
          label: '新建笔记',
          hint: '创建一条新的笔记',
          child: FloatingActionButton(
            onPressed: () {
              final folderState = context.read<FolderBloc>().state;
              String folderId = '';
              if (folderState is FolderLoaded && folderState.selectedFolderId != null) {
                folderId = folderState.selectedFolderId!;
              }
              // P1-3: 打开模板选择页，选择模板后从模板创建笔记
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TemplatePickerPage(
                    onTemplateSelected: (template) {
                      context.read<NotesBloc>().add(
                            CreateNoteFromTemplate(
                              template: template,
                              folderId: folderId,
                            ),
                          );
                    },
                  ),
                ),
              );
            },
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }
}
