import 'package:devnote/features/whiteboard/models/whiteboard_element.dart';
import 'package:devnote/features/whiteboard/widgets/whiteboard_toolbar.dart';

/// 白板事件基类
abstract class WhiteboardEvent {}

/// 加载白板（从持久化层或入参恢复元素列表）
class LoadWhiteboard extends WhiteboardEvent {
  final List<WhiteboardElement> elements;
  LoadWhiteboard(this.elements);
}

/// 添加元素
class AddElement extends WhiteboardEvent {
  final WhiteboardElement element;
  AddElement(this.element);
}

/// 更新元素（按 id 替换）
class UpdateElement extends WhiteboardEvent {
  final String id;
  final WhiteboardElement element;
  UpdateElement(this.id, this.element);
}

/// 删除元素
class DeleteElement extends WhiteboardEvent {
  final String id;
  DeleteElement(this.id);
}

/// 选中元素（传 null 表示取消选中）
class SelectElement extends WhiteboardEvent {
  final String? id;
  SelectElement(this.id);
}

/// 清除选择
class ClearSelection extends WhiteboardEvent {}

/// 撤销
class Undo extends WhiteboardEvent {}

/// 重做
class Redo extends WhiteboardEvent {}

/// 清空画布
class ClearCanvas extends WhiteboardEvent {}

/// 切换工具
class ChangeTool extends WhiteboardEvent {
  final WhiteboardTool tool;
  ChangeTool(this.tool);
}

/// 修改当前描边颜色
class ChangeStrokeColor extends WhiteboardEvent {
  final String color;
  ChangeStrokeColor(this.color);
}

/// 修改当前描边宽度
class ChangeStrokeWidth extends WhiteboardEvent {
  final double width;
  ChangeStrokeWidth(this.width);
}

/// 切换网格显示
class ToggleGrid extends WhiteboardEvent {}

/// 导出白板为 JSON 字符串
class ExportWhiteboard extends WhiteboardEvent {}
