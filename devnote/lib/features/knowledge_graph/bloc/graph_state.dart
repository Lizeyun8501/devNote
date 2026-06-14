import 'package:devnote/features/knowledge_graph/graph_service.dart';

class NodePosition {
  final String nodeId;
  final double x;
  final double y;

  const NodePosition({required this.nodeId, required this.x, required this.y});

  NodePosition copyWith({String? nodeId, double? x, double? y}) {
    return NodePosition(
      nodeId: nodeId ?? this.nodeId,
      x: x ?? this.x,
      y: y ?? this.y,
    );
  }
}

sealed class GraphState {
  const GraphState();
}

final class GraphInitial extends GraphState {
  const GraphInitial();
}

final class GraphLoading extends GraphState {
  const GraphLoading();
}

final class GraphLoaded extends GraphState {
  final GraphDataModel data;
  final List<NodePosition> positions;
  final String? selectedNodeId;
  final List<CentralityResult>? centrality;
  final List<ClusterModel>? clusters;

  // 修复：添加 backlinks/shortestPath/relatedNodes 字段，
  // 原 _onGetBacklinks/_onGetShortestPath/_onGetRelatedNodes 调用 service
  // 但从不 emit 结果到状态，导致用户无法看到这些操作的结果
  final List<KnowledgeEdgeModel>? backlinks;
  final List<String>? shortestPath;
  final List<KnowledgeNodeModel>? relatedNodes;

  const GraphLoaded({
    required this.data,
    required this.positions,
    this.selectedNodeId,
    this.centrality,
    this.clusters,
    this.backlinks,
    this.shortestPath,
    this.relatedNodes,
  });

  GraphLoaded copyWith({
    GraphDataModel? data,
    List<NodePosition>? positions,
    Object? selectedNodeId = _graphSentinel,
    List<CentralityResult>? centrality,
    Object? clusters = _graphSentinel,
    Object? backlinks = _graphSentinel,
    Object? shortestPath = _graphSentinel,
    Object? relatedNodes = _graphSentinel,
  }) {
    return GraphLoaded(
      data: data ?? this.data,
      positions: positions ?? this.positions,
      selectedNodeId: selectedNodeId == _graphSentinel ? this.selectedNodeId : selectedNodeId as String?,
      centrality: centrality ?? this.centrality,
      clusters: clusters == _graphSentinel ? this.clusters : clusters as List<ClusterModel>?,
      backlinks: backlinks == _graphSentinel ? this.backlinks : backlinks as List<KnowledgeEdgeModel>?,
      shortestPath: shortestPath == _graphSentinel ? this.shortestPath : shortestPath as List<String>?,
      relatedNodes: relatedNodes == _graphSentinel ? this.relatedNodes : relatedNodes as List<KnowledgeNodeModel>?,
    );
  }
}

const _graphSentinel = Object();

final class GraphError extends GraphState {
  final String message;

  const GraphError(this.message);
}
