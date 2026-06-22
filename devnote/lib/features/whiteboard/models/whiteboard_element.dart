// 白板元素数据模型 —— Excalidraw 风格的手绘画布元素
//
// 借鉴 Excalidraw 的元素模型设计：
// 来源: https://github.com/excalidraw/excalidraw
// 借鉴内容: 以 sealed class 抽象公共字段（id/x/y/rotation/strokeColor/...），
// 子类型携带各自几何属性，统一通过 toJson/fromJson 序列化。

import 'dart:convert';
import 'dart:ui';

/// 白板元素类型标识
enum WhiteboardElementType {
  rectangle,
  ellipse,
  line,
  arrow,
  freedraw,
  text,
  diamond,
  image,
}

/// 箭头/线段端点样式
enum Arrowhead { none, arrow, dot }

/// 白板元素抽象基类 —— 所有子类型共享公共字段
abstract class WhiteboardElement {
  final String id;
  final double x;
  final double y;
  final double rotation;
  final String strokeColor;
  final String fillColor;
  final double strokeWidth;
  final double opacity;

  const WhiteboardElement({
    required this.id,
    required this.x,
    required this.y,
    this.rotation = 0,
    this.strokeColor = '#000000',
    this.fillColor = 'transparent',
    this.strokeWidth = 2,
    this.opacity = 1,
  });

  WhiteboardElementType get type;

  /// 序列化为 JSON（包含 type 字段以便反序列化时分发）
  Map<String, dynamic> toJson();

  /// 拷贝并修改部分字段（子类各自实现以保留自身字段）
  WhiteboardElement copyWith({
    double? x,
    double? y,
    double? rotation,
    String? strokeColor,
    String? fillColor,
    double? strokeWidth,
    double? opacity,
  });

  /// 公共字段写入 map，子类调用以减少重复
  Map<String, dynamic> baseJson() => {
        'id': id,
        'type': type.name,
        'x': x,
        'y': y,
        'rotation': rotation,
        'stroke_color': strokeColor,
        'fill_color': fillColor,
        'stroke_width': strokeWidth,
        'opacity': opacity,
      };

  /// 工厂方法：根据 JSON 中的 type 字段分发到对应子类型
  static WhiteboardElement fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    switch (typeStr) {
      case 'rectangle':
        return RectangleElement.fromJson(json);
      case 'ellipse':
        return EllipseElement.fromJson(json);
      case 'line':
        return LineElement.fromJson(json);
      case 'arrow':
        return ArrowElement.fromJson(json);
      case 'freedraw':
        return FreedrawElement.fromJson(json);
      case 'text':
        return TextElement.fromJson(json);
      case 'diamond':
        return DiamondElement.fromJson(json);
      case 'image':
        return ImageElement.fromJson(json);
      default:
        throw ArgumentError('Unknown whiteboard element type: $typeStr');
    }
  }

  /// 工具方法：解析颜色字符串为 Color
  static Color parseColor(String hex) {
    if (hex == 'transparent' || hex.isEmpty) return const Color(0x00000000);
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }
}

/// 矩形元素
class RectangleElement extends WhiteboardElement {
  final double width;
  final double height;
  final double borderRadius;

  const RectangleElement({
    required super.id,
    required super.x,
    required super.y,
    required this.width,
    required this.height,
    this.borderRadius = 0,
    super.rotation,
    super.strokeColor,
    super.fillColor,
    super.strokeWidth,
    super.opacity,
  });

  factory RectangleElement.fromJson(Map<String, dynamic> json) {
    return RectangleElement(
      id: json['id'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      borderRadius: (json['border_radius'] as num?)?.toDouble() ?? 0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      strokeColor: json['stroke_color'] as String? ?? '#000000',
      fillColor: json['fill_color'] as String? ?? 'transparent',
      strokeWidth: (json['stroke_width'] as num?)?.toDouble() ?? 2,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
    );
  }

  @override
  WhiteboardElementType get type => WhiteboardElementType.rectangle;

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'width': width,
        'height': height,
        'border_radius': borderRadius,
      };

