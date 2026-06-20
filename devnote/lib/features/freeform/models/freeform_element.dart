import 'dart:convert';
import 'dart:ui';

/// 自由画布元素 — 可在画布任意位置放置的内容
class FreeformElement {
  final String id;
  final FreeformElementType type;
  final Offset position; // 画布坐标
  final Size size; // 元素尺寸
  final String content; // 内容（文本/图片URL/HTML等）
  final int zIndex; // 层叠顺序
  final double rotation; // 旋转角度（度）
  final DateTime createdAt;
  final DateTime updatedAt;

  FreeformElement({
    required this.id,
    required this.type,
    required this.position,
    required this.size,
    required this.content,
    this.zIndex = 0,
    this.rotation = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  FreeformElement copyWith({
    Offset? position,
    Size? size,
    String? content,
    int? zIndex,
    double? rotation,
    DateTime? updatedAt,
  }) =>
      FreeformElement(
        id: id,
        type: type,
        position: position ?? this.position,
        size: size ?? this.size,
        content: content ?? this.content,
        zIndex: zIndex ?? this.zIndex,
        rotation: rotation ?? this.rotation,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'x': position.dx,
        'y': position.dy,
        'width': size.width,
        'height': size.height,
        'content': content,
        'z_index': zIndex,
        'rotation': rotation,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory FreeformElement.fromJson(Map<String, dynamic> json) =>
      FreeformElement(
        id: json['id'] as String,
        type: FreeformElementType.values.byName(json['type'] as String),
        position: Offset(
          (json['x'] as num).toDouble(),
          (json['y'] as num).toDouble(),
        ),
        size: Size(
          (json['width'] as num).toDouble(),
          (json['height'] as num).toDouble(),
        ),
        content: json['content'] as String,
        zIndex: (json['z_index'] as num?)?.toInt() ?? 0,
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : null,
      );
}

/// 自由画布元素类型
enum FreeformElementType {
  text, // 文本框
  richText, // 富文本（Markdown）
  image, // 图片
  drawing, // 手写绘图（SVG path）
  stickyNote, // 便签
  audio, // 音频
  link, // 链接卡片
  embed, // 嵌入内容（视频/网页）
}

/// 自由画布页面数据
class FreeformPageData {
  final String id;
  final String title;
  final List<FreeformElement> elements;
  final Size canvasSize; // 画布总尺寸（可扩展）
  final double zoom;
  final Offset panOffset;

  FreeformPageData({
    required this.id,
    required this.title,
    required this.elements,
    this.canvasSize = const Size(4000, 4000),
    this.zoom = 1.0,
    this.panOffset = Offset.zero,
  });

  FreeformPageData copyWith({
    String? title,
    List<FreeformElement>? elements,
    Size? canvasSize,
    double? zoom,
    Offset? panOffset,
  }) =>
      FreeformPageData(
        id: id,
        title: title ?? this.title,
        elements: elements ?? this.elements,
        canvasSize: canvasSize ?? this.canvasSize,
        zoom: zoom ?? this.zoom,
        panOffset: panOffset ?? this.panOffset,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'elements': elements.map((e) => e.toJson()).toList(),
        'canvas_width': canvasSize.width,
        'canvas_height': canvasSize.height,
        'zoom': zoom,
        'pan_x': panOffset.dx,
        'pan_y': panOffset.dy,
      };

  factory FreeformPageData.fromJson(Map<String, dynamic> json) =>
      FreeformPageData(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        elements: (json['elements'] as List? ?? [])
            .map((e) => FreeformElement.fromJson(e as Map<String, dynamic>))
            .toList(),
        canvasSize: Size(
          (json['canvas_width'] as num?)?.toDouble() ?? 4000,
          (json['canvas_height'] as num?)?.toDouble() ?? 4000,
        ),
        zoom: (json['zoom'] as num?)?.toDouble() ?? 1.0,
        panOffset: Offset(
          (json['pan_x'] as num?)?.toDouble() ?? 0,
          (json['pan_y'] as num?)?.toDouble() ?? 0,
        ),
      );

  String toJsonString() => jsonEncode(toJson());

  factory FreeformPageData.fromJsonString(String str) =>
      FreeformPageData.fromJson(jsonDecode(str) as Map<String, dynamic>);
}
