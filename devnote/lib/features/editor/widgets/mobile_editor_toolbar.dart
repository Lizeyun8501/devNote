import 'package:flutter/material.dart';

/// 移动端优化的编辑器工具栏
/// 横向滚动，大触控目标，常用操作一键访问
class MobileEditorToolbar extends StatelessWidget {
  final Function(String blockType) onInsertBlock;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onShowKeyboard;
  final bool canUndo;
  final bool canRedo;

  const MobileEditorToolbar({
    super.key,
    required this.onInsertBlock,
    this.onUndo,
    this.onRedo,
    this.onShowKeyboard,
    this.canUndo = false,
    this.canRedo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withAlpha(30),
          ),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _buildButton(
            icon: Icons.text_fields,
            label: '文本',
            onTap: () => onInsertBlock('paragraph'),
          ),
          _buildButton(
            icon: Icons.title,
            label: '标题',
            onTap: () => onInsertBlock('heading1'),
          ),
          _buildButton(
            icon: Icons.format_list_bulleted,
            label: '列表',
            onTap: () => onInsertBlock('list'),
          ),
          _buildButton(
            icon: Icons.check_box_outlined,
            label: '待办',
            onTap: () => onInsertBlock('taskListBlock'),
          ),
          _buildButton(
            icon: Icons.code,
            label: '代码',
            onTap: () => onInsertBlock('codeBlock'),
          ),
          _buildButton(
            icon: Icons.format_quote,
            label: '引用',
            onTap: () => onInsertBlock('quote'),
          ),
          _buildButton(
            icon: Icons.image,
            label: '图片',
            onTap: () => onInsertBlock('image'),
          ),
          _buildButton(
            icon: Icons.table_chart,
            label: '表格',
            onTap: () => onInsertBlock('tableBlock'),
          ),
          _buildButton(
            icon: Icons.mic,
            label: '录音',
            onTap: () => onInsertBlock('audio'),
          ),
          const VerticalDivider(width: 16),
          _buildButton(
            icon: Icons.undo,
            label: '撤销',
            onTap: onUndo,
            enabled: canUndo,
          ),
          _buildButton(
            icon: Icons.redo,
            label: '重做',
            onTap: onRedo,
            enabled: canRedo,
          ),
          _buildButton(
            icon: Icons.keyboard_hide,
            label: '键盘',
            onTap: onShowKeyboard,
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    return Tooltip(
      message: label,
      child: IconButton(
        icon: Icon(icon),
        onPressed: enabled ? onTap : null,
        visualDensity: VisualDensity.compact,
        iconSize: 22,
        constraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
      ),
    );
  }
}