  @override
  WhiteboardElement copyWith({
    double? x,
    double? y,
    double? rotation,
    String? strokeColor,
    String? fillColor,
    double? strokeWidth,
    double? opacity,
    double? width,
    double? height,
    double? borderRadius,
  }) =>
      RectangleElement(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        rotation: rotation ?? this.rotation,
        strokeColor: strokeColor ?? this.strokeColor,
        fillColor: fillColor ?? this.fillColor,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        opacity: opacity ?? this.opacity,
        width: width ?? this.width,
        height: height ?? this.height,
        borderRadius: borderRadius ?? this.borderRadius,
      );
}

/// 椭圆元素
class EllipseElement extends WhiteboardElement {
  final double width;
  final double height;

  const EllipseElement({
    required super.id,
    required super.x,
    required super.y,
    required this.width,
    required this.height,
    super.rotation,
    super.strokeColor,
    super.fillColor,
    super.strokeWidth,
    super.opacity,
  });

  factory EllipseElement.fromJson(Map<String, dynamic> json) {
    return EllipseElement(
      id: json['id'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      strokeColor: json['stroke_color'] as String? ?? '#000000',
      fillColor: json['fill_color'] as String? ?? 'transparent',
      strokeWidth: (json['stroke_width'] as num?)?.toDouble() ?? 2,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
    );
  }

  @override
  WhiteboardElementType get type => WhiteboardElementType.ellipse;

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'width': width,
        'height': height,
      };

  @override
  WhiteboardElement copyWith({
    double? x,
    double? y,
    double? rotation,
    String? strokeColor,
    String? fillColor,
    double? strokeWidth,
    double? opacity,
    double? width,
    double? height,
  }) =>
      EllipseElement(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        rotation: rotation ?? this.rotation,
        strokeColor: strokeColor ?? this.strokeColor,
        fillColor: fillColor ?? this.fillColor,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        opacity: opacity ?? this.opacity,
        width: width ?? this.width,
        height: height ?? this.height,
      );
}

/// 直线元素
class LineElement extends WhiteboardElement {
  final double x2;
  final double y2;
  final Arrowhead arrowhead;

  const LineElement({
    required super.id,
    required super.x,
    required super.y,
    required this.x2,
    required this.y2,
    this.arrowhead = Arrowhead.none,
    super.rotation,
    super.strokeColor,
    super.fillColor,
    super.strokeWidth,
    super.opacity,
  });

  factory LineElement.fromJson(Map<String, dynamic> json) {
    return LineElement(
      id: json['id'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      x2: (json['x2'] as num).toDouble(),
      y2: (json['y2'] as num).toDouble(),
      arrowhead: Arrowhead.values.firstWhere(
        (e) => e.name == (json['arrowhead'] as String? ?? 'none'),
        orElse: () => Arrowhead.none,
      ),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      strokeColor: json['stroke_color'] as String? ?? '#000000',
      fillColor: json['fill_color'] as String? ?? 'transparent',
      strokeWidth: (json['stroke_width'] as num?)?.toDouble() ?? 2,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
    );
  }

  @override
  WhiteboardElementType get type => WhiteboardElementType.line;

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'x2': x2,
        'y2': y2,
        'arrowhead': arrowhead.name,
      };

  @override
  WhiteboardElement copyWith({
    double? x,
    double? y,
    double? rotation,
    String? strokeColor,
    String? fillColor,
    double? strokeWidth,
    double? opacity,
    double? x2,
    double? y2,
    Arrowhead? arrowhead,
  }) =>
      LineElement(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        rotation: rotation ?? this.rotation,
        strokeColor: strokeColor ?? this.strokeColor,
        fillColor: fillColor ?? this.fillColor,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        opacity: opacity ?? this.opacity,
        x2: x2 ?? this.x2,
        y2: y2 ?? this.y2,
        arrowhead: arrowhead ?? this.arrowhead,
      );
}

/// 箭头元素（始终带箭头端点）
class ArrowElement extends WhiteboardElement {
  final double x2;
  final double y2;

