import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/canvas/bloc/canvas_event.dart';
import 'package:devnote/features/canvas/bloc/canvas_state.dart';
import 'package:devnote/features/canvas/canvas_service.dart';
import 'package:uuid/uuid.dart';

class CanvasBloc extends Bloc<CanvasEvent, CanvasState> {
  final CanvasService _canvasService;
  final _uuid = const Uuid();

  CanvasBloc(this._canvasService) : super(const CanvasInitial()) {
    on<LoadCanvas>(_onLoadCanvas);
    on<AddNode>(_onAddNode);
    on<RemoveNode>(_onRemoveNode);
    on<MoveNode>(_onMoveNode);
    on<ResizeNode>(_onResizeNode);
    on<AddEdge>(_onAddEdge);
    on<RemoveEdge>(_onRemoveEdge);
    on<SelectNode>(_onSelectNode);
    on<AutoLayout>(_onAutoLayout);
    on<SaveCanvas>(_onSaveCanvas);
    on<AddInkStroke>(_onAddInkStroke);
    on<UndoInkStroke>(_onUndoInkStroke);
    on<RedoInkStroke>(_onRedoInkStroke);
    on<ClearInkStrokes>(_onClearInkStrokes);
  }

  Future<void> _onLoadCanvas(LoadCanvas event, Emitter<CanvasState> emit) async {
    try {
      final data = await _canvasService.getCanvas(event.canvasId);
      emit(CanvasLoaded(
        canvasId: event.canvasId,
        nodes: data.nodes,
        edges: data.edges,
        inkStrokes: data.inkStrokes,
        undoStack: data.inkStrokes,
      ));
    } catch (e) {
      emit(CanvasError(e.toString()));
    }
  }

  Future<void> _onAddNode(AddNode event, Emitter<CanvasState> emit) async {
    final currentState = state;
    if (currentState is! CanvasLoaded) return;
    try {
      await _canvasService.addNode(currentState.canvasId, event.node);
      emit(currentState.copyWith(
        nodes: [...currentState.nodes, event.node],
      ));
    } catch (e) {
      emit(CanvasError(e.toString()));
    }
  }

  Future<void> _onRemoveNode(RemoveNode event, Emitter<CanvasState> emit) async {
    final currentState = state;
    if (currentState is! CanvasLoaded) return;
    try {
      await _canvasService.removeNode(currentState.canvasId, event.nodeId);
      final updatedNodes = currentState.nodes.where((n) => n.id != event.nodeId).toList();
      final updatedEdges = currentState.edges
          .where((e) => e.fromNode != event.nodeId && e.toNode != event.nodeId)
          .toList();
      emit(currentState.copyWith(
        nodes: updatedNodes,
        edges: updatedEdges,
        selectedNodeId: currentState.selectedNodeId == event.nodeId
            ? null
            : currentState.selectedNodeId,
      ));
    } catch (e) {
      emit(CanvasError(e.toString()));
    }
  }

  Future<void> _onMoveNode(MoveNode event, Emitter<CanvasState> emit) async {
    final currentState = state;
    if (currentState is! CanvasLoaded) return;
    try {
      await _canvasService.moveNode(
        currentState.canvasId,
        event.nodeId,
        event.x,
        event.y,
      );
      final updatedNodes = currentState.nodes
          .map((n) => n.id == event.nodeId ? n.copyWith(x: event.x, y: event.y) : n)
          .toList();
      emit(currentState.copyWith(nodes: updatedNodes));
    } catch (e) {
      emit(CanvasError(e.toString()));
    }
  }

  Future<void> _onResizeNode(ResizeNode event, Emitter<CanvasState> emit) async {
    final currentState = state;
    if (currentState is! CanvasLoaded) return;
    try {
      await _canvasService.resizeNode(
        currentState.canvasId,
        event.nodeId,
        event.width,
        event.height,
      );
      final updatedNodes = currentState.nodes
          .map((n) => n.id == event.nodeId
              ? n.copyWith(width: event.width, height: event.height)
              : n)
          .toList();
      emit(currentState.copyWith(nodes: updatedNodes));
    } catch (e) {
      emit(CanvasError(e.toString()));
    }
  }

