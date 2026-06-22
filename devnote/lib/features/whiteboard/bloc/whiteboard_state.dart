import 'package:devnote/features/whiteboard/models/whiteboard_element.dart';
import 'package:devnote/features/whiteboard/widgets/whiteboard_toolbar.dart';

/// 白板状态基类
abstract class WhiteboardState {}

class WhiteboardInitial extends WhiteboardState {}

class WhiteboardLoaded extends WhiteboardState {
  final List<WhiteboardElement> elements;
  final String? selectedElementId;
  final WhiteboardTool currentTool;
  final String strokeColor;
  final double strokeWidth;
  final bool showGrid;
  final List<List<WhiteboardElement>> undoStack;
  final List<List<WhiteboardElement>> redoStack;

  WhiteboardLoaded({
    required this.elements,
    this.selectedElementId,
    this.currentTool = WhiteboardTool.selection,
    this.strokeColor = '#1E1E1E',
    this.strokeWidth = 2,
    this.showGrid = true,
    this.undoStack = const [],
    this.redoStack = const [],
  });

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  WhiteboardLoaded copyWith({
    List<WhiteboardElement>? elements,
    String? selectedElementId,
    bool clearSelection = false,
    WhiteboardTool? currentTool,
    String? strokeColor,
    double? strokeWidth,
    bool? showGrid,
    List<List<WhiteboardElement>>? undoStack,
    List<List<WhiteboardElement>>? redoStack,
  }) =>
      WhiteboardLoaded(
        elements: elements ?? this.elements,
        selectedElementId: clearSelection
            ? null
            : (selectedElementId ?? this.selectedElementId),
        currentTool: currentTool ?? this.currentTool,
        strokeColor: strokeColor ?? this.strokeColor,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        showGrid: showGrid ?? this.showGrid,
        undoStack: undoStack ?? this.undoStack,
        redoStack: redoStack ?? this.redoStack,
      );
}

/// 导出完成状态
class WhiteboardExported extends WhiteboardState {
  final String jsonString;
  WhiteboardExported(this.jsonString);
}

/// 错误状态
class WhiteboardError extends WhiteboardState {
  final String message;
  WhiteboardError(this.message);
}
