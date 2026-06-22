import '../models/freeform_element.dart';
import '../widgets/freeform_toolbar.dart';

abstract class FreeformState {}

class FreeformInitial extends FreeformState {}

class FreeformLoading extends FreeformState {}

class FreeformLoaded extends FreeformState {
  final FreeformPageData data;
  final String? selectedElementId;
  final String? editingElementId;
  final FreeformTool currentTool;
  final List<FreeformPageData> undoStack;
  final List<FreeformPageData> redoStack;

  FreeformLoaded({
    required this.data,
    this.selectedElementId,
    this.editingElementId,
    this.currentTool = FreeformTool.select,
    this.undoStack = const [],
    this.redoStack = const [],
  });

  FreeformLoaded copyWith({
    FreeformPageData? data,
    String? selectedElementId,
    String? editingElementId,
    FreeformTool? currentTool,
    List<FreeformPageData>? undoStack,
    List<FreeformPageData>? redoStack,
    bool clearSelection = false,
    bool clearEditing = false,
  }) =>
      FreeformLoaded(
        data: data ?? this.data,
        selectedElementId: clearSelection
            ? null
            : (selectedElementId ?? this.selectedElementId),
        editingElementId: clearEditing
            ? null
            : (editingElementId ?? this.editingElementId),
        currentTool: currentTool ?? this.currentTool,
        undoStack: undoStack ?? this.undoStack,
        redoStack: redoStack ?? this.redoStack,
      );
}

class FreeformError extends FreeformState {
  final String message;
  FreeformError(this.message);
}
