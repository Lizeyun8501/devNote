import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/notes/bloc/folder_bloc.dart';
import 'package:devnote/features/notes/bloc/folder_event.dart';
import 'package:devnote/features/notes/bloc/folder_state.dart';

class FolderTree extends StatelessWidget {
  const FolderTree({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FolderBloc, FolderState>(
      builder: (context, state) {
        if (state is FolderLoaded) {
          if (state.rootNodes.isEmpty) {
            return const Center(child: Text('暂无文件夹'));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: state.rootNodes.length,
            itemBuilder: (context, index) {
              return _FolderNodeWidget(
                node: state.rootNodes[index],
                depth: 0,
                selectedFolderId: state.selectedFolderId,
                expandedFolderIds: state.expandedFolderIds,
              );
            },
          );
        }
        if (state is FolderError) {
          return Center(child: Text(state.message));
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}

class _FolderNodeWidget extends StatelessWidget {
  const _FolderNodeWidget({
    required this.node,
    required this.depth,
    required this.selectedFolderId,
    required this.expandedFolderIds,
  });

  final FolderNode node;
  final int depth;
  final String? selectedFolderId;
  final Set<String> expandedFolderIds;

  @override
  Widget build(BuildContext context) {
    final isExpanded = expandedFolderIds.contains(node.folder.id);
    final isSelected = selectedFolderId == node.folder.id;
    final hasChildren = node.children.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FolderTile(
          node: node,
          depth: depth,
          isExpanded: isExpanded,
          isSelected: isSelected,
          hasChildren: hasChildren,
        ),
        if (isExpanded && hasChildren)
          ...node.children.map((child) => _FolderNodeWidget(
                node: child,
                depth: depth + 1,
                selectedFolderId: selectedFolderId,
                expandedFolderIds: expandedFolderIds,
              )),
      ],
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.node,
    required this.depth,
    required this.isExpanded,
    required this.isSelected,
    required this.hasChildren,
  });

  final FolderNode node;
  final int depth;
  final bool isExpanded;
  final bool isSelected;
  final bool hasChildren;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 8.0 + depth * 16.0),
      child: ListTile(
        dense: true,
        selected: isSelected,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.15),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasChildren)
              GestureDetector(
                onTap: () => context.read<FolderBloc>().add(
                      ExpandFolder(
                        folderId: node.folder.id,
                        isExpanded: !isExpanded,
                      ),
                    ),
                child: Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                ),
              )
            else
              const SizedBox(width: 16),
            Icon(
              isExpanded ? Icons.folder_open : Icons.folder_outlined,
              size: 18,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ],
        ),
        title: Text(
          node.folder.name,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isSelected ? Theme.of(context).colorScheme.primary : null,
                fontWeight: isSelected ? FontWeight.w600 : null,
              ),
        ),
        onTap: () => context.read<FolderBloc>().add(SelectFolder(node.folder.id)),
        onLongPress: () => _showContextMenu(context),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height,
        position.dx + size.width,
        position.dy,
      ),
      items: [
        const PopupMenuItem(value: 'create', child: Text('新建子文件夹')),
        const PopupMenuItem(value: 'rename', child: Text('重命名')),
        const PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    ).then((value) {
      if (value == null) return;
      if (!context.mounted) return;
      switch (value) {
        case 'create':
          _showCreateDialog(context);
        case 'rename':
          _showRenameDialog(context);
        case 'delete':
          context.read<FolderBloc>().add(DeleteFolder(node.folder.id));
      }
    });
  }

  void _showCreateDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建子文件夹'),
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
                context.read<FolderBloc>().add(
                      CreateFolder(name: controller.text, parentId: node.folder.id),
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

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: node.folder.name);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                context.read<FolderBloc>().add(
                      RenameFolder(folderId: node.folder.id, newName: controller.text),
                    );
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
