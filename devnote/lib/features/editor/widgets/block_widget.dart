import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import 'package:devnote/features/editor/models/timeline_marker.dart';
import 'package:devnote/features/editor/widgets/audio_block_widget.dart';
import 'package:devnote/features/editor/widgets/code_block_widget.dart';
import 'package:devnote/features/editor/widgets/latex_block_widget.dart';
import 'package:devnote/features/editor/widgets/table_block_widget.dart';
import 'package:devnote/features/editor/widgets/task_list_widget.dart';
import 'package:devnote/features/editor/widgets/timeline_audio_player.dart';

class BlockWidget extends StatefulWidget {
  final BlockModel block;
  final bool isActive;
  final ValueChanged<String> onContentChanged;
  final VoidCallback onDelete;
  final ValueChanged<BlockType> onTypeChanged;
  final VoidCallback onEnterPressed;
  final VoidCallback onBackspaceAtStart;

  /// 点击时间轴标记时回调，参数为关联的文本块 ID（用于滚动定位）
  final ValueChanged<String>? onTimelineMarkerTap;

  const BlockWidget({
    super.key,
    required this.block,
    required this.isActive,
    required this.onContentChanged,
    required this.onDelete,
    required this.onTypeChanged,
    required this.onEnterPressed,
    required this.onBackspaceAtStart,
    this.onTimelineMarkerTap,
  });

  @override
  State<BlockWidget> createState() => _BlockWidgetState();
}

