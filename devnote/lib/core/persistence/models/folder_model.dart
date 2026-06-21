// FolderModel —— Dart 端文件夹模型
//
// P1 修复 (P1-6 数据模型跨端对齐):
// 原实现仅 5 字段，与 Rust Folder 模型（6 字段）不对齐，缺少 sort_order 字段，
// 导致跨端同步时排序信息丢失。
// 现补齐 sort_order 字段，与 Rust 端对齐。
//
// 注意：原使用 freezed 但未生成 .freezed.dart/.g.dart 文件，改为手动实现。

class FolderModel {
  final String id;
  final String name;
  final String? parentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  // P1 修复: 补齐与 Rust Folder 模型对齐的排序字段
  final int sortOrder;

  const FolderModel({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
    required this.updatedAt,
    this.sortOrder = 0,
  });

  FolderModel copyWith({
    String? id,
    String? name,
    String? parentId,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? sortOrder,
  }) {
    return FolderModel(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'parent_id': parentId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        // P1 修复: 序列化排序字段，确保跨端同步时不丢失
        'sort_order': sortOrder,
      };

  factory FolderModel.fromJson(Map<String, dynamic> json) {
    return FolderModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      parentId: json['parent_id'] as String?,
      createdAt: json['created_at'] is String
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] is String
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      // P1 修复: 反序列化排序字段，兼容旧数据（字段不存在时用默认值 0）
      sortOrder: json['sort_order'] is int
          ? json['sort_order'] as int
          : (json['sort_order'] is num
              ? (json['sort_order'] as num).toInt()
              : 0),
    );
  }

  @override
  String toString() =>
      'FolderModel(id: $id, name: $name, parentId: $parentId, sortOrder: $sortOrder)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FolderModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
