import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:devnote/core/constants/app_constants.dart';

class NotesPage extends StatelessWidget {
  const NotesPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const _DirectoryTreePanel(),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
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
            const Expanded(child: _DirectoryTreeView()),
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
          Icon(
            Icons.description_outlined,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
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
}

class _DirectoryTreeView extends StatelessWidget {
  const _DirectoryTreeView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _DirectoryTile(title: '我的笔记', icon: Icons.folder_outlined, depth: 0),
        _DirectoryTile(title: '工作', icon: Icons.folder_outlined, depth: 1),
        _DirectoryTile(title: '项目文档', icon: Icons.folder_outlined, depth: 2),
        _DirectoryTile(title: '会议记录', icon: Icons.folder_outlined, depth: 2),
        _DirectoryTile(title: '个人', icon: Icons.folder_outlined, depth: 1),
        _DirectoryTile(title: '日记', icon: Icons.folder_outlined, depth: 2),
        _DirectoryTile(title: '收藏', icon: Icons.folder_special_outlined, depth: 0),
      ],
    );
  }
}

class _DirectoryTile extends StatelessWidget {
  const _DirectoryTile({
    required this.title,
    required this.icon,
    required this.depth,
  });

  final String title;
  final IconData icon;
  final int depth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16.0 + depth * 16.0),
      child: ListTile(
        dense: true,
        leading: Icon(icon, size: 18),
        title: Text(title),
        titleTextStyle: Theme.of(context).textTheme.bodyMedium,
        trailing: const Icon(Icons.chevron_right, size: 16),
        onTap: () {},
      ),
    );
  }
}

class NotesListPlaceholder extends StatelessWidget {
  const NotesListPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记列表'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.go('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _NoteCard(title: '欢迎使用 DevNote', summary: '这是一篇示例笔记...', date: '2026-06-02'),
          _NoteCard(title: '项目计划', summary: '第一阶段：基础架构搭建...', date: '2026-06-01'),
          _NoteCard(title: '学习笔记', summary: 'Flutter 状态管理最佳实践...', date: '2026-05-30'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.title,
    required this.summary,
    required this.date,
  });

  final String title;
  final String summary;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                summary,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                date,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
