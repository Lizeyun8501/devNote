import 'dart:ui';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../models/freeform_element.dart';
import '../widgets/freeform_toolbar.dart';
import 'freeform_event.dart';
import 'freeform_state.dart';

class FreeformBloc extends Bloc<FreeformEvent, FreeformState> {
  final String pageId;

  FreeformBloc({required this.pageId}) : super(FreeformInitial()) {
    on<LoadFreeformPage>(_onLoad);
    on<ChangeTool>(_onChangeTool);
    on<AddElement>(_onAddElement);
    on<SelectElement>(_onSelectElement);
    on<StartEditingElement>(_onStartEditing);
    on<UpdateElement>(_onUpdateElement);
    on<EndDragElement>(_onEndDrag);
    on<CanvasTap>(_onCanvasTap);
    on<UndoFreeform>(_onUndo);
    on<RedoFreeform>(_onRedo);
    on<SaveFreeformPage>(_onSave);
  }

  void _onLoad(LoadFreeformPage event, Emitter<FreeformState> emit) {
    emit(FreeformLoading());
    // TODO: 从持久化层加载 FreeformPageData
    // 当前创建空页面
    emit(
      FreeformLoaded(
        data: FreeformPageData(
          id: event.pageId,
          title: '',
          elements: [],
        ),
      ),
    );
  }

  void _onChangeTool(ChangeTool event, Emitter<FreeformState> emit) {
    final state = this.state;
    if (state is FreeformLoaded) {
      emit(state.copyWith(currentTool: event.tool));
    }
  }

  void _onAddElement(AddElement event, Emitter<FreeformState> emit) {
    final state = this.state;
    if (state is! FreeformLoaded) return;

    final element = FreeformElement(
      id: const Uuid().v4(),
      type: event.type,
      position: const Offset(100, 100), // 默认位置
      size: _getDefaultSize(event.type),
      content: '',
    );

    final newData = state.data.copyWith(
      elements: [...state.data.elements, element],
    );

    emit(
      state.copyWith(
        data: newData,
        selectedElementId: element.id,
        editingElementId: element.id,
        undoStack: [...state.undoStack, state.data],
        redoStack: [],
      ),
    );
  }

  Size _getDefaultSize(FreeformElementType type) {
    switch (type) {
      case FreeformElementType.text:
        return const Size(200, 60);
      case FreeformElementType.richText:
        return const Size(300, 150);
      case FreeformElementType.image:
        return const Size(200, 200);
      case FreeformElementType.stickyNote:
        return const Size(180, 180);
      case FreeformElementType.drawing:
        return const Size(250, 250);
      case FreeformElementType.audio:
        return const Size(200, 60);
      case FreeformElementType.link:
        return const Size(250, 60);
      case FreeformElementType.embed:
        return const Size(300, 200);
    }
  }

  void _onSelectElement(SelectElement event, Emitter<FreeformState> emit) {
    final state = this.state;
    if (state is! FreeformLoaded) return;
    emit(
      state.copyWith(
        selectedElementId: event.elementId,
        clearEditing: true,
      ),
    );
  }

  void _onStartEditing(
    StartEditingElement event,
    Emitter<FreeformState> emit,
  ) {
    final state = this.state;
    if (state is! FreeformLoaded) return;
    emit(
      state.copyWith(
        selectedElementId: event.elementId,
        editingElementId: event.elementId,
      ),
    );
  }

  void _onUpdateElement(UpdateElement event, Emitter<FreeformState> emit) {
    final state = this.state;
    if (state is! FreeformLoaded) return;

    final newElements = state.data.elements.map((e) {
      return e.id == event.element.id ? event.element : e;
    }).toList();

    emit(
      state.copyWith(data: state.data.copyWith(elements: newElements)),
    );
  }

  void _onEndDrag(EndDragElement event, Emitter<FreeformState> emit) {
    final state = this.state;
    if (state is! FreeformLoaded) return;
    // 拖拽结束时保存到 undoStack
    emit(
      state.copyWith(
        undoStack: [...state.undoStack, state.data],
        redoStack: [],
      ),
    );
  }

  void _onCanvasTap(CanvasTap event, Emitter<FreeformState> emit) {
    final state = this.state;
    if (state is! FreeformLoaded) return;
    // 点击空白处取消选择
    emit(state.copyWith(clearSelection: true, clearEditing: true));
  }

  void _onUndo(UndoFreeform event, Emitter<FreeformState> emit) {
    final state = this.state;
    if (state is! FreeformLoaded || state.undoStack.isEmpty) return;

    final previous = state.undoStack.last;
    emit(
      state.copyWith(
        data: previous,
        undoStack: state.undoStack.sublist(0, state.undoStack.length - 1),
        redoStack: [...state.redoStack, state.data],
        clearSelection: true,
        clearEditing: true,
      ),
    );
  }

  void _onRedo(RedoFreeform event, Emitter<FreeformState> emit) {
    final state = this.state;
    if (state is! FreeformLoaded || state.redoStack.isEmpty) return;

    final next = state.redoStack.last;
    emit(
      state.copyWith(
        data: next,
        redoStack: state.redoStack.sublist(0, state.redoStack.length - 1),
        undoStack: [...state.undoStack, state.data],
        clearSelection: true,
        clearEditing: true,
      ),
    );
  }

  void _onSave(SaveFreeformPage event, Emitter<FreeformState> emit) {
    final state = this.state;
    if (state is! FreeformLoaded) return;
    // TODO: 持久化 FreeformPageData
    // 将 data.toJsonString() 存入笔记的 content 字段
  }
}
