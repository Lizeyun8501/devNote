import 'package:flutter/material.dart';

class ObjectEdgeWidget extends StatelessWidget {
  final Offset source;
  final Offset target;
  final String? label;

  const ObjectEdgeWidget({
    super.key,
    required this.source,
    required this.target,
    this.label,
  });

  static void paintEdge(Canvas canvas, Offset source, Offset target) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(source, target, paint);

    final angle = (target - source).direction;
    const arrowSize = 8.0;
    final arrowP1 = target - Offset.fromDirection(angle + 0.5, arrowSize);
    final arrowP2 = target - Offset.fromDirection(angle - 0.5, arrowSize);

    final arrowPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(target.dx, target.dy)
      ..lineTo(arrowP1.dx, arrowP1.dy)
      ..lineTo(arrowP2.dx, arrowP2.dy)
      ..close();
    canvas.drawPath(path, arrowPaint);
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _EdgePainter(source: source, target: target, label: label),
      size: Size(
        (source.dx - target.dx).abs() + 20,
        (source.dy - target.dy).abs() + 20,
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  final Offset source;
  final Offset target;
  final String? label;

  const _EdgePainter({
    required this.source,
    required this.target,
    this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    ObjectEdgeWidget.paintEdge(canvas, source, target);

    if (label != null) {
      final midPoint = Offset(
        (source.dx + target.dx) / 2,
        (source.dy + target.dy) / 2,
      );
      final tp = TextPainter(
        text: TextSpan(text: label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(midPoint.dx - tp.width / 2, midPoint.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