  Future<void> _onAddEdge(AddEdge event, Emitter<CanvasState> emit) async {
    final currentState = state;
    if (currentState is! CanvasLoaded) return;
    try {
      await _canvasService.addEdge(currentState.canvasId, event.edge);
      emit(currentState.copyWith(
        edges: [...currentState.edges, event.edge],
      ));
    } catch (e) {
      emit(CanvasError(e.toString()));
    }
  }

  Future<void> _onRemoveEdge(RemoveEdge event, Emitter<CanvasState> emit) async {
    final currentState = state;
    if (currentState is! CanvasLoaded) return;
    try {
      await _canvasService.removeEdge(currentState.canvasId, event.edgeId);
      final updatedEdges = currentState.edges.where((e) => e.id != event.edgeId).toList();
      emit(currentState.copyWith(edges: updatedEdges));
    } catch (e) {
      emit(CanvasError(e.toString()));
    }
  }

  void _onSelectNode(SelectNode event, Emitter<CanvasState> emit) {
    final currentState = state;
    if (currentState is! CanvasLoaded) return;
    emit(currentState.copyWith(selectedNodeId: event.nodeId));
  }

  Future<void> _onAutoLayout(AutoLayout event, Emitter<CanvasState> emit) async {
    final currentState = state;
    if (currentState is! CanvasLoaded) return;
    try {
      final data = await _canvasService.autoLayout(
        currentState.canvasId,
        event.layoutType,
      );
      emit(currentState.copyWith(
        nodes: data.nodes,
        edges: data.edges,
      ));
    } catch (e) {
      emit(CanvasError(e.toString()));
    }
  }

  Future<void> _onSaveCanvas(SaveCanvas event, Emitter<CanvasState> emit) async {
    final currentState = state;
    if (currentState is! CanvasLoaded) return;
    try {
      await _canvasService.saveCanvas(currentState.canvasId, event.path);
    } catch (e) {
      emit(CanvasError(e.toString()));
    }
  }

  // ============================================================
  // Ink 手写笔触处理
  // ============================================================

  void _onAddInkStroke(AddInkStroke event, Emitter<CanvasState> emit) {
    final currentState = state;
    if (currentState is! CanvasLoaded) return;
    emit(currentState.copyWith(
      inkStrokes: [...currentState.inkStrokes, event.stroke],
      undoStack: [...currentState.undoStack, event.stroke],
      redoStack: const [],
    ));
  }

  void _onUndoInkStroke(UndoInkStroke event, Emitter<CanvasState> emit) {
    final currentState = state;
    if (currentState is! CanvasLoaded) return;
    if (currentState.undoStack.isEmpty) return;
    final lastStroke = currentState.undoStack.last;
    final newStrokes =
        currentState.inkStrokes.where((s) => s.id != lastStroke.id).toList();
    emit(currentState.copyWith(
      inkStrokes: newStrokes,
      undoStack:
          currentState.undoStack.sublist(0, currentState.undoStack.length - 1),
      redoStack: [...currentState.redoStack, lastStroke],
    ));
  }

  void _onRedoInkStroke(RedoInkStroke event, Emitter<CanvasState> emit) {
    final currentState = state;
    if (currentState is! CanvasLoaded) return;
    if (currentState.redoStack.isEmpty) return;
    final stroke = currentState.redoStack.last;
    emit(currentState.copyWith(
      inkStrokes: [...currentState.inkStrokes, stroke],
      undoStack: [...currentState.undoStack, stroke],
      redoStack:
          currentState.redoStack.sublist(0, currentState.redoStack.length - 1),
    ));
  }

  void _onClearInkStrokes(ClearInkStrokes event, Emitter<CanvasState> emit) {
    final currentState = state;
    if (currentState is! CanvasLoaded) return;
    emit(currentState.copyWith(
      inkStrokes: const [],
      undoStack: const [],
      redoStack: const [],
    ));
  }

  String generateId() => _uuid.v4();
}