class _BlockWidgetState extends State<BlockWidget> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.block.content);
    _focusNode = FocusNode();
    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant BlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.content != widget.block.content &&
        _controller.text != widget.block.content) {
      _controller.text = widget.block.content;
    }
    if (widget.isActive && !oldWidget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  TextStyle _getTextStyle(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodyLarge!;
    switch (widget.block.blockType) {
      case BlockType.heading1:
        return baseStyle.copyWith(fontSize: 28, fontWeight: FontWeight.bold);
      case BlockType.heading2:
        return baseStyle.copyWith(fontSize: 24, fontWeight: FontWeight.bold);
      case BlockType.heading3:
        return baseStyle.copyWith(fontSize: 20, fontWeight: FontWeight.bold);
      case BlockType.heading4:
        return baseStyle.copyWith(fontSize: 18, fontWeight: FontWeight.bold);
      case BlockType.heading5:
        return baseStyle.copyWith(fontSize: 16, fontWeight: FontWeight.bold);
      case BlockType.heading6:
        return baseStyle.copyWith(fontSize: 14, fontWeight: FontWeight.bold);
      case BlockType.codeBlock:
        return TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          color: Theme.of(context).colorScheme.onSurface,
        );
      case BlockType.quote:
        return baseStyle.copyWith(
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
      default:
        return baseStyle;
    }
  }

  EdgeInsets _getPadding() {
    switch (widget.block.blockType) {
      case BlockType.heading1:
      case BlockType.heading2:
      case BlockType.heading3:
        return const EdgeInsets.symmetric(vertical: 8);
      case BlockType.codeBlock:
        return const EdgeInsets.all(12);
      case BlockType.quote:
        return const EdgeInsets.symmetric(vertical: 4, horizontal: 16);
      default:
        return const EdgeInsets.symmetric(vertical: 2);
    }
  }

  BoxDecoration _getDecoration(BuildContext context) {
    switch (widget.block.blockType) {
      case BlockType.codeBlock:
        return BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E1E32)
              : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        );
      case BlockType.quote:
        return BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 3,
            ),
          ),
        );
      default:
        return const BoxDecoration();
    }
  }

  String _getHintText() {
    switch (widget.block.blockType) {
      case BlockType.heading1:
        return 'Heading 1';
      case BlockType.heading2:
        return 'Heading 2';
      case BlockType.heading3:
        return 'Heading 3';
      case BlockType.heading4:
        return 'Heading 4';
      case BlockType.heading5:
        return 'Heading 5';
      case BlockType.heading6:
        return 'Heading 6';
      case BlockType.codeBlock:
        return 'Code';
      case BlockType.quote:
        return 'Quote';
      case BlockType.list:
      case BlockType.orderedList:
        return 'List item';
      case BlockType.latexBlock:
        return 'LaTeX formula';
      case BlockType.tableBlock:
        return 'Table';
      case BlockType.taskListBlock:
        return 'Task';
      default:
        return 'Type something...';
    }
  }

  Widget _buildBlockPrefix(BuildContext context) {
    if (widget.block.blockType == BlockType.list) {
      return Padding(
        padding: const EdgeInsets.only(right: 8, top: 12),
        child: Icon(
          Icons.circle,
          size: 6,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    if (widget.block.blockType == BlockType.orderedList) {
      return Padding(
        padding: const EdgeInsets.only(right: 8, top: 12),
        child: Text(
          '${widget.block.position + 1}.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  bool _isSpecialBlock() {
    switch (widget.block.blockType) {
      case BlockType.codeBlock:
      case BlockType.latexBlock:
      case BlockType.tableBlock:
      case BlockType.taskListBlock:
      case BlockType.audio:
        return true;
      default:
        return false;
    }
  }

  Widget _buildSpecialBlock() {
    switch (widget.block.blockType) {
      case BlockType.codeBlock:
        return CodeBlockWidget(
          content: widget.block.content,
          language: widget.block.language,
          onContentChanged: widget.onContentChanged,
        );
      case BlockType.latexBlock:
        return LatexBlockWidget(
          content: widget.block.content,
          onContentChanged: widget.onContentChanged,
        );
      case BlockType.tableBlock:
        return TableBlockWidget(
          content: widget.block.content,
          onContentChanged: widget.onContentChanged,
        );
      case BlockType.taskListBlock:
        return TaskListWidget(
          content: widget.block.content,
          onContentChanged: widget.onContentChanged,
        );
      case BlockType.audio:
        return _buildAudioBlock();
      default:
        return const SizedBox.shrink();
    }
  }

  /// 渲染音频块：若 content JSON 包含时间轴 markers，使用 TimelineAudioPlayer；
  /// 否则回退到普通 AudioBlockWidget（向后兼容 P0-3 已有录音）
  Widget _buildAudioBlock() {
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(widget.block.content) as Map<String, dynamic>;
    } catch (_) {
      data = null;
    }
    final markersJson = data?['markers'] as List?;
    if (markersJson != null && markersJson.isNotEmpty) {
      final markers = markersJson
          .map((e) => TimelineMarker.fromJson(e as Map<String, dynamic>))
          .toList();
      return TimelineAudioPlayer(
        audioPath: data?['url'] as String? ?? '',
        durationMs: (data?['duration_ms'] as num?)?.toInt() ?? 0,
        transcript: data?['transcript'] as String? ?? '',
        markers: markers,
        onMarkerTap: widget.onTimelineMarkerTap,
      );
    }
    return AudioBlockWidget(
      content: widget.block.content,
      onContentChanged: widget.onContentChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isSpecialBlock()) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: MouseRegion(
          cursor: SystemMouseCursors.text,
          child: GestureDetector(
            onDoubleTap: () => _showTypeMenu(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSpecialBlock(),
                if (widget.isActive)
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: const Icon(Icons.drag_handle, size: 16),
                      onPressed: () => _showBlockActions(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: GestureDetector(
          onDoubleTap: () => _showTypeMenu(context),
          child: Container(
            decoration: _getDecoration(context),
            padding: _getPadding(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBlockPrefix(context),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: _getTextStyle(context),
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: _getHintText(),
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: widget.onContentChanged,
                    onSubmitted: (_) => widget.onEnterPressed,
                  ),
                ),
                if (widget.isActive)
                  IconButton(
                    icon: const Icon(Icons.drag_handle, size: 16),
                    onPressed: () => _showBlockActions(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    color: Theme.of(context).colorScheme.outline,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBlockActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete Block'),
              onTap: () {
                Navigator.pop(context);
                widget.onDelete();
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_vert),
              title: const Text('Change Type'),
              onTap: () {
                Navigator.pop(context);
                _showTypeMenu(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTypeMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    showMenu<BlockType>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + renderBox.size.height,
        offset.dx + renderBox.size.width,
        offset.dy,
      ),
      items: [
        const PopupMenuItem(value: BlockType.paragraph, child: Text('Paragraph')),
        const PopupMenuItem(value: BlockType.heading1, child: Text('Heading 1')),
        const PopupMenuItem(value: BlockType.heading2, child: Text('Heading 2')),
        const PopupMenuItem(value: BlockType.heading3, child: Text('Heading 3')),
        const PopupMenuItem(value: BlockType.codeBlock, child: Text('Code Block')),
        const PopupMenuItem(value: BlockType.quote, child: Text('Quote')),
        const PopupMenuItem(value: BlockType.list, child: Text('Bullet List')),
        const PopupMenuItem(value: BlockType.orderedList, child: Text('Ordered List')),
        const PopupMenuItem(value: BlockType.tableBlock, child: Text('Table')),
        const PopupMenuItem(value: BlockType.latexBlock, child: Text('LaTeX')),
        const PopupMenuItem(value: BlockType.taskListBlock, child: Text('Task List')),
        const PopupMenuItem(value: BlockType.audio, child: Text('Audio')),
      ],
    ).then((type) {
      if (type != null) {
        widget.onTypeChanged(type);
      }
    });
  }
}