  const ArrowElement({
    required super.id,
    required super.x,
    required super.y,
    required this.x2,
    required this.y2,
    super.rotation,
    super.strokeColor,
    super.fillColor,
    super.strokeWidth,
    super.opacity,
  });

  factory ArrowElement.fromJson(Map<String, dynamic> json) {
    return ArrowElement(
      id: json['id'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      x2: (json['x2'] as num).toDouble(),
      y2: (json['y2'] as num).toDouble(),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      strokeColor: json['stroke_color'] as String? ?? '#000000',
      fillColor: json['fill_color'] as String? ?? 'transparent',
      strokeWidth: (json['stroke_width'] as num?)?.toDouble() ?? 2,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
    );
  }

  @override
  WhiteboardElementType get type => WhiteboardElementType.arrow;

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'x2': x2,
        'y2': y2,
      };

  @override
  WhiteboardElement copyWith({
    double? x,
    double? y,
    double? rotation,
    String? strokeColor,
    String? fillColor,
    double? strokeWidth,
    double? opacity,
    double? x2,
    double? y2,
  }) =>
      ArrowElement(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        rotation: rotation ?? this.rotation,
        strokeColor: strokeColor ?? this.strokeColor,
        fillColor: fillColor ?? this.fillColor,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        opacity: opacity ?? this.opacity,
        x2: x2 ?? this.x2,
        y2: y2 ?? this.y2,
      );
}

/// 自由绘制元素 —— 连续点序列形成路径
class FreedrawElement extends WhiteboardElement {
  final List<Offset> points;

  const FreedrawElement({
    required super.id,
    required super.x,
    required super.y,
    required this.points,
    super.rotation,
    super.strokeColor,
    super.fillColor,
    super.strokeWidth,
    super.opacity,
  });

  factory FreedrawElement.fromJson(Map<String, dynamic> json) {
    final pts = (json['points'] as List<dynamic>)
        .map((e) => Offset(
              (e['x'] as num).toDouble(),
              (e['y'] as num).toDouble(),
            ))
        .toList();
    return FreedrawElement(
      id: json['id'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      points: pts,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      strokeColor: json['stroke_color'] as String? ?? '#000000',
      fillColor: json['fill_color'] as String? ?? 'transparent',
      strokeWidth: (json['stroke_width'] as num?)?.toDouble() ?? 2,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
    );
  }

  @override
  WhiteboardElementType get type => WhiteboardElementType.freedraw;

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'points': points
            .map((p) => {'x': p.dx, 'y': p.dy})
            .toList(),
      };

  @override
  WhiteboardElement copyWith({
    double? x,
    double? y,
    double? rotation,
    String? strokeColor,
    String? fillColor,
    double? strokeWidth,
    double? opacity,
    List<Offset>? points,
  }) =>
      FreedrawElement(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        rotation: rotation ?? this.rotation,
        strokeColor: strokeColor ?? this.strokeColor,
        fillColor: fillColor ?? this.fillColor,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        opacity: opacity ?? this.opacity,
        points: points ?? this.points,
      );
}

/// 文本元素
class TextElement extends WhiteboardElement {
  final String text;
  final double fontSize;
  final String fontFamily;

  const TextElement({
    required super.id,
    required super.x,
    required super.y,
    required this.text,
    this.fontSize = 16,
    this.fontFamily = 'sans-serif',
    super.rotation,
    super.strokeColor,
    super.fillColor,
    super.strokeWidth,
    super.opacity,
  });

  factory TextElement.fromJson(Map<String, dynamic> json) {
    return TextElement(
      id: json['id'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      text: json['text'] as String? ?? '',
      fontSize: (json['font_size'] as num?)?.toDouble() ?? 16,
      fontFamily: json['font_family'] as String? ?? 'sans-serif',
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      strokeColor: json['stroke_color'] as String? ?? '#000000',
      fillColor: json['fill_color'] as String? ?? 'transparent',
      strokeWidth: (json['stroke_width'] as num?)?.toDouble() ?? 2,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
    );
  }

  @override
  WhiteboardElementType get type => WhiteboardElementType.text;

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'text': text,
        'font_size': fontSize,
        'font_family': fontFamily,
      };

