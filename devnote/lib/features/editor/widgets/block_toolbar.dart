import 'package:flutter/material.dart';

class BlockToolbar extends StatelessWidget {
  final VoidCallback onInsertParagraph;
  final VoidCallback onInsertHeading;
  final VoidCallback onInsertCodeBlock;
  final VoidCallback onInsertList;
  final VoidCallback onInsertQuote;
  final VoidCallback onInsertAudio;
  final VoidCallback onInsertPdf;
  final VoidCallback onInsertWhiteboard;
  final VoidCallback onTimelineRecord;
  /// P2-9: 公式（手写）按钮 —— 直接弹出 MathInkDialog，插入时创建 latex block
  final VoidCallback onInsertMathInk;
  final bool isTimelineRecording;

  const BlockToolbar({
    super.key,
    required this.onInsertParagraph,
    required this.onInsertHeading,
    required this.onInsertCodeBlock,
    required this.onInsertList,
    required this.onInsertQuote,
    required this.onInsertAudio,
    required this.onInsertPdf,
    required this.onInsertWhiteboard,
    required this.onTimelineRecord,
    required this.onInsertMathInk,
    this.isTimelineRecording = false,
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
              _ToolbarButton(
                icon: Icons.picture_as_pdf,
                tooltip: 'PDF',
                label: '插入 PDF 标注',
                onPressed: onInsertPdf,
              ),
              _ToolbarButton(
                icon: Icons.draw,
                tooltip: 'Whiteboard',
                label: '插入白板',
                onPressed: onInsertWhiteboard,
              ),
              _ToolbarButton(
                icon: Icons.gesture,
                tooltip: 'Formula (Handwriting)',
                label: '公式（手写）',
                onPressed: onInsertMathInk,
              ),
              _ToolbarButton(
                icon: isTimelineRecording ? Icons.stop : Icons.timeline,
                tooltip: isTimelineRecording ? 'Stop Timeline Recording' : 'Timeline Recording',
                label: isTimelineRecording ? '停止时间轴录音' : '时间轴录音',
                onPressed: onTimelineRecord,
                color: isTimelineRecording
                    ? Colors.red
                    : Theme.of(context).colorScheme.onSurfaceVariant,
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
  final Color? color;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.label,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: IconButton(
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        onPressed: onPressed,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
