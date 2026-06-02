import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:devnote/features/canvas/canvas_service.dart';

class CanvasEdgeWidget extends StatelessWidget {
  final CanvasEdgeModel edge;
  final CanvasNodeModel fromNode;
  final CanvasNodeModel toNode;

  const CanvasEdgeWidget({
    super.key,
    required this.edge,
    required this.fromNode,
    required this.toNode,
  });

  @override
  Widget build(BuildContext context) {
    final fromOffset = _getConnectionPoint(fromNode, edge.fromSide, true);
    final toOffset = _getConnectionPoint(toNode, edge.toSide, false);

    return CustomPaint(
      size: Size(
        (fromOffset.dx - toOffset.dx).abs() + 40,
        (fromOffset.dy - toOffset.dy).abs() + 40,
      ),
      painter: _EdgePainter(
        from: fromOffset,
        to: toOffset,
        color: _getEdgeColor(context),
        label: edge.label,
        labelStyle: Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12),
      ),
    );
  }

  Offset _getConnectionPoint(CanvasNodeModel node, Side? side, bool isFrom) {
    final effectiveSide = side ?? (isFrom ? Side.right : Side.left);
    switch (effectiveSide) {
      case Side.top:
        return Offset(node.x + node.width / 2, node.y);
      case Side.bottom:
        return Offset(node.x + node.width / 2, node.y + node.height);
      case Side.left:
        return Offset(node.x, node.y + node.height / 2);
      case Side.right:
        return Offset(node.x + node.width, node.y + node.height / 2);
    }
  }

  Color _getEdgeColor(BuildContext context) {
    if (edge.color != null) {
      final hex = edge.color!.replaceFirst('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    }
    return Theme.of(context).colorScheme.outline;
  }
}

class _EdgePainter extends CustomPainter {
  final Offset from;
  final Offset to;
  final Color color;
  final String? label;
  final TextStyle labelStyle;

  const _EdgePainter({
    required this.from,
    required this.to,
    required this.color,
    this.label,
    required this.labelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final dx = (to.dx - from.dx).abs();
    final controlOffset = (dx * 0.5).clamp(50.0, 200.0);

    final controlPoint1 = Offset(from.dx + controlOffset, from.dy);
    final controlPoint2 = Offset(to.dx - controlOffset, to.dy);

    final path = Path();
    path.moveTo(from.dx, from.dy);
    path.cubicTo(
      controlPoint1.dx,
      controlPoint1.dy,
      controlPoint2.dx,
      controlPoint2.dy,
      to.dx,
      to.dy,
    );
    canvas.drawPath(path, paint);

    _drawArrow(canvas, path);

    if (label != null && label!.isNotEmpty) {
      final midpoint = _getBezierMidpoint(from, controlPoint1, controlPoint2, to, 0.5);
      final textPainter = TextPainter(
        text: TextSpan(text: label, style: labelStyle.copyWith(color: color)),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(midpoint.dx - textPainter.width / 2, midpoint.dy - textPainter.height - 4),
      );
    }
  }

  void _drawArrow(Canvas canvas, Path path) {
    final metrics = path.computeMetrics();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final endLength = 10.0;
    final tangent = metric.getTangentForOffset(metric.length - 1);
    if (tangent == null) return;
    final endPoint = tangent.position;
    final angle = tangent.angle;
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path2 = Path();
    path2.moveTo(endPoint.dx, endPoint.dy);
    path2.lineTo(
      endPoint.dx - endLength * math.cos(angle + 0.4),
      endPoint.dy - endLength * math.sin(angle + 0.4),
    );
    path2.lineTo(
      endPoint.dx - endLength * math.cos(angle - 0.4),
      endPoint.dy - endLength * math.sin(angle - 0.4),
    );
    path2.close();
    canvas.drawPath(path2, arrowPaint);
  }

  Offset _getBezierMidpoint(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final mt = 1 - t;
    return Offset(
      mt * mt * mt * p0.dx +
          3 * mt * mt * t * p1.dx +
          3 * mt * t * t * p2.dx +
          t * t * t * p3.dx,
      mt * mt * mt * p0.dy +
          3 * mt * mt * t * p1.dy +
          3 * mt * t * t * p2.dy +
          t * t * t * p3.dy,
    );
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) {
    return from != oldDelegate.from ||
        to != oldDelegate.to ||
        color != oldDelegate.color ||
        label != oldDelegate.label;
  }
}
