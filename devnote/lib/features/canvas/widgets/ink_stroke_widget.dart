import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import '../models/ink_stroke.dart';

/// 单条手写笔触渲染组件
///
/// 使用 perfect_freehand 渲染压感笔触。
/// 借鉴: https://github.com/steveruizok/perfect-freehand-dart
class InkStrokeWidget extends StatelessWidget {
  final InkStroke stroke;
  final double scale; // Canvas 缩放比例

  const InkStrokeWidget({
    super.key,
    required this.stroke,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    if (stroke.points.isEmpty) return const SizedBox.shrink();

    // 使用 perfect_freehand 渲染压感笔触
    // perfect_freehand 2.x: getStroke(points, options: options)
    final outlinePoints = getStroke(
      stroke.toPerfectFreehandPoints(),
      options: StrokeOptions(
        size: stroke.strokeWidth * 2 * scale,
        thinning: 0.6, // 压感灵敏度
        smoothing: 0.5, // 平滑度
        streamline: 0.5, // 流线化
        simulatePressure: true,
        isComplete: true,
        start: StrokeEndOptions(
          cap: true,
          taperEnabled: false,
        ),
        end: StrokeEndOptions(
          cap: true,
          taperEnabled: false,
        ),
      ),
    );

    // 构建笔触路径
    final path = _buildPath(outlinePoints);

    return CustomPaint(
      size: Size.infinite,
      painter: _InkPainter(
        path: path,
        color: stroke.isEraser ? Colors.transparent : stroke.color,
        isEraser: stroke.isEraser,
      ),
    );
  }

  /// 将 perfect_freehand 输出的轮廓点构建为闭合填充路径
  Path _buildPath(List<PointVector> points) {
    if (points.isEmpty) return Path();

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    for (var i = 1; i < points.length - 1; i++) {
      final midX = (points[i].dx + points[i + 1].dx) / 2;
      final midY = (points[i].dy + points[i + 1].dy) / 2;
      path.quadraticBezierTo(points[i].dx, points[i].dy, midX, midY);
    }

    if (points.length > 1) {
      path.lineTo(points.last.dx, points.last.dy);
    }

    return path;
  }
}

class _InkPainter extends CustomPainter {
  final Path path;
  final Color color;
  final bool isEraser;

  _InkPainter({
    required this.path,
    required this.color,
    this.isEraser = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (isEraser) {
      // 橡皮擦使用 BlendMode.clear 擦除已有内容
      canvas.save();
      final paint = Paint()
        ..blendMode = BlendMode.clear
        ..style = PaintingStyle.fill
        ..antiAlias = true;
      canvas.drawPath(path, paint);
      canvas.restore();
    } else {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..antiAlias = true;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _InkPainter oldDelegate) {
    return path != oldDelegate.path || color != oldDelegate.color;
  }
}
