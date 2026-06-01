import 'dart:convert';

class NoteFolder {
  final String id;
  final String name;
  final String? parentId;
  final int createdAt;

  NoteFolder({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
  });

  factory NoteFolder.fromJson(Map<String, dynamic> json) => NoteFolder(
        id: json['id'],
        name: json['name'],
        parentId: json['parent_id'],
        createdAt: json['created_at'],
      );

  static List<NoteFolder> fromJsonList(String jsonString) {
    final list = jsonDecode(jsonString) as List;
    return list
        .map((e) => NoteFolder.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
