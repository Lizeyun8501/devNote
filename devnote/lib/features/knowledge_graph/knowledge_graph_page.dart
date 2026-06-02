import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/knowledge_graph/bloc/graph_bloc.dart';
import 'package:devnote/features/knowledge_graph/bloc/graph_event.dart';
import 'package:devnote/features/knowledge_graph/bloc/graph_state.dart';
import 'package:devnote/features/knowledge_graph/graph_service.dart';
import 'package:devnote/features/knowledge_graph/widgets/graph_node_widget.dart';
import 'package:devnote/features/knowledge_graph/widgets/graph_edge_widget.dart';
import 'package:devnote/features/knowledge_graph/widgets/graph_filter_panel.dart';
import 'package:go_router/go_router.dart';

class KnowledgeGraphPage extends StatelessWidget {
  const KnowledgeGraphPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => GraphBloc(GraphService())..add(const LoadGraph()),
      child: const _KnowledgeGraphView(),
    );
  }
}

class _KnowledgeGraphView extends StatefulWidget {
  const _KnowledgeGraphView();

  @override
  State<_KnowledgeGraphView> createState() => _KnowledgeGraphViewState();
}

class _KnowledgeGraphViewState extends State<_KnowledgeGraphView> {
  final TransformationController _transformationController = TransformationController();
  Offset _dragOffset = Offset.zero;
  String? _draggingNodeId;
  bool _showFilterPanel = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('知识图谱'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              setState(() {
                _showFilterPanel = !_showFilterPanel;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.hub),
            tooltip: '中心度分析',
            onPressed: () {
              context.read<GraphBloc>().add(const CalculateCentrality());
            },
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: '聚类检测',
            onPressed: () {
              context.read<GraphBloc>().add(const DetectClusters());
            },
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in),
            onPressed: _zoomIn,
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            onPressed: _zoomOut,
          ),
        ],
      ),
      body: BlocBuilder<GraphBloc, GraphState>(
        builder: (context, state) {
          if (state is GraphError) {
            return Center(child: Text('Error: ${state.message}'));
          }
          if (state is GraphLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is GraphLoaded) {
            return Row(
              children: [
                Expanded(
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 0.1,
                    maxScale: 5.0,
                    child: GestureDetector(
                      onTapUp: (_) {
                        context.read<GraphBloc>().add(const SelectGraphNode(null));
                      },
                      child: Container(
                        width: 10000,
                        height: 10000,
                        color: Theme.of(context).colorScheme.surface,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CustomPaint(
                              size: const Size(10000, 10000),
                              painter: _GridPainter(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: 0.2),
                              ),
                            ),
                            ...state.data.edges.map((edge) {
                              final fromPos = state.positions.where((p) => p.nodeId == edge.sourceId);
                              final toPos = state.positions.where((p) => p.nodeId == edge.targetId);
                              if (fromPos.isEmpty || toPos.isEmpty) return const SizedBox.shrink();
                              return GraphEdgeWidget(
                                edge: edge,
                                fromPosition: fromPos.first,
                                toPosition: toPos.first,
                              );
                            }),
                            ...state.data.nodes.map((node) {
                              final pos = state.positions.where((p) => p.nodeId == node.id);
                              if (pos.isEmpty) return const SizedBox.shrink();
                              final isSelected = state.selectedNodeId == node.id;
                              return GraphNodeWidget(
                                node: node,
                                x: pos.first.x,
                                y: pos.first.y,
                                isSelected: isSelected,
                                onTap: () {
                                  context.read<GraphBloc>().add(SelectGraphNode(node.id));
                                },
                                onDragStart: (offset) {
                                  setState(() {
                                    _draggingNodeId = node.id;
                                    _dragOffset = offset;
                                  });
                                },
                                onDragUpdate: (globalPosition) {
                                  if (_draggingNodeId == node.id) {
                                    final transform = _transformationController.value;
                                    final inverse = Matrix4.inverted(transform);
                                    final local = MatrixUtils.transformPoint(inverse, globalPosition);
                                    final dx = local.dx - 60;
                                    final dy = local.dy - 25;
                                    context.read<GraphBloc>().add(MoveGraphNode(
                                          nodeId: node.id,
                                          x: dx,
                                          y: dy,
                                        ));
                                  }
                                },
                                onDragEnd: () {
                                  setState(() {
                                    _draggingNodeId = null;
                                  });
                                },
                              );
                            }),
                            if (state.selectedNodeId != null)
                              _buildNodeDetail(context, state),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_showFilterPanel)
                  GraphFilterPanel(
                    onFilter: (filter) {
                      context.read<GraphBloc>().add(FilterGraph(filter: filter));
                    },
                  ),
              ],
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  Widget _buildNodeDetail(BuildContext context, GraphLoaded state) {
    final selectedNode = state.data.nodes.where((n) => n.id == state.selectedNodeId).firstOrNull;
    if (selectedNode == null) return const SizedBox.shrink();

    final pos = state.positions.where((p) => p.nodeId == selectedNode.id).firstOrNull;
    if (pos == null) return const SizedBox.shrink();

    return Positioned(
      left: pos.x + 70,
      top: pos.y - 40,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                selectedNode.title,
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '类型: ${_typeLabel(selectedNode.nodeType)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (selectedNode.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 4,
                    children: selectedNode.tags
                        .map((t) => Chip(
                              label: Text(t, style: const TextStyle(fontSize: 10)),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      if (selectedNode.nodeType == GraphNodeType.note) {
                        context.push('/notes/${selectedNode.id}');
                      }
                    },
                    child: const Text('打开'),
                  ),
                  TextButton(
                    onPressed: () {
                      context.read<GraphBloc>().add(GetNeighbors(nodeId: selectedNode.id, depth: 2));
                    },
                    child: const Text('展开'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _typeLabel(GraphNodeType type) {
    switch (type) {
      case GraphNodeType.note:
        return '笔记';
      case GraphNodeType.tag:
        return '标签';
      case GraphNodeType.folder:
        return '文件夹';
      case GraphNodeType.canvas:
        return '画布';
    }
  }

  void _zoomIn() {
    final transform = _transformationController.value;
    final newScale = (transform.getMaxScaleOnAxis() * 1.2).clamp(0.1, 5.0);
    _transformationController.value = Matrix4.identity()..scale(newScale);
  }

  void _zoomOut() {
    final transform = _transformationController.value;
    final newScale = (transform.getMaxScaleOnAxis() / 1.2).clamp(0.1, 5.0);
    _transformationController.value = Matrix4.identity()..scale(newScale);
  }
}

class _GridPainter extends CustomPainter {
  final Color color;

  const _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    const step = 50.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
