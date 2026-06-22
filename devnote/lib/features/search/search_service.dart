import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/persistence/models/highlight_model.dart';

// P1 修复 (P1-3): HighlightModel 已提取到 core/persistence/models/，
// 通过 re-export 保持向后兼容，现有 import search_service.dart 的代码无需改动。
export 'package:devnote/core/persistence/models/highlight_model.dart';

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

class SearchService {
  final Dispatch _dispatch = getIt<Dispatch>();
  final List<String> _searchHistory = [];
  static const int _maxHistory = 20;

  Future<List<SearchResultModel>> search(String query, {int limit = 20, int offset = 0}) async {
    final results = await _dispatch.searchNotes(
      query: query,
      limit: limit,
      offset: offset,
    );
    return results
        .map((item) => SearchResultModel.fromJson(item))
        .toList();
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
    final results = await _dispatch.searchNotes(
      query: query,
      limit: limit,
      offset: offset,
    );
    // FFI 层尚未支持服务端过滤，在 Dart 侧应用额外的过滤条件（best-effort）：
    // 若返回结果不包含对应字段则保留该条目。
    final filtered = results.where((item) {
      // 文件夹过滤
      if (folderId != null) {
        final itemFolderId = item['folder_id'];
        if (itemFolderId != null && itemFolderId != folderId) {
          return false;
        }
      }
      // 标签过滤（存在交集即保留）
      if (tags.isNotEmpty) {
        final itemTags = item['tags'];
        if (itemTags is List) {
          final itemTagsSet = itemTags.map((e) => e.toString()).toSet();
          if (!tags.any((t) => itemTagsSet.contains(t))) {
            return false;
          }
        }
      }
      // 日期过滤（优先 updated_at，其次 created_at）
      if (startDate != null || endDate != null) {
        final dateField = item['updated_at'] ?? item['created_at'];
        if (dateField is String) {
          try {
            final dt = DateTime.parse(dateField);
            if (startDate != null && dt.isBefore(startDate)) {
              return false;
            }
            if (endDate != null && dt.isAfter(endDate)) {
              return false;
            }
          } catch (_) {
            // 日期解析失败则保留该条目
          }
        }
      }
      return true;
    }).toList();
    return filtered
        .map((item) => SearchResultModel.fromJson(item))
        .toList();
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
