import 'dart:ui';
import '../models/freeform_element.dart';
import '../widgets/freeform_toolbar.dart';

abstract class FreeformEvent {}

class LoadFreeformPage extends FreeformEvent {
  final String pageId;
  LoadFreeformPage(this.pageId);
}

class ChangeTool extends FreeformEvent {
  final FreeformTool tool;
  ChangeTool(this.tool);
}

class AddElement extends FreeformEvent {
  final FreeformElementType type;
  AddElement(this.type);
}

class SelectElement extends FreeformEvent {
  final String elementId;
  SelectElement(this.elementId);
}

class StartEditingElement extends FreeformEvent {
  final String elementId;
  StartEditingElement(this.elementId);
}

class UpdateElement extends FreeformEvent {
  final FreeformElement element;
  UpdateElement(this.element);
}

class EndDragElement extends FreeformEvent {}

class CanvasTap extends FreeformEvent {
  final Offset position;
  CanvasTap(this.position);
}

class UndoFreeform extends FreeformEvent {}

class RedoFreeform extends FreeformEvent {}

class SaveFreeformPage extends FreeformEvent {}
