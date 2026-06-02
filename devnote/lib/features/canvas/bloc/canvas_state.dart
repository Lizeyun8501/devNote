import 'package:equatable/equatable.dart';
import 'package:devnote/features/canvas/canvas_service.dart';

abstract class CanvasState extends Equatable {
  const CanvasState();

  @override
  List<Object?> get props => [];
}

class CanvasInitial extends CanvasState {
  const CanvasInitial();
}

class CanvasLoaded extends CanvasState {
  final String canvasId;
  final List<CanvasNodeModel> nodes;
  final List<CanvasEdgeModel> edges;
  final String? selectedNodeId;

  const CanvasLoaded({
    required this.canvasId,
    required this.nodes,
    required this.edges,
    this.selectedNodeId,
  });

  CanvasLoaded copyWith({
    String? canvasId,
    List<CanvasNodeModel>? nodes,
    List<CanvasEdgeModel>? edges,
    String? selectedNodeId,
  }) {
    return CanvasLoaded(
      canvasId: canvasId ?? this.canvasId,
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      selectedNodeId: selectedNodeId ?? this.selectedNodeId,
    );
  }

  @override
  List<Object?> get props => [canvasId, nodes, edges, selectedNodeId];
}

class CanvasError extends CanvasState {
  final String message;

  const CanvasError(this.message);

  @override
  List<Object?> get props => [message];
}
