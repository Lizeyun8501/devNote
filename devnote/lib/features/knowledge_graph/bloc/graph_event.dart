import 'package:equatable/equatable.dart';
import 'package:devnote/features/knowledge_graph/graph_service.dart';

abstract class GraphEvent extends Equatable {
  const GraphEvent();

  @override
  List<Object?> get props => [];
}

class LoadGraph extends GraphEvent {
  const LoadGraph();
}

class GetNeighbors extends GraphEvent {
  final String nodeId;
  final int depth;

  const GetNeighbors({required this.nodeId, this.depth = 1});

  @override
  List<Object?> get props => [nodeId, depth];
}

class GetBacklinks extends GraphEvent {
  final String noteId;

  const GetBacklinks({required this.noteId});

  @override
  List<Object?> get props => [noteId];
}

class GetShortestPath extends GraphEvent {
  final String fromId;
  final String toId;

  const GetShortestPath({required this.fromId, required this.toId});

  @override
  List<Object?> get props => [fromId, toId];
}

class GetRelatedNodes extends GraphEvent {
  final String nodeId;
  final int limit;

  const GetRelatedNodes({required this.nodeId, this.limit = 10});

  @override
  List<Object?> get props => [nodeId, limit];
}

class FilterGraph extends GraphEvent {
  final GraphFilterModel filter;

  const FilterGraph({required this.filter});

  @override
  List<Object?> get props => [filter];
}

class CalculateCentrality extends GraphEvent {
  const CalculateCentrality();
}

class DetectClusters extends GraphEvent {
  const DetectClusters();
}

class SelectGraphNode extends GraphEvent {
  final String? nodeId;

  const SelectGraphNode(this.nodeId);

  @override
  List<Object?> get props => [nodeId];
}

class MoveGraphNode extends GraphEvent {
  final String nodeId;
  final double x;
  final double y;

  const MoveGraphNode({required this.nodeId, required this.x, required this.y});

  @override
  List<Object?> get props => [nodeId, x, y];
}
