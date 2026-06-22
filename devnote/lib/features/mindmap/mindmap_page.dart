import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'bloc/mindmap_bloc.dart';
import 'models/mindmap_node.dart';
import 'widgets/mindmap_canvas.dart';

class MindmapPage extends StatelessWidget {
  final String pageId;
  final String pageTitle;

  const MindmapPage({
    super.key,
    required this.pageId,
    required this.pageTitle,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => MindmapBloc(pageId: pageId)
        ..add(LoadMindmap(pageId))
        ..add(ChangeLayout(MindmapLayoutType.tree)),
      child: BlocBuilder<MindmapBloc, MindmapState>(
        builder: (context, state) {
          return Scaffold(
            appBar: AppBar(
              title: Text(pageTitle),
              actions: [
                // 布局切换
                PopupMenuButton<MindmapLayoutType>(
                  icon: const Icon(Icons.account_tree),
                  tooltip: '布局方式',
                  onSelected: (type) =>
                      context.read<MindmapBloc>().add(ChangeLayout(type)),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: MindmapLayoutType.tree,
                      child: Row(children: [
                        Icon(Icons.account_tree),
                        SizedBox(width: 8),
                        Text('树状布局'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: MindmapLayoutType.radial,
                      child: Row(children: [
                        Icon(Icons.radio_button_unchecked),
                        SizedBox(width: 8),
                        Text('放射布局'),
                      ]),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '添加子节点',
                  onPressed: state is MindmapLoaded && state.selectedNodeId != null
                      ? () => _showAddNodeDialog(context, state.selectedNodeId!)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: '删除节点',
                  onPressed: state is MindmapLoaded &&
                      state.selectedNodeId != null &&
                      state.selectedNodeId != state.data.rootId
                      ? () => context.read<MindmapBloc>().add(
                            DeleteNode(state.selectedNodeId!),
                          )
                      : null,
                ),
              ],
            ),
            body: state is MindmapLoaded
                ? MindmapCanvas(
                    data: state.data,
                    selectedNodeId: state.selectedNodeId,
                    onNodeTap: (id) =>
                        context.read<MindmapBloc>().add(SelectNode(id)),
                    onNodeDoubleTap: (id) =>
                        _showEditNodeDialog(context, id),
                    onCanvasTap: (_) =>
                        context.read<MindmapBloc>().add(SelectNode('')),
                  )
                : const Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }

  void _showAddNodeDialog(BuildContext context, String parentId) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加子节点'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '节点文本',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                final node = MindmapNode(
                  id: const Uuid().v4(),
                  text: controller.text,
                  parentId: parentId,
                  level: (dialogContext.read<MindmapBloc>().state as MindmapLoaded)
                      .data
                      .nodes[parentId]!
                      .level + 1,
                );
                dialogContext.read<MindmapBloc>().add(AddNode(node, parentId));
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _showEditNodeDialog(BuildContext context, String nodeId) {
    final bloc = context.read<MindmapBloc>();
    final state = bloc.state as MindmapLoaded;
    final node = state.data.nodes[nodeId];
    if (node == null) return;

    final controller = TextEditingController(text: node.text);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑节点'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '节点文本',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                bloc.add(UpdateNode(node.copyWith(text: controller.text)));
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
