import 'dart:ui';

/// 思维导图节点
class MindmapNode {
  final String id;
  final String text;
  final String? noteId; // 关联的笔记 ID
  final String parentId;
  final int level; // 层级（0=根节点）
  final Offset position;
  final Size size;
  final MindmapNodeColor color;
  final List<String> childrenIds;

  MindmapNode({
    required this.id,
    required this.text,
    this.noteId,
    required this.parentId,
    this.level = 0,
    this.position = Offset.zero,
    this.size = const Size(120, 40),
    this.color = MindmapNodeColor.blue,
    this.childrenIds = const [],
  });

  MindmapNode copyWith({
    String? text,
    String? noteId,
    Offset? position,
    Size? size,
    MindmapNodeColor? color,
    List<String>? childrenIds,
  }) => MindmapNode(
    id: id,
    text: text ?? this.text,
    noteId: noteId ?? this.noteId,
    parentId: parentId,
    level: level,
    position: position ?? this.position,
    size: size ?? this.size,
    color: color ?? this.color,
    childrenIds: childrenIds ?? this.childrenIds,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'note_id': noteId,
    'parent_id': parentId,
    'level': level,
    'x': position.dx,
    'y': position.dy,
    'width': size.width,
    'height': size.height,
    'color': color.name,
    'children_ids': childrenIds,
  };

  factory MindmapNode.fromJson(Map<String, dynamic> json) => MindmapNode(
    id: json['id'] as String,
    text: json['text'] as String,
    noteId: json['note_id'] as String?,
    parentId: json['parent_id'] as String? ?? '',
    level: (json['level'] as num?)?.toInt() ?? 0,
    position: Offset(
      (json['x'] as num?)?.toDouble() ?? 0,
      (json['y'] as num?)?.toDouble() ?? 0,
    ),
    size: Size(
      (json['width'] as num?)?.toDouble() ?? 120,
      (json['height'] as num?)?.toDouble() ?? 40,
    ),
    color: MindmapNodeColor.values.byName(json['color'] as String? ?? 'blue'),
    childrenIds: (json['children_ids'] as List? ?? [])
        .map((e) => e as String)
        .toList(),
  );
}

enum MindmapNodeColor {
  blue,    // 根节点
  green,   // 一级子节点
  orange,  // 二级子节点
  purple,  // 三级及以下
  red,     // 重要节点
  grey,    // 普通节点
}

extension MindmapNodeColorExtension on MindmapNodeColor {
  Color get color {
    switch (this) {
      case MindmapNodeColor.blue: return const Color(0xFF2196F3);
      case MindmapNodeColor.green: return const Color(0xFF4CAF50);
      case MindmapNodeColor.orange: return const Color(0xFFFF9800);
      case MindmapNodeColor.purple: return const Color(0xFF9C27B0);
      case MindmapNodeColor.red: return const Color(0xFFF44336);
      case MindmapNodeColor.grey: return const Color(0xFF9E9E9E);
    }
  }

  Color get backgroundColor {
    return color.withAlpha(30);
  }
}

/// 思维导图数据
class MindmapData {
  final String id;
  final String title;
  final String rootId;
  final Map<String, MindmapNode> nodes; // id -> node

  MindmapData({
    required this.id,
    required this.title,
    required this.rootId,
    required this.nodes,
  });

  MindmapData copyWith({
    String? title,
    String? rootId,
    Map<String, MindmapNode>? nodes,
  }) => MindmapData(
    id: id,
    title: title ?? this.title,
    rootId: rootId ?? this.rootId,
    nodes: nodes ?? this.nodes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'root_id': rootId,
    'nodes': nodes.map((key, value) => MapEntry(key, value.toJson())),
  };

  factory MindmapData.fromJson(Map<String, dynamic> json) => MindmapData(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    rootId: json['root_id'] as String,
    nodes: (json['nodes'] as Map? ?? {}).map((k, v) =>
        MapEntry(k as String, MindmapNode.fromJson(v as Map<String, dynamic>))),
  );
}
