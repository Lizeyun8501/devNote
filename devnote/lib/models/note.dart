import 'dart:convert';

class Note {
  final String id;
  final String title;
  final String content;
  final String? folderId;
  final int createdAt;
  final int updatedAt;

  Note({
    required this.id,
    required this.title,
    required this.content,
    this.folderId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'],
        title: json['title'],
        content: json['content'],
        folderId: json['folder_id'],
        createdAt: json['created_at'],
        updatedAt: json['updated_at'],
      );

  static List<Note> fromJsonList(String jsonString) {
    final list = jsonDecode(jsonString) as List;
    return list.map((e) => Note.fromJson(e as Map<String, dynamic>)).toList();
  }
}
