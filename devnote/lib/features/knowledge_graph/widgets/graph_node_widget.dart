import 'package:flutter/material.dart';
import 'package:devnote/features/knowledge_graph/graph_service.dart';

class GraphNodeWidget extends StatelessWidget {
  final KnowledgeNodeModel node;
  final double x;
  final double y;
  final bool isSelected;
  final VoidCallback onTap;
  final void Function(Offset offset)? onDragStart;
  final void Function(Offset globalPosition)? onDragUpdate;
  final VoidCallback? onDragEnd;

  const GraphNodeWidget({
    super.key,
    required this.node,
    required this.x,
    required this.y,
    required this.isSelected,
    required this.onTap,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  Color _nodeColor(BuildContext context) {
    switch (node.nodeType) {
      case GraphNodeType.note:
        return Theme.of(context).colorScheme.primaryContainer;
      case GraphNodeType.tag:
        return Theme.of(context).colorScheme.tertiaryContainer;
      case GraphNodeType.folder:
        return Theme.of(context).colorScheme.secondaryContainer;
      case GraphNodeType.canvas:
        return Theme.of(context).colorScheme.errorContainer;
    }
  }

  IconData _nodeIcon() {
    switch (node.nodeType) {
      case GraphNodeType.note:
        return Icons.description;
      case GraphNodeType.tag:
        return Icons.label;
      case GraphNodeType.folder:
        return Icons.folder;
      case GraphNodeType.canvas:
        return Icons.dashboard;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _nodeColor(context);
    final icon = _nodeIcon();

    return Positioned(
      left: x - 60,
      top: y - 25,
      child: GestureDetector(
        onTap: onTap,
        onPanStart: onDragStart != null
            ? (details) => onDragStart!(details.globalPosition)
            : null,
        onPanUpdate: onDragUpdate != null
            ? (details) => onDragUpdate!(details.globalPosition)
            : null,
        onPanEnd: onDragEnd != null ? (_) => onDragEnd!() : null,
        child: Container(
          width: 120,
          height: 50,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurface),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  node.title,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (node.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(
                    Icons.label,
                    size: 10,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
