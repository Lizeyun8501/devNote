import 'package:flutter/material.dart';

class BlockToolbar extends StatelessWidget {
  final VoidCallback onInsertParagraph;
  final VoidCallback onInsertHeading;
  final VoidCallback onInsertCodeBlock;
  final VoidCallback onInsertList;
  final VoidCallback onInsertQuote;
  final VoidCallback onInsertAudio;

  const BlockToolbar({
    super.key,
    required this.onInsertParagraph,
    required this.onInsertHeading,
    required this.onInsertCodeBlock,
    required this.onInsertList,
    required this.onInsertQuote,
    required this.onInsertAudio,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '编辑器工具栏',
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 1,
            ),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _ToolbarButton(
                icon: Icons.text_fields,
                tooltip: 'Paragraph',
                label: '插入段落',
                onPressed: onInsertParagraph,
              ),
              _ToolbarButton(
                icon: Icons.title,
                tooltip: 'Heading',
                label: '插入标题',
                onPressed: onInsertHeading,
              ),
              _ToolbarButton(
                icon: Icons.code,
                tooltip: 'Code Block',
                label: '插入代码块',
                onPressed: onInsertCodeBlock,
              ),
              _ToolbarButton(
                icon: Icons.format_list_bulleted,
                tooltip: 'Bullet List',
                label: '插入列表',
                onPressed: onInsertList,
              ),
              _ToolbarButton(
                icon: Icons.format_quote,
                tooltip: 'Quote',
                label: '插入引用',
                onPressed: onInsertQuote,
              ),
              _ToolbarButton(
                icon: Icons.mic,
                tooltip: 'Voice Recorder',
                label: '语音速记',
                onPressed: onInsertAudio,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final String label;
  final VoidCallback onPressed;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: IconButton(
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        onPressed: onPressed,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
