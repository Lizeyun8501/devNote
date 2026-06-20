import 'package:flutter/material.dart';
import '../models/mindmap_node.dart';

/// 思维导图画布 Widget
class MindmapCanvas extends StatelessWidget {
  final MindmapData data;
  final String? selectedNodeId;
  final Function(String nodeId)? onNodeTap;
  final Function(String nodeId)? onNodeDoubleTap;
  final Function(Offset position)? onCanvasTap;

  const MindmapCanvas({
    super.key,
    required this.data,
    this.selectedNodeId,
    this.onNodeTap,
    this.onNodeDoubleTap,
    this.onCanvasTap,
  });

  @override
  Widget build(BuildContext context) {
    // 计算所有节点的边界
    final bounds = _calculateBounds();
    final offsetX = -bounds.left + 100;
    final offsetY = -bounds.top + 100;

    return InteractiveViewer(
      minScale: 0.2,
      maxScale: 3.0,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      child: GestureDetector(
        onTap: () => onCanvasTap?.call(Offset.zero),
        child: SizedBox(
          width: bounds.width + 200,
          height: bounds.height + 200,
          child: Stack(
            children: [
              // 绘制连线
              CustomPaint(
                size: Size(bounds.width + 200, bounds.height + 200),
                painter: _EdgePainter(
                  data: data,
                  offsetX: offsetX,
                  offsetY: offsetY,
                ),
              ),
              // 绘制节点
              ...data.nodes.values.map((node) {
                return Positioned(
                  left: node.position.dx + offsetX,
                  top: node.position.dy + offsetY,
                  width: node.size.width,
                  height: node.size.height,
                  child: _MindmapNodeWidget(
                    node: node,
                    isSelected: node.id == selectedNodeId,
                    onTap: () => onNodeTap?.call(node.id),
                    onDoubleTap: () => onNodeDoubleTap?.call(node.id),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Rect _calculateBounds() {
    if (data.nodes.isEmpty) return Rect.zero;
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final node in data.nodes.values) {
      minX = _min(minX, node.position.dx);
      minY = _min(minY, node.position.dy);
      maxX = _max(maxX, node.position.dx + node.size.width);
      maxY = _max(maxY, node.position.dy + node.size.height);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  double _min(double a, double b) => a < b ? a : b;
  double _max(double a, double b) => a > b ? a : b;
}

class _MindmapNodeWidget extends StatelessWidget {
  final MindmapNode node;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  const _MindmapNodeWidget({
    required this.node,
    this.isSelected = false,
    this.onTap,
    this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: node.color.backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? node.color.color : node.color.color.withAlpha(100),
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: isSelected
              ? [BoxShadow(
                  color: node.color.color.withAlpha(60),
                  blurRadius: 8,
                  spreadRadius: 1,
                )]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                node.text,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: node.level == 0 ? FontWeight.bold : FontWeight.normal,
                  color: node.color.color,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (node.noteId != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.note,
                size: 14,
                color: node.color.color.withAlpha(150),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  final MindmapData data;
  final double offsetX;
  final double offsetY;

  _EdgePainter({
    required this.data,
    required this.offsetX,
    required this.offsetY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withAlpha(100)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final node in data.nodes.values) {
      if (node.parentId.isEmpty) continue;
      final parent = data.nodes[node.parentId];
      if (parent == null) continue;

      // 贝塞尔曲线连接父子节点
      final startX = parent.position.dx + parent.size.width / 2 + offsetX;
      final startY = parent.position.dy + parent.size.height / 2 + offsetY;
      final endX = node.position.dx + node.size.width / 2 + offsetX;
      final endY = node.position.dy + node.size.height / 2 + offsetY;

      final controlX1 = startX + (endX - startX) * 0.5;
      final controlY1 = startY;
      final controlX2 = startX + (endX - startX) * 0.5;
      final controlY2 = endY;

      final path = Path()
        ..moveTo(startX, startY)
        ..cubicTo(controlX1, controlY1, controlX2, controlY2, endX, endY);

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) =>
      data != oldDelegate.data;
}
