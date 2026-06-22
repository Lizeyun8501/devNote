import 'dart:ui';

/// PDF 标注类型
enum PdfAnnotationType {
  highlight, // 高亮
  underline, // 下划线
  note, // 批注
  signature, // 签名
  drawing, // 绘图
}

/// PDF 标注
class PdfAnnotation {
  final String id;
  final int pageNumber;
  final PdfAnnotationType type;
  final Rect rect; // 标注区域
  final String? text; // 批注文本
  final Color color; // 标注颜色
  final List<Offset>? points; // 绘图点序列（drawing 类型）
  final String? userId; // 标注用户
  final DateTime createdAt;
  final DateTime? updatedAt;

  PdfAnnotation({
    required this.id,
    required this.pageNumber,
    required this.type,
    required this.rect,
    this.text,
    this.color = const Color(0xFFFFEB3B),
    this.points,
    this.userId,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  PdfAnnotation copyWith({
    Rect? rect,
    String? text,
    Color? color,
    List<Offset>? points,
    DateTime? updatedAt,
  }) =>
      PdfAnnotation(
        id: id,
        pageNumber: pageNumber,
        type: type,
        rect: rect ?? this.rect,
        text: text ?? this.text,
        color: color ?? this.color,
        points: points ?? this.points,
        userId: userId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'page_number': pageNumber,
        'type': type.name,
        'x': rect.left,
        'y': rect.top,
        'width': rect.width,
        'height': rect.height,
        'text': text,
        'color': color.toARGB32(),
        'points': points?.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'user_id': userId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };

  factory PdfAnnotation.fromJson(Map<String, dynamic> json) => PdfAnnotation(
        id: json['id'] as String,
        pageNumber: (json['page_number'] as num).toInt(),
        type: PdfAnnotationType.values.byName(json['type'] as String),
        rect: Rect.fromLTWH(
          (json['x'] as num).toDouble(),
          (json['y'] as num).toDouble(),
          (json['width'] as num).toDouble(),
          (json['height'] as num).toDouble(),
        ),
        text: json['text'] as String?,
        color: Color(json['color'] as int? ?? 0xFFFFEB3B),
        points: (json['points'] as List?)
            ?.map((p) =>
                Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
            .toList(),
        userId: json['user_id'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : null,
      );
}
