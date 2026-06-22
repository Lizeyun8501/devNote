// TagModel —— Dart 端标签模型
//
// P1 修复 (P1-6 数据模型跨端对齐):
// 原实现仅 3 字段，与 Rust Tag 模型（4 字段）不对齐，缺少 color 字段，
// 导致跨端同步时标签颜色信息丢失。
// 现补齐 color 字段，与 Rust 端对齐。
//
// 注意：原使用 freezed 但未生成 .freezed.dart/.g.dart 文件，改为手动实现。

class TagModel {
  final String id;
  final String name;
  final DateTime createdAt;

  // P1 修复: 补齐与 Rust Tag 模型对齐的颜色字段
  final String? color;

  const TagModel({
    required this.id,
    required this.name,
    required this.createdAt,
    this.color,
  });

  TagModel copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    String? color,
  }) {
    return TagModel(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      color: color ?? this.color,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created_at': createdAt.toIso8601String(),
        // P1 修复: 序列化颜色字段，确保跨端同步时不丢失
        'color': color,
      };

  factory TagModel.fromJson(Map<String, dynamic> json) {
    return TagModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      createdAt: json['created_at'] is String
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      // P1 修复: 反序列化颜色字段，兼容旧数据（字段不存在时为 null）
      color: json['color'] as String?,
    );
  }

  @override
  String toString() => 'TagModel(id: $id, name: $name, color: $color)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TagModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
