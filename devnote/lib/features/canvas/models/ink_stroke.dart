import 'dart:convert';
import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart';

/// 手写笔触
class InkStroke {
  final String id;
  final List<InkPoint> points;
  final double strokeWidth;
  final Color color;
  final bool isEraser;
  final DateTime createdAt;

  InkStroke({
    required this.id,
    required this.points,
    this.strokeWidth = 2.0,
    this.color = const Color(0xFF000000),
    this.isEraser = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 转换为 perfect_freehand 的点格式
  /// perfect_freehand 2.x 接受 List<PointVector>，第三参数为压感 (0.0-1.0)
  List<PointVector> toPerfectFreehandPoints() {
    return points
        .map((p) => PointVector(p.x, p.y, p.pressure))
        .toList(growable: false);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'points': points.map((p) => p.toJson()).toList(),
      'stroke_width': strokeWidth,
      'color': color.toARGB32(),
      'is_eraser': isEraser,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory InkStroke.fromJson(Map<String, dynamic> json) {
    return InkStroke(
      id: json['id'] as String,
      points: (json['points'] as List)
          .map((p) => InkPoint.fromJson(p as Map<String, dynamic>))
          .toList(),
      strokeWidth: (json['stroke_width'] as num?)?.toDouble() ?? 2.0,
      color: Color(json['color'] as int? ?? 0xFF000000),
      isEraser: json['is_eraser'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  String toJsonString() => jsonEncode(toJson());
}

/// 手写点
class InkPoint {
  final double x;
  final double y;
  final double pressure; // 0.0-1.0

  InkPoint({
    required this.x,
    required this.y,
    this.pressure = 0.5,
  });

  Offset toOffset() => Offset(x, y);

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'pressure': pressure,
      };

  factory InkPoint.fromJson(Map<String, dynamic> json) {
    return InkPoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      pressure: (json['pressure'] as num?)?.toDouble() ?? 0.5,
    );
  }
}
