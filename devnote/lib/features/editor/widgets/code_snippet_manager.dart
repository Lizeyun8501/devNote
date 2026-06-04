import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CodeSnippet {
  final String id;
  final String title;
  final String code;
  final String language;
  final String category;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CodeSnippet({
    required this.id,
    required this.title,
    required this.code,
    required this.language,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
  });

  CodeSnippet copyWith({
    String? id,
    String? title,
    String? code,
    String? language,
    String? category,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CodeSnippet(
      id: id ?? this.id,
      title: title ?? this.title,
      code: code ?? this.code,
      language: language ?? this.language,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'code': code,
        'language': language,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CodeSnippet.fromJson(Map<String, dynamic> json) => CodeSnippet(
        id: json['id'] as String,
        title: json['title'] as String,
        code: json['code'] as String,
        language: json['language'] as String? ?? '',
        category: json['category'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class CodeSnippetManager {
  static const String _fileName = 'code_snippets.json';

  List<CodeSnippet> _snippets = [];
  List<CodeSnippet> get snippets => List.unmodifiable(_snippets);

  List<String> get categories {
    final cats = <String>{};
    for (final snippet in _snippets) {
      if (snippet.category.isNotEmpty) {
        cats.add(snippet.category);
      }
    }
    return cats.toList()..sort();
  }

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> load() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
        _snippets = jsonList.map((e) => CodeSnippet.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {
      _snippets = [];
    }
  }

  Future<void> save() async {
    final file = await _getFile();
    final jsonList = _snippets.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }

  Future<CodeSnippet> addSnippet({
    required String title,
    required String code,
    required String language,
    String category = '',
  }) async {
    final now = DateTime.now();
    final snippet = CodeSnippet(
      id: now.millisecondsSinceEpoch.toRadixString(36),
      title: title,
      code: code,
      language: language,
      category: category,
      createdAt: now,
      updatedAt: now,
    );
    _snippets.add(snippet);
    await save();
    return snippet;
  }

  Future<CodeSnippet> updateSnippet(String id, {
    String? title,
    String? code,
    String? language,
    String? category,
  }) async {
    final index = _snippets.indexWhere((s) => s.id == id);
    if (index == -1) throw StateError('Snippet not found: $id');
    _snippets[index] = _snippets[index].copyWith(
      title: title,
      code: code,
      language: language,
      category: category,
      updatedAt: DateTime.now(),
    );
    await save();
    return _snippets[index];
  }

  Future<void> deleteSnippet(String id) async {
    _snippets.removeWhere((s) => s.id == id);
    await save();
  }

  List<CodeSnippet> search(String query) {
    if (query.isEmpty) return List.of(_snippets);
    final lowerQuery = query.toLowerCase();
    return _snippets.where((s) {
      return s.title.toLowerCase().contains(lowerQuery) ||
          s.code.toLowerCase().contains(lowerQuery) ||
          s.language.toLowerCase().contains(lowerQuery) ||
          s.category.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  List<CodeSnippet> getByCategory(String category) {
    return _snippets.where((s) => s.category == category).toList();
  }

  List<CodeSnippet> getByLanguage(String language) {
    return _snippets.where((s) => s.language == language).toList();
  }
}
