import 'package:flutter/material.dart';

class BlockToolbar extends StatelessWidget {
  final VoidCallback onInsertParagraph;
  final VoidCallback onInsertHeading;
  final VoidCallback onInsertCodeBlock;
  final VoidCallback onInsertList;
  final VoidCallback onInsertQuote;

  const BlockToolbar({
    super.key,
    required this.onInsertParagraph,
    required this.onInsertHeading,
    required this.onInsertCodeBlock,
    required this.onInsertList,
    required this.onInsertQuote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
              onPressed: onInsertParagraph,
            ),
            _ToolbarButton(
              icon: Icons.title,
              tooltip: 'Heading',
              onPressed: onInsertHeading,
            ),
            _ToolbarButton(
              icon: Icons.code,
              tooltip: 'Code Block',
              onPressed: onInsertCodeBlock,
            ),
            _ToolbarButton(
              icon: Icons.format_list_bulleted,
              tooltip: 'Bullet List',
              onPressed: onInsertList,
            ),
            _ToolbarButton(
              icon: Icons.format_quote,
              tooltip: 'Quote',
              onPressed: onInsertQuote,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}
