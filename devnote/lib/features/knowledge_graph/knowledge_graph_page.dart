/// 知识图谱页面
///
/// ## 已替换的开源模块
/// - **graphview** ([pub.dev](https://pub.dev/packages/graphview)):
///   已替代自研 CustomPaint + InteractiveViewer + Stack 渲染方案，
///   使用 FruchtermanReingoldAlgorithm 力导向布局（借鉴 d3-force）。
///   graphview 提供更成熟的图可视化能力，支持节点拖拽、缩放、布局算法切换等。
///
/// ## 替换前方案
/// - 自研 InteractiveViewer + CustomPaint（网格背景）+ Stack（节点/边叠加）
/// - 自研 GraphEdgeWidget 绘制边（含箭头、虚线）
/// - 自研 GraphNodeWidget 手动 Positioned 定位 + GestureDetector 拖拽
/// - 自研 _calculateForceLayout 力导向布局算法
///
/// ## 替换后方案
/// - graphview 的 GraphView 组件接管图渲染
/// - FruchtermanReingoldAlgorithm 替代自研力导向布局
/// - graphview 内置 EdgeRenderer 替代自研 GraphEdgeWidget
/// - graphview 内置拖拽替代自研 onDragStart/onDragUpdate/onDragEnd
/// - 仍保留 GraphNodeWidget 用于自定义节点外观
/// - 仍保留 BLoC 架构（GraphBloc + GraphEvent + GraphState）
/// - 仍保留 GraphFilterPanel 侧边栏

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:graphview/GraphView.dart';
import 'package:devnote/features/knowledge_graph/bloc/graph_bloc.dart';
import 'package:devnote/features/knowledge_graph/bloc/graph_event.dart';
import 'package:devnote/features/knowledge_graph/bloc/graph_state.dart';
import 'package:devnote/features/knowledge_graph/graph_service.dart';
import 'package:devnote/features/knowledge_graph/widgets/graph_node_widget.dart';
import 'package:devnote/features/knowledge_graph/widgets/graph_filter_panel.dart';

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
  /// graphview 的图数据对象
  Graph _graph = Graph();

  /// FruchtermanReingold 力导向布局算法（借鉴 d3-force）
  FruchtermanReingoldAlgorithm _algorithm = FruchtermanReingoldAlgorithm(
    FruchtermanReingoldConfiguration(),
  );

  bool _showFilterPanel = false;

  /// 将 GraphState 中的节点/边数据转换为 graphview 的 Graph 对象
  void _buildGraph(GraphLoaded state) {
    _graph = Graph();

    // 添加节点
    for (final node in state.data.nodes) {
      _graph.addNode(Node.Id(node.id));
    }

    // 添加边
    for (final edge in state.data.edges) {
      _graph.addEdge(
        Node.Id(edge.sourceId),
        Node.Id(edge.targetId),
      );
    }

    // 使用 FruchtermanReingold 力导向布局
    // 借鉴 d3-force 的力导向布局思想，graphview 内置实现更成熟
    _algorithm = FruchtermanReingoldAlgorithm(
      FruchtermanReingoldConfiguration(),
    );
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
            // 每次状态更新时重建 graphview 的 Graph 对象
            _buildGraph(state);

            return Row(
              children: [
                Expanded(
                  // graphview 内部已支持缩放与平移，但仍用 InteractiveViewer
                  // 提供更流畅的缩放体验
                  child: InteractiveViewer(
                    minScale: 0.1,
                    maxScale: 5.0,
                    child: GraphView(
                      graph: _graph,
                      algorithm: _algorithm,
                      // 使用透明画笔，因为 graphview 的 EdgeRenderer 已接管边渲染
                      paint: Paint()..color = Colors.transparent,
                      builder: (node) {
                        // 自定义节点渲染：通过 node.key 查找对应的业务数据
                        final nodeId = node.key?.value as String?;
                        if (nodeId == null) return const SizedBox.shrink();

                        final graphNode = state.data.nodes
                            .where((n) => n.id == nodeId)
                            .firstOrNull;
                        if (graphNode == null) return const SizedBox.shrink();

                        final isSelected =
                            state.selectedNodeId == graphNode.id;

                        return GraphNodeWidget(
                          node: graphNode,
                          // graphview 内部管理节点位置，不再需要手动传入 x/y
                          x: 0,
                          y: 0,
                          isSelected: isSelected,
                          onTap: () {
                            context
                                .read<GraphBloc>()
                                .add(SelectGraphNode(graphNode.id));
                          },
                          // 移除 onDragStart/onDragUpdate/onDragEnd，
                          // graphview 内置拖拽支持
                        );
                      },
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
}