  @override
  WhiteboardElement copyWith({
    double? x,
    double? y,
    double? rotation,
    String? strokeColor,
    String? fillColor,
    double? strokeWidth,
    double? opacity,
    String? text,
    double? fontSize,
    String? fontFamily,
  }) =>
      TextElement(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        rotation: rotation ?? this.rotation,
        strokeColor: strokeColor ?? this.strokeColor,
        fillColor: fillColor ?? this.fillColor,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        opacity: opacity ?? this.opacity,
        text: text ?? this.text,
        fontSize: fontSize ?? this.fontSize,
        fontFamily: fontFamily ?? this.fontFamily,
      );
}

/// 菱形元素
class DiamondElement extends WhiteboardElement {
  final double width;
  final double height;

  const DiamondElement({
    required super.id,
    required super.x,
    required super.y,
    required this.width,
    required this.height,
    super.rotation,
    super.strokeColor,
    super.fillColor,
    super.strokeWidth,
    super.opacity,
  });

  factory DiamondElement.fromJson(Map<String, dynamic> json) {
    return DiamondElement(
      id: json['id'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      strokeColor: json['stroke_color'] as String? ?? '#000000',
      fillColor: json['fill_color'] as String? ?? 'transparent',
      strokeWidth: (json['stroke_width'] as num?)?.toDouble() ?? 2,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
    );
  }

  @override
  WhiteboardElementType get type => WhiteboardElementType.diamond;

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'width': width,
        'height': height,
      };

  @override
  WhiteboardElement copyWith({
    double? x,
    double? y,
    double? rotation,
    String? strokeColor,
    String? fillColor,
    double? strokeWidth,
    double? opacity,
    double? width,
    double? height,
  }) =>
      DiamondElement(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        rotation: rotation ?? this.rotation,
        strokeColor: strokeColor ?? this.strokeColor,
        fillColor: fillColor ?? this.fillColor,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        opacity: opacity ?? this.opacity,
        width: width ?? this.width,
        height: height ?? this.height,
      );
}

/// 图片元素
class ImageElement extends WhiteboardElement {
  final String imagePath;
  final double width;
  final double height;

  const ImageElement({
    required super.id,
    required super.x,
    required super.y,
    required this.imagePath,
    required this.width,
    required this.height,
    super.rotation,
    super.strokeColor,
    super.fillColor,
    super.strokeWidth,
    super.opacity,
  });

  factory ImageElement.fromJson(Map<String, dynamic> json) {
    return ImageElement(
      id: json['id'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      imagePath: json['image_path'] as String? ?? '',
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      strokeColor: json['stroke_color'] as String? ?? '#000000',
      fillColor: json['fill_color'] as String? ?? 'transparent',
      strokeWidth: (json['stroke_width'] as num?)?.toDouble() ?? 2,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
    );
  }

  @override
  WhiteboardElementType get type => WhiteboardElementType.image;

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'image_path': imagePath,
        'width': width,
        'height': height,
      };

  @override
  WhiteboardElement copyWith({
    double? x,
    double? y,
    double? rotation,
    String? strokeColor,
    String? fillColor,
    double? strokeWidth,
    double? opacity,
    String? imagePath,
    double? width,
    double? height,
  }) =>
      ImageElement(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        rotation: rotation ?? this.rotation,
        strokeColor: strokeColor ?? this.strokeColor,
        fillColor: fillColor ?? this.fillColor,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        opacity: opacity ?? this.opacity,
        imagePath: imagePath ?? this.imagePath,
        width: width ?? this.width,
        height: height ?? this.height,
      );
}

/// 白板元素列表序列化工具
class WhiteboardSerializer {
  /// 将元素列表序列化为 JSON 字符串
  static String encode(List<WhiteboardElement> elements) {
    return jsonEncode({
      'version': 1,
      'elements': elements.map((e) => e.toJson()).toList(),
    });
  }

  /// 从 JSON 字符串反序列化为元素列表
  static List<WhiteboardElement> decode(String jsonString) {
    if (jsonString.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      final list = decoded['elements'] as List? ?? const [];
      return list
          .map((e) => WhiteboardElement.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
