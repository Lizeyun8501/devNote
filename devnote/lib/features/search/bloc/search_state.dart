import 'package:devnote/features/search/search_service.dart';

sealed class SearchState {
  const SearchState();
}

final class SearchInitial extends SearchState {
  const SearchInitial();
}

final class SearchLoading extends SearchState {
  const SearchLoading();
}

final class SearchResults extends SearchState {
  final String query;
  final List<SearchResultModel> results;
  final List<String> searchHistory;
  final String? folderId;
  final List<String> tags;
  final DateTime? startDate;
  final DateTime? endDate;

  const SearchResults({
    required this.query,
    required this.results,
    this.searchHistory = const [],
    this.folderId,
    this.tags = const [],
    this.startDate,
    this.endDate,
  });

  /// 修复：copyWith 使用 _Sentinel 模式支持清除 nullable 字段
  /// 原代码 `folderId ?? this.folderId` 无法传 null 清除筛选条件
  SearchResults copyWith({
    String? query,
    List<SearchResultModel>? results,
    List<String>? searchHistory,
    Object? folderId = _sentinel,
    List<String>? tags,
    Object? startDate = _sentinel,
    Object? endDate = _sentinel,
  }) {
    return SearchResults(
      query: query ?? this.query,
      results: results ?? this.results,
      searchHistory: searchHistory ?? this.searchHistory,
      folderId: folderId == _sentinel ? this.folderId : folderId as String?,
      tags: tags ?? this.tags,
      startDate: startDate == _sentinel ? this.startDate : startDate as DateTime?,
      endDate: endDate == _sentinel ? this.endDate : endDate as DateTime?,
    );
  }
}

/// Sentinel 值用于区分"未传参"和"显式传 null"
const _sentinel = Object();

final class SearchError extends SearchState {
  final String message;

  const SearchError(this.message);
}
