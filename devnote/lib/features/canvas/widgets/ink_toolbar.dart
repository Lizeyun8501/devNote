import 'package:flutter/material.dart';

/// 手写工具类型
enum InkTool { pen, marker, eraser }

/// 手写 Ink 工具栏
///
/// 提供：笔/马克笔/橡皮擦切换、颜色选择、笔触粗细、撤销/重做/清除。
/// 优先适配 iPad + Apple Pencil 和 Surface + Surface Pen。
class InkToolbar extends StatelessWidget {
  final InkTool currentTool;
  final Color currentColor;
  final double currentStrokeWidth;
  final ValueChanged<InkTool> onToolChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;

  const InkToolbar({
    super.key,
    required this.currentTool,
    required this.currentColor,
    required this.currentStrokeWidth,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onStrokeWidthChanged,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
  });

  static const _colors = [
    Color(0xFF000000), // 黑
    Color(0xFFFFFFFF), // 白
    Color(0xFFEF4444), // 红
    Color(0xFF3B82F6), // 蓝
    Color(0xFF10B981), // 绿
    Color(0xFFF59E0B), // 黄
    Color(0xFF8B5CF6), // 紫
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          // 工具选择
          _buildToolButton(context, InkTool.pen, Icons.edit, '笔'),
          _buildToolButton(context, InkTool.marker, Icons.brush, '马克笔'),
          _buildToolButton(context, InkTool.eraser, Icons.auto_fix_high, '橡皮擦'),
          const _VerticalDividerSpacer(),
          // 颜色选择
          for (final color in _colors) _buildColorButton(context, color),
          const _VerticalDividerSpacer(),
          // 笔触粗细
          SizedBox(
            width: 100,
            child: Slider(
              value: currentStrokeWidth,
              min: 1.0,
              max: 10.0,
              divisions: 9,
              onChanged: onStrokeWidthChanged,
            ),
          ),
          const _VerticalDividerSpacer(),
          // 操作按钮
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
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: onClear,
            tooltip: '清除',
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton(BuildContext context, InkTool tool, IconData icon, String label) {
    final isSelected = currentTool == tool;
    return Tooltip(
      message: label,
      child: IconButton(
        icon: Icon(icon),
        isSelected: isSelected,
        onPressed: () => onToolChanged(tool),
        style: isSelected
            ? IconButton.styleFrom(
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
              )
            : null,
      ),
    );
  }

  Widget _buildColorButton(BuildContext context, Color color) {
    final isSelected = currentColor.toARGB32() == color.toARGB32();
    return GestureDetector(
      onTap: () => onColorChanged(color),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey,
            width: isSelected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

/// Wrap 中使用的竖直分隔占位（VerticalDivider 在 Wrap 中需要固定尺寸包装）
class _VerticalDividerSpacer extends StatelessWidget {
  const _VerticalDividerSpacer();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 24,
      child: VerticalDivider(width: 16),
    );
  }
}
