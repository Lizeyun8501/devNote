import 'package:devnote/features/canvas/canvas_service.dart';
import 'package:devnote/features/canvas/models/ink_stroke.dart';

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

  // Ink 手写笔触
  final List<InkStroke> inkStrokes;
  final List<InkStroke> undoStack;
  final List<InkStroke> redoStack;

  const CanvasLoaded({
    required this.canvasId,
    required this.nodes,
    required this.edges,
    this.selectedNodeId,
    this.inkStrokes = const [],
    this.undoStack = const [],
    this.redoStack = const [],
  });

  CanvasLoaded copyWith({
    String? canvasId,
    List<CanvasNodeModel>? nodes,
    List<CanvasEdgeModel>? edges,
    String? selectedNodeId,
    List<InkStroke>? inkStrokes,
    List<InkStroke>? undoStack,
    List<InkStroke>? redoStack,
  }) {
    return CanvasLoaded(
      canvasId: canvasId ?? this.canvasId,
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      selectedNodeId: selectedNodeId ?? this.selectedNodeId,
      inkStrokes: inkStrokes ?? this.inkStrokes,
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
    );
  }
}

final class CanvasError extends CanvasState {
  final String message;

  const CanvasError(this.message);
}
