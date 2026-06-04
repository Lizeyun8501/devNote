import 'package:devnote/features/canvas/canvas_service.dart';

sealed class CanvasState {
  const CanvasState();
}

final class CanvasInitial extends CanvasState {
  const CanvasInitial();
}

final class CanvasLoaded extends CanvasState {
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
}

final class CanvasError extends CanvasState {
  final String message;

  const CanvasError(this.message);
}
