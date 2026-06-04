import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:devnote/features/knowledge_graph/graph_service.dart';
import 'package:devnote/features/knowledge_graph/bloc/graph_state.dart';

class GraphEdgeWidget extends StatelessWidget {
  final KnowledgeEdgeModel edge;
  final NodePosition fromPosition;
  final NodePosition toPosition;

  const GraphEdgeWidget({
    super.key,
    required this.edge,
    required this.fromPosition,
    required this.toPosition,
  });

  Color _edgeColor(BuildContext context) {
    switch (edge.edgeType) {
      case GraphEdgeType.reference:
        return Theme.of(context).colorScheme.primary.withValues(alpha: 0.6);
      case GraphEdgeType.tag:
        return Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.6);
      case GraphEdgeType.parent:
        return Theme.of(context).colorScheme.secondary.withValues(alpha: 0.6);
      case GraphEdgeType.related:
        return Theme.of(context).colorScheme.outline.withValues(alpha: 0.4);
    }
  }

  double _edgeWidth() {
    switch (edge.edgeType) {
      case GraphEdgeType.reference:
        return 2.0;
      case GraphEdgeType.tag:
        return 1.5;
      case GraphEdgeType.parent:
        return 2.5;
      case GraphEdgeType.related:
        return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _edgeColor(context);
    final width = _edgeWidth();

    return CustomPaint(
      painter: _EdgePainter(
        from: Offset(fromPosition.x, fromPosition.y),
        to: Offset(toPosition.x, toPosition.y),
        color: color,
        strokeWidth: width,
        isDashed: edge.edgeType == GraphEdgeType.related,
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  final Offset from;
  final Offset to;
  final Color color;
  final double strokeWidth;
  final bool isDashed;

  const _EdgePainter({
    required this.from,
    required this.to,
    required this.color,
    required this.strokeWidth,
    this.isDashed = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    if (isDashed) {
      _drawDashedLine(canvas, paint);
    } else {
      canvas.drawLine(from, to, paint);
    }

    final angle = (to - from).direction;
    const arrowSize = 8.0;
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        to.dx - arrowSize * math.cos(angle + 0.4),
        to.dy - arrowSize * math.sin(angle + 0.4),
      )
      ..lineTo(
        to.dx - arrowSize * math.cos(angle - 0.4),
        to.dy - arrowSize * math.sin(angle - 0.4),
      )
      ..close();
    canvas.drawPath(path, arrowPaint);
  }

  void _drawDashedLine(Canvas canvas, Paint paint) {
    const dashLength = 5.0;
    const gapLength = 3.0;
    final totalDistance = (to - from).distance;
    final direction = (to - from) / totalDistance;
    var current = 0.0;

    while (current < totalDistance) {
      final start = from + direction * current;
      final endDist = (current + dashLength).clamp(0.0, totalDistance).toDouble();
      final end = from + direction * endDist;
      canvas.drawLine(start, end, paint);
      current += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) {
    return from != oldDelegate.from || to != oldDelegate.to || color != oldDelegate.color;
  }
}
