import 'package:flutter/material.dart';

/// 白板工具枚举
enum WhiteboardTool {
  selection,
  rectangle,
  ellipse,
  diamond,
  line,
  arrow,
  freedraw,
  text,
  eraser,
}

/// 白板工具栏 —— 浮动在画布底部的工具面板
///
/// 包含：
/// - 工具切换按钮（选择 / 矩形 / 椭圆 / 菱形 / 直线 / 箭头 / 自由绘制 / 文本 / 橡皮擦）
/// - 操作按钮（撤销 / 重做 / 清空 / 导出）
/// - 颜色选择器（6 种预设）
/// - 描边宽度滑块（1-10）
/// - 网格开关
class WhiteboardToolbar extends StatelessWidget {
  final WhiteboardTool currentTool;
  final String strokeColor;
  final double strokeWidth;
  final bool showGrid;
  final bool canUndo;
  final bool canRedo;
  final void Function(WhiteboardTool) onToolChanged;
  final void Function(String) onColorChanged;
  final void Function(double) onStrokeWidthChanged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;
  final VoidCallback onExport;
  final VoidCallback onToggleGrid;

  const WhiteboardToolbar({
    super.key,
    required this.currentTool,
    required this.strokeColor,
    required this.strokeWidth,
    required this.showGrid,
    required this.canUndo,
    required this.canRedo,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onStrokeWidthChanged,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    required this.onExport,
    required this.onToggleGrid,
  });

  /// 预设颜色
  static const List<String> presetColors = [
    '#1E1E1E', // 黑
    '#E03131', // 红
    '#2F9E44', // 绿
    '#1971C2', // 蓝
    '#F08C00', // 橙
    '#9C36B5', // 紫
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surface.withValues(alpha: 0.98),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 第一行：工具按钮
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ToolButton(
                    icon: Icons.near_me,
                    label: '选择',
                    isSelected: currentTool == WhiteboardTool.selection,
                    onPressed: () =>
                        onToolChanged(WhiteboardTool.selection),
                  ),
                  _ToolButton(
                    icon: Icons.crop_square,
                    label: '矩形',
                    isSelected: currentTool == WhiteboardTool.rectangle,
                    onPressed: () =>
                        onToolChanged(WhiteboardTool.rectangle),
                  ),
                  _ToolButton(
                    icon: Icons.circle_outlined,
                    label: '椭圆',
                    isSelected: currentTool == WhiteboardTool.ellipse,
                    onPressed: () =>
                        onToolChanged(WhiteboardTool.ellipse),
                  ),
                  _ToolButton(
                    icon: Icons.diamond_outlined,
                    label: '菱形',
                    isSelected: currentTool == WhiteboardTool.diamond,
                    onPressed: () =>
                        onToolChanged(WhiteboardTool.diamond),
                  ),
                  _ToolButton(
                    icon: Icons.show_chart,
                    label: '直线',
                    isSelected: currentTool == WhiteboardTool.line,
                    onPressed: () => onToolChanged(WhiteboardTool.line),
                  ),
                  _ToolButton(
                    icon: Icons.arrow_forward,
                    label: '箭头',
                    isSelected: currentTool == WhiteboardTool.arrow,
                    onPressed: () => onToolChanged(WhiteboardTool.arrow),
                  ),
                  _ToolButton(
                    icon: Icons.brush,
                    label: '自由绘制',
                    isSelected: currentTool == WhiteboardTool.freedraw,
                    onPressed: () =>
                        onToolChanged(WhiteboardTool.freedraw),
                  ),
                  _ToolButton(
                    icon: Icons.text_fields,
                    label: '文本',
                    isSelected: currentTool == WhiteboardTool.text,
                    onPressed: () => onToolChanged(WhiteboardTool.text),
                  ),
                  _ToolButton(
                    icon: Icons.delete_outline,
                    label: '橡皮擦',
                    isSelected: currentTool == WhiteboardTool.eraser,
                    onPressed: () =>
                        onToolChanged(WhiteboardTool.eraser),
                  ),
                  const _Divider(),
                  _ToolButton(
                    icon: Icons.undo,
                    label: '撤销',
                    isEnabled: canUndo,
                    onPressed: onUndo,
                  ),
                  _ToolButton(
                    icon: Icons.redo,
                    label: '重做',
                    isEnabled: canRedo,
                    onPressed: onRedo,
                  ),
                  _ToolButton(
                    icon: Icons.clear,
                    label: '清空',
                    onPressed: onClear,
                  ),
                  _ToolButton(
                    icon: Icons.download,
                    label: '导出',
                    onPressed: onExport,
                  ),
                  _ToolButton(
                    icon: showGrid ? Icons.grid_on : Icons.grid_off,
                    label: showGrid ? '隐藏网格' : '显示网格',
                    isSelected: showGrid,
                    onPressed: onToggleGrid,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // 第二行：颜色选择 + 描边宽度
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...presetColors.map((c) => _ColorChip(
                        color: c,
                        isSelected: strokeColor == c,
                        onTap: () => onColorChanged(c),
                      )),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: Row(
                      children: [
                        const Icon(Icons.line_weight, size: 16),
                        Expanded(
                          child: Slider(
                            value: strokeWidth,
                            min: 1,
                            max: 10,
                            divisions: 9,
                            label: strokeWidth.toStringAsFixed(0),
                            onChanged: onStrokeWidthChanged,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback onPressed;

  const _ToolButton({
    required this.icon,
    required this.label,
    this.isSelected = false,
    this.isEnabled = true,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: IconButton(
        icon: Icon(icon),
        isSelected: isSelected,
        onPressed: isEnabled ? onPressed : null,
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
        style: isSelected
            ? IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primaryContainer,
              )
            : null,
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  final String color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorChip({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = WhiteboardToolbarColorHelper.parse(color);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: isSelected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(context).dividerColor,
    );
  }
}

/// 颜色解析工具（独立类以便测试访问）
class WhiteboardToolbarColorHelper {
  static Color parse(String hex) {
    if (hex == 'transparent' || hex.isEmpty) {
      return const Color(0x00000000);
    }
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }
}
