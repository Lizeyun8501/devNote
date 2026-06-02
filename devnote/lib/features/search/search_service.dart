import 'dart:convert';
import 'dart:typed_data';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/bridge/error.dart';

class HighlightModel {
  final int start;
  final int end;
  final String text;

  const HighlightModel({
    required this.start,
    required this.end,
    required this.text,
  });

  factory HighlightModel.fromJson(Map<String, dynamic> json) {
    return HighlightModel(
      start: json['start'] as int,
      end: json['end'] as int,
      text: json['text'] as String,
    );
  }
}

class SearchResultModel {
  final String noteId;
  final String title;
  final String snippet;
  final List<HighlightModel> highlights;
  final double score;

  const SearchResultModel({
    required this.noteId,
    required this.title,
    required this.snippet,
    required this.highlights,
    required this.score,
  });

  factory SearchResultModel.fromJson(Map<String, dynamic> json) {
    return SearchResultModel(
      noteId: json['note_id'] as String,
      title: json['title'] as String,
      snippet: json['snippet'] as String,
      highlights: (json['highlights'] as List<dynamic>)
          .map((h) => HighlightModel.fromJson(h as Map<String, dynamic>))
          .toList(),
      score: (json['score'] as num).toDouble(),
    );
  }
}

List<SearchResultModel> _parseSearchResults(FlowyResult<Uint8List, FlowyInternalError> result) {
  if (result is Success<Uint8List, FlowyInternalError>) {
    final json = jsonDecode(utf8.decode(result.value));
    if (json is Map<String, dynamic> && json.containsKey('data')) {
      final dataStr = json['data'];
      if (dataStr is String) {
        final items = jsonDecode(dataStr) as List<dynamic>;
        return items
            .map((item) => SearchResultModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    }
    if (json is List) {
      return json
          .map((item) => SearchResultModel.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    return <SearchResultModel>[];
  }
  if (result is Failure<Uint8List, FlowyInternalError>) {
    throw Exception(result.error.message);
  }
  throw Exception('Unknown result type');
}

class SearchService {
  final Dispatch _dispatch = Dispatch.instance;
  final List<String> _searchHistory = [];
  static const int _maxHistory = 20;

  Future<List<SearchResultModel>> search(String query, {int limit = 20, int offset = 0}) async {
    final payload = jsonEncode({
      'query': query,
      'limit': limit,
      'offset': offset,
    });
    final result = await _dispatch.asyncRequest(
      'SearchEvent.SearchNotes',
      payload: utf8.encode(payload),
    );
    return _parseSearchResults(result);
  }

  Future<List<SearchResultModel>> searchWithFilter({
    required String query,
    String? folderId,
    List<String> tags = const [],
    DateTime? startDate,
    DateTime? endDate,
    int limit = 20,
    int offset = 0,
  }) async {
    final payload = jsonEncode({
      'query': query,
      'limit': limit,
      'offset': offset,
      'folder_id': folderId,
      'tags': tags,
      'start_date': startDate?.toUtc().toIso8601String(),
      'end_date': endDate?.toUtc().toIso8601String(),
    });
    final result = await _dispatch.asyncRequest(
      'SearchEvent.SearchContent',
      payload: utf8.encode(payload),
    );
    return _parseSearchResults(result);
  }

  Future<List<String>> getSearchHistory() async {
    return List<String>.from(_searchHistory);
  }

  Future<void> addToSearchHistory(String query) async {
    if (query.isEmpty) return;
    _searchHistory.remove(query);
    _searchHistory.insert(0, query);
    if (_searchHistory.length > _maxHistory) {
      _searchHistory.removeRange(_maxHistory, _searchHistory.length);
    }
  }

  Future<void> clearSearchHistory() async {
    _searchHistory.clear();
  }
}
