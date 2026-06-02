import 'package:equatable/equatable.dart';
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

abstract class GraphState extends Equatable {
  const GraphState();

  @override
  List<Object?> get props => [];
}

class GraphInitial extends GraphState {
  const GraphInitial();
}

class GraphLoading extends GraphState {
  const GraphLoading();
}

class GraphLoaded extends GraphState {
  final GraphDataModel data;
  final List<NodePosition> positions;
  final String? selectedNodeId;
  final List<CentralityResult>? centrality;
  final List<ClusterModel>? clusters;

  const GraphLoaded({
    required this.data,
    required this.positions,
    this.selectedNodeId,
    this.centrality,
    this.clusters,
  });

  GraphLoaded copyWith({
    GraphDataModel? data,
    List<NodePosition>? positions,
    String? selectedNodeId,
    List<CentralityResult>? centrality,
    List<ClusterModel>? clusters,
  }) {
    return GraphLoaded(
      data: data ?? this.data,
      positions: positions ?? this.positions,
      selectedNodeId: selectedNodeId ?? this.selectedNodeId,
      centrality: centrality ?? this.centrality,
      clusters: clusters ?? this.clusters,
    );
  }

  @override
  List<Object?> get props => [data, positions, selectedNodeId, centrality, clusters];
}

class GraphError extends GraphState {
  final String message;

  const GraphError(this.message);

  @override
  List<Object?> get props => [message];
}
