import 'package:flutter/material.dart';
import '../models/freeform_element.dart';

class FreeformToolbar extends StatelessWidget {
  final FreeformTool currentTool;
  final void Function(FreeformTool) onToolChanged;
  final void Function(FreeformElementType) onAddElement;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  const FreeformToolbar({
    super.key,
    required this.currentTool,
    required this.onToolChanged,
    required this.onAddElement,
    required this.onUndo,
    required this.onRedo,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildToolButton(FreeformTool.select, Icons.mouse, '选择'),
        _buildToolButton(FreeformTool.text, Icons.text_fields, '文本'),
        _buildToolButton(FreeformTool.stickyNote, Icons.sticky_note_2, '便签'),
        _buildToolButton(FreeformTool.image, Icons.image, '图片'),
        _buildToolButton(FreeformTool.drawing, Icons.draw, '绘图'),
        const VerticalDivider(width: 16),
        IconButton(
          icon: const Icon(Icons.undo),
          onPressed: onUndo,
          tooltip: '撤销',
        ),
        IconButton(
          icon: const Icon(Icons.redo),
          onPressed: onRedo,
          tooltip: '重做',
        ),
      ],
    );
  }

  Widget _buildToolButton(FreeformTool tool, IconData icon, String label) {
    final isSelected = currentTool == tool;
    return Tooltip(
      message: label,
      child: IconButton(
        icon: Icon(icon),
        isSelected: isSelected,
        onPressed: () {
          onToolChanged(tool);
          // 根据工具类型添加元素
          switch (tool) {
            case FreeformTool.text:
              onAddElement(FreeformElementType.text);
            case FreeformTool.stickyNote:
              onAddElement(FreeformElementType.stickyNote);
            case FreeformTool.image:
              onAddElement(FreeformElementType.image);
            case FreeformTool.drawing:
              onAddElement(FreeformElementType.drawing);
            case FreeformTool.select:
              break;
          }
        },
      ),
    );
  }
}

/// 自由画布工具类型
enum FreeformTool { select, text, stickyNote, image, drawing }
