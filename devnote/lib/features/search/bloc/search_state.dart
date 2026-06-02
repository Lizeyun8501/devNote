import 'package:equatable/equatable.dart';
import 'package:devnote/features/search/search_service.dart';

abstract class SearchState extends Equatable {
  const SearchState();

  @override
  List<Object?> get props => [];
}

class SearchInitial extends SearchState {
  const SearchInitial();
}

class SearchLoading extends SearchState {
  const SearchLoading();
}

class SearchResults extends SearchState {
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

  SearchResults copyWith({
    String? query,
    List<SearchResultModel>? results,
    List<String>? searchHistory,
    String? folderId,
    List<String>? tags,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return SearchResults(
      query: query ?? this.query,
      results: results ?? this.results,
      searchHistory: searchHistory ?? this.searchHistory,
      folderId: folderId ?? this.folderId,
      tags: tags ?? this.tags,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }

  @override
  List<Object?> get props => [query, results, searchHistory, folderId, tags, startDate, endDate];
}

class SearchError extends SearchState {
  final String message;

  const SearchError(this.message);

  @override
  List<Object?> get props => [message];
}
