import 'package:equatable/equatable.dart';
import 'package:devnote/features/canvas/canvas_service.dart';
import 'package:devnote/features/canvas/models/ink_stroke.dart';

abstract class CanvasEvent extends Equatable {
  const CanvasEvent();

  @override
  List<Object?> get props => [];
}

class LoadCanvas extends CanvasEvent {
  final String canvasId;

  const LoadCanvas(this.canvasId);

  @override
  List<Object?> get props => [canvasId];
}

class AddNode extends CanvasEvent {
  final CanvasNodeModel node;

  const AddNode(this.node);

  @override
  List<Object?> get props => [node];
}

class RemoveNode extends CanvasEvent {
  final String nodeId;

  const RemoveNode(this.nodeId);

  @override
  List<Object?> get props => [nodeId];
}

class MoveNode extends CanvasEvent {
  final String nodeId;
  final double x;
  final double y;

  const MoveNode({
    required this.nodeId,
    required this.x,
    required this.y,
  });

  @override
  List<Object?> get props => [nodeId, x, y];
}

class ResizeNode extends CanvasEvent {
  final String nodeId;
  final double width;
  final double height;

  const ResizeNode({
    required this.nodeId,
    required this.width,
    required this.height,
  });

  @override
  List<Object?> get props => [nodeId, width, height];
}

class AddEdge extends CanvasEvent {
  final CanvasEdgeModel edge;

  const AddEdge(this.edge);

  @override
  List<Object?> get props => [edge];
}

class RemoveEdge extends CanvasEvent {
  final String edgeId;

  const RemoveEdge(this.edgeId);

  @override
  List<Object?> get props => [edgeId];
}

class SelectNode extends CanvasEvent {
  final String? nodeId;

  const SelectNode(this.nodeId);

  @override
  List<Object?> get props => [nodeId];
}

class AutoLayout extends CanvasEvent {
  final LayoutType layoutType;

  const AutoLayout(this.layoutType);

  @override
  List<Object?> get props => [layoutType];
}

class SaveCanvas extends CanvasEvent {
  final String path;

  const SaveCanvas(this.path);

  @override
  List<Object?> get props => [path];
}

// ============================================================
// Ink 手写笔触事件
// ============================================================

class AddInkStroke extends CanvasEvent {
  final InkStroke stroke;

  const AddInkStroke(this.stroke);

  @override
  List<Object?> get props => [stroke];
}

class UndoInkStroke extends CanvasEvent {
  const UndoInkStroke();
}

class RedoInkStroke extends CanvasEvent {
  const RedoInkStroke();
}

class ClearInkStrokes extends CanvasEvent {
  const ClearInkStrokes();
}
