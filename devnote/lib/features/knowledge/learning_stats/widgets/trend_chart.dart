import 'package:flutter/material.dart';

class TrendData {
  final String label;
  final double value;

  const TrendData({
    required this.label,
    required this.value,
  });
}

class TrendChart extends StatelessWidget {
  final List<TrendData> data;

  const TrendChart({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('暂无数据'));
    }
    return CustomPaint(
      size: Size.infinite,
      painter: _TrendChartPainter(
        data: data,
        lineColor: Theme.of(context).colorScheme.primary,
        fillColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        labelStyle: TextStyle(
          fontSize: 9,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  final List<TrendData> data;
  final Color lineColor;
  final Color fillColor;
  final TextStyle labelStyle;

  _TrendChartPainter({
    required this.data,
    required this.lineColor,
    required this.fillColor,
    required this.labelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final leftPadding = 30.0;
    final bottomPadding = 24.0;
    final topPadding = 8.0;
    final rightPadding = 8.0;

    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - bottomPadding - topPadding;

    final maxValue = data.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final safeMax = maxValue == 0 ? 1.0 : maxValue;

    final points = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      final x = leftPadding + (i / (data.length - 1).clamp(1, data.length)) * chartWidth;
      final y = topPadding + chartHeight - (data[i].value / safeMax) * chartHeight;
      points.add(Offset(x, y));
    }

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (points.length >= 2) {
      canvas.drawLine(points.first, points.last, Paint()
        ..color = Colors.grey.withValues(alpha: 0.2)
        ..strokeWidth = 0.5);

      final linePath = Path()..moveTo(points[0].dx, points[0].dy);
      for (int i = 1; i < points.length; i++) {
        linePath.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(linePath, linePaint);

      final fillPath = Path()..moveTo(points[0].dx, topPadding + chartHeight);
      for (final point in points) {
        fillPath.lineTo(point.dx, point.dy);
      }
      fillPath.lineTo(points.last.dx, topPadding + chartHeight);
      fillPath.close();
      canvas.drawPath(fillPath, Paint()..color = fillColor..style = PaintingStyle.fill);
    }

    for (final point in points) {
      canvas.drawCircle(point, 3, Paint()..color = lineColor);
    }

    final labelPainter = TextPainter(textDirection: TextDirection.ltr);
    final step = (data.length / 7).ceil().clamp(1, data.length);
    for (int i = 0; i < data.length; i += step) {
      labelPainter.text = TextSpan(text: data[i].label, style: labelStyle);
      labelPainter.layout();
      labelPainter.paint(
        canvas,
        Offset(points[i].dx - labelPainter.width / 2, topPadding + chartHeight + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) =>
      data != oldDelegate.data || lineColor != oldDelegate.lineColor;
}
