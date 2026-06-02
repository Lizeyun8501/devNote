import 'package:flutter/material.dart';
import 'package:devnote/features/canvas/canvas_service.dart';

class CanvasNodeWidget extends StatelessWidget {
  final CanvasNodeModel node;
  final bool isSelected;
  final VoidCallback onTap;
  final void Function(Offset localOffset) onDragStart;
  final void Function(Offset globalPosition) onDragUpdate;
  final VoidCallback onDragEnd;
  final void Function(Offset globalPosition) onResizeStart;
  final void Function(Offset globalPosition) onResizeUpdate;
  final VoidCallback onResizeEnd;

  const CanvasNodeWidget({
    super.key,
    required this.node,
    required this.isSelected,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: node.x,
      top: node.y,
      child: GestureDetector(
        onTap: onTap,
        onPanStart: (details) {
          onDragStart(details.localPosition);
        },
        onPanUpdate: (details) {
          onDragUpdate(details.globalPosition);
        },
        onPanEnd: (_) {
          onDragEnd();
        },
        child: Container(
          width: node.width,
          height: node.height,
          decoration: BoxDecoration(
            color: _getNodeColor(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(2, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              _buildContent(context),
              if (isSelected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onPanStart: (details) {
                      onResizeStart(details.globalPosition);
                    },
                    onPanUpdate: (details) {
                      onResizeUpdate(details.globalPosition);
                    },
                    onPanEnd: (_) {
                      onResizeEnd();
                    },
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(8),
                          topLeft: Radius.circular(4),
                        ),
                      ),
                      child: Icon(
                        Icons.drag_handle,
                        size: 10,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getNodeColor(BuildContext context) {
    if (node.color != null) {
      final hex = node.color!.replaceFirst('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    }
    switch (node.nodeType) {
      case NodeType.note:
        return Theme.of(context).colorScheme.surface;
      case NodeType.image:
        return Theme.of(context).colorScheme.surfaceContainerHighest;
      case NodeType.file:
        return Theme.of(context).colorScheme.surfaceContainerLow;
      case NodeType.link:
        return Theme.of(context).colorScheme.primaryContainer;
      case NodeType.group:
        return Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.5);
    }
  }

  Widget _buildContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 8),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Icon(
          _getNodeIcon(),
          size: 16,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          _getNodeTitle(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  IconData _getNodeIcon() {
    switch (node.nodeType) {
      case NodeType.note:
        return Icons.note_outlined;
      case NodeType.image:
        return Icons.image_outlined;
      case NodeType.file:
        return Icons.insert_drive_file_outlined;
      case NodeType.link:
        return Icons.link;
      case NodeType.group:
        return Icons.crop_free;
    }
  }

  String _getNodeTitle() {
    switch (node.nodeType) {
      case NodeType.note:
        return node.content ?? '笔记';
      case NodeType.image:
        return '图片';
      case NodeType.file:
        return node.file ?? '文件';
      case NodeType.link:
        return node.content ?? '链接';
      case NodeType.group:
        return '分组';
    }
  }

  Widget _buildBody(BuildContext context) {
    switch (node.nodeType) {
      case NodeType.note:
        return Text(
          node.content ?? '',
          style: Theme.of(context).textTheme.bodySmall,
          overflow: TextOverflow.fade,
        );
      case NodeType.image:
        return Center(
          child: Icon(
            Icons.image,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
        );
      case NodeType.file:
        return Center(
          child: Icon(
            Icons.insert_drive_file,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
        );
      case NodeType.link:
        return Text(
          node.content ?? '',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
          overflow: TextOverflow.fade,
        );
      case NodeType.group:
        return const SizedBox.shrink();
    }
  }
}
