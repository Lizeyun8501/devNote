import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/whiteboard/bloc/whiteboard_event.dart';
import 'package:devnote/features/whiteboard/bloc/whiteboard_state.dart';
import 'package:devnote/features/whiteboard/models/whiteboard_element.dart';

/// 白板 BLoC —— 维护元素列表、选中状态、撤销/重做历史
///
/// 历史栈策略：
/// - 每次会改变 elements 的操作前，将当前 elements 压入 undoStack，并清空 redoStack
/// - Undo：从 undoStack 弹出 → 当前 elements 压入 redoStack
/// - Redo：从 redoStack 弹出 → 当前 elements 压入 undoStack
class WhiteboardBloc extends Bloc<WhiteboardEvent, WhiteboardState> {
  WhiteboardBloc() : super(WhiteboardInitial()) {
    on<LoadWhiteboard>(_onLoad);
    on<AddElement>(_onAddElement);
    on<UpdateElement>(_onUpdateElement);
    on<DeleteElement>(_onDeleteElement);
    on<SelectElement>(_onSelectElement);
    on<ClearSelection>(_onClearSelection);
    on<Undo>(_onUndo);
    on<Redo>(_onRedo);
    on<ClearCanvas>(_onClearCanvas);
    on<ChangeTool>(_onChangeTool);
    on<ChangeStrokeColor>(_onChangeStrokeColor);
    on<ChangeStrokeWidth>(_onChangeStrokeWidth);
    on<ToggleGrid>(_onToggleGrid);
    on<ExportWhiteboard>(_onExport);
  }

  void _onLoad(LoadWhiteboard event, Emitter<WhiteboardState> emit) {
    emit(WhiteboardLoaded(elements: List.of(event.elements)));
  }

  /// 构建新的历史栈：将当前元素列表快照压入 undoStack，清空 redoStack
  ({List<List<WhiteboardElement>> undo, List<List<WhiteboardElement>> redo})
      _snapshotHistory(WhiteboardLoaded state) {
    return (
      undo: [...state.undoStack, List.of(state.elements)],
      redo: const <List<WhiteboardElement>>[],
    );
  }

  void _onAddElement(AddElement event, Emitter<WhiteboardState> emit) {
    final state = this.state;
    if (state is! WhiteboardLoaded) return;
    final history = _snapshotHistory(state);
    emit(
      state.copyWith(
        elements: [...state.elements, event.element],
        selectedElementId: event.element.id,
        undoStack: history.undo,
        redoStack: history.redo,
      ),
    );
  }

  void _onUpdateElement(UpdateElement event, Emitter<WhiteboardState> emit) {
    final state = this.state;
    if (state is! WhiteboardLoaded) return;
    final newElements = state.elements
        .map((e) => e.id == event.id ? event.element : e)
        .toList();
    emit(state.copyWith(elements: newElements));
  }

  void _onDeleteElement(DeleteElement event, Emitter<WhiteboardState> emit) {
    final state = this.state;
    if (state is! WhiteboardLoaded) return;
    final history = _snapshotHistory(state);
    final newElements =
        state.elements.where((e) => e.id != event.id).toList();
    emit(
      state.copyWith(
        elements: newElements,
        clearSelection: state.selectedElementId == event.id,
        undoStack: history.undo,
        redoStack: history.redo,
      ),
    );
  }

  void _onSelectElement(SelectElement event, Emitter<WhiteboardState> emit) {
    final state = this.state;
    if (state is! WhiteboardLoaded) return;
    emit(state.copyWith(selectedElementId: event.id));
  }

  void _onClearSelection(ClearSelection event, Emitter<WhiteboardState> emit) {
    final state = this.state;
    if (state is! WhiteboardLoaded) return;
    emit(state.copyWith(clearSelection: true));
  }

  void _onUndo(Undo event, Emitter<WhiteboardState> emit) {
    final state = this.state;
    if (state is! WhiteboardLoaded || state.undoStack.isEmpty) return;
    final previous = state.undoStack.last;
    final newUndo = List<List<WhiteboardElement>>.from(state.undoStack)
      ..removeLast();
    final newRedo = List<List<WhiteboardElement>>.from(state.redoStack)
      ..add(List.of(state.elements));
    emit(
      state.copyWith(
        elements: previous,
        undoStack: newUndo,
        redoStack: newRedo,
        clearSelection: true,
      ),
    );
  }

  void _onRedo(Redo event, Emitter<WhiteboardState> emit) {
    final state = this.state;
    if (state is! WhiteboardLoaded || state.redoStack.isEmpty) return;
    final next = state.redoStack.last;
    final newRedo = List<List<WhiteboardElement>>.from(state.redoStack)
      ..removeLast();
    final newUndo = List<List<WhiteboardElement>>.from(state.undoStack)
      ..add(List.of(state.elements));
    emit(
      state.copyWith(
        elements: next,
        undoStack: newUndo,
        redoStack: newRedo,
        clearSelection: true,
      ),
    );
  }

  void _onClearCanvas(ClearCanvas event, Emitter<WhiteboardState> emit) {
    final state = this.state;
    if (state is! WhiteboardLoaded) return;
    if (state.elements.isEmpty) return;
    final history = _snapshotHistory(state);
    emit(
      state.copyWith(
        elements: const [],
        clearSelection: true,
        undoStack: history.undo,
        redoStack: history.redo,
      ),
    );
  }

  void _onChangeTool(ChangeTool event, Emitter<WhiteboardState> emit) {
    final state = this.state;
    if (state is! WhiteboardLoaded) return;
    emit(state.copyWith(currentTool: event.tool));
  }

  void _onChangeStrokeColor(
      ChangeStrokeColor event, Emitter<WhiteboardState> emit) {
    final state = this.state;
    if (state is! WhiteboardLoaded) return;
    emit(state.copyWith(strokeColor: event.color));
  }

  void _onChangeStrokeWidth(
      ChangeStrokeWidth event, Emitter<WhiteboardState> emit) {
    final state = this.state;
    if (state is! WhiteboardLoaded) return;
    emit(state.copyWith(strokeWidth: event.width));
  }

  void _onToggleGrid(ToggleGrid event, Emitter<WhiteboardState> emit) {
    final state = this.state;
    if (state is! WhiteboardLoaded) return;
    emit(state.copyWith(showGrid: !state.showGrid));
  }

  void _onExport(ExportWhiteboard event, Emitter<WhiteboardState> emit) {
    final state = this.state;
    if (state is! WhiteboardLoaded) return;
    final json = WhiteboardSerializer.encode(state.elements);
    emit(WhiteboardExported(json));
    // 立即恢复到 Loaded 状态，避免后续事件无法处理
    emit(state);
  }
}
