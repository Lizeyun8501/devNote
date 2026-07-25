import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:devnote/core/constants/app_constants.dart';
import 'package:devnote/features/notes/bloc/folder_bloc.dart';
import 'package:devnote/features/notes/bloc/folder_event.dart';
import 'package:devnote/features/notes/bloc/folder_state.dart';
import 'package:devnote/features/notes/widgets/folder_tree.dart';
import 'package:devnote/features/sync/sync_status_widget.dart';

/// 移动端左侧导航抽屉
///
/// 复用顶层 NotesPage 提供的 FolderBloc / SyncBloc，保证桌面端双栏与
/// 移动端抽屉的状态完全一致。点击文件夹后通过 BlocListener 监听选中态
/// 变化自动关闭抽屉，避免遮挡右侧内容。
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    // 监听文件夹选中变化：移动端选中后自动关闭抽屉
    return BlocListener<FolderBloc, FolderState>(
      listenWhen: (prev, next) =>
          prev is FolderLoaded &&
          next is FolderLoaded &&
          prev.selectedFolderId != next.selectedFolderId,
      listener: (context, state) {
        if (Scaffold.of(context).isDrawerOpen) {
          Navigator.of(context).pop();
        }
      },
      child: Drawer(
        // 语义标签：供屏幕阅读器识别
        child: Semantics(
          label: '导航抽屉',
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                const Divider(height: 1),
                _buildQuickActions(context),
                const Divider(height: 1),
                _buildFolderSection(context),
                const Divider(height: 1),
                _buildFooter(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ① Header 区：应用名 + 版本 + 同步状态
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                label: '笔记应用',
                child: Icon(
                  Icons.description_outlined,
                  size: 24,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppConstants.appName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      'v${AppConstants.appVersion}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 紧凑同步状态：复用 SyncStatusWidget
          const Align(
            alignment: Alignment.centerLeft,
            child: SyncStatusWidget(),
          ),
        ],
      ),
    );
  }

  // ② 快速操作区：将桌面端 AppBar 的 IconButton 迁移为 ListTile
  Widget _buildQuickActions(BuildContext context) {
    final actions = <_DrawerAction>[
      _DrawerAction(
        icon: Icons.calendar_today_outlined,
        label: '每日笔记',
        semanticsLabel: 'Daily Notes',
        semanticsHint: '打开每日笔记',
        onTap: () => _navigateAndClose(context, '/daily-notes'),
      ),
      _DrawerAction(
        icon: Icons.search,
        label: '搜索笔记',
        semanticsLabel: '搜索笔记',
        semanticsHint: '搜索你的笔记',
        onTap: () => _navigateAndClose(context, '/search'),
      ),
      _DrawerAction(
        icon: Icons.checklist,
        label: '待办清单',
        semanticsLabel: '待办',
        semanticsHint: '打开全局待办列表',
        onTap: () => _navigateAndClose(context, '/todo'),
      ),
    ];

    return Column(
      children: actions.map((a) => _DrawerActionTile(action: a)).toList(),
    );
  }

  // ③ 文件夹区：复用 FolderTree + 新建文件夹按钮
  Widget _buildFolderSection(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '文件夹',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                Semantics(
                  label: '新建文件夹',
                  hint: '创建新的文件夹',
                  child: IconButton(
                    icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                    tooltip: '新建文件夹',
                    onPressed: () => _showCreateFolderDialog(context),
                  ),
                ),
              ],
            ),
          ),
          // 复用同一组件，BLoC 由顶层 NotesPage 提供
          const Expanded(child: FolderTree()),
        ],
      ),
    );
  }

  // ④ 底部导航区：设置 + 关于
  Widget _buildFooter(BuildContext context) {
    return Column(
      children: [
        _DrawerActionTile(
          action: _DrawerAction(
            icon: Icons.settings_outlined,
            label: '设置',
            semanticsLabel: '设置',
            semanticsHint: '打开设置页面',
            onTap: () => _navigateAndClose(context, '/settings'),
          ),
        ),
        _DrawerActionTile(
          action: _DrawerAction(
            icon: Icons.info_outline,
            label: '关于',
            semanticsLabel: '关于',
            semanticsHint: '查看应用信息',
            onTap: () => _showAboutDialog(context),
          ),
        ),
      ],
    );
  }

  void _navigateAndClose(BuildContext context, String route) {
    Navigator.of(context).pop(); // 先关闭抽屉
    context.go(route);
  }

  void _showAboutDialog(BuildContext context) {
    Navigator.of(context).pop(); // 先关闭抽屉
    // Flutter 3.44.2 的 showAboutDialog 无 applicationDescription 参数，
    // 通过 children 传入应用描述
    showAboutDialog(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: 'v${AppConstants.appVersion}',
      applicationIcon: Icon(
        Icons.description_outlined,
        size: 48,
        color: Theme.of(context).colorScheme.primary,
      ),
      children: [
        const SizedBox(height: 16),
        Text(AppConstants.appDescription),
      ],
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

/// 抽屉内单个操作项的数据模型
class _DrawerAction {
  const _DrawerAction({
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.semanticsHint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semanticsLabel;
  final String semanticsHint;
  final VoidCallback onTap;
}

class _DrawerActionTile extends StatelessWidget {
  const _DrawerActionTile({required this.action});

  final _DrawerAction action;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: action.semanticsLabel,
      hint: action.semanticsHint,
      button: true,
      child: ListTile(
        leading: Icon(action.icon, size: 22),
        title: Text(action.label),
        // 触摸目标 48dp 由 ListTile 默认保证
        onTap: action.onTap,
      ),
    );
  }
}
