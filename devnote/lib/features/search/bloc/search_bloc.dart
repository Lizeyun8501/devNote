import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/ai/semantic_search_service.dart';
import 'package:devnote/features/search/bloc/search_event.dart';
import 'package:devnote/features/search/bloc/search_state.dart';
import 'package:devnote/features/search/search_service.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final SearchService _searchService;
  final SemanticSearchService _semanticSearchService;
  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 300);

  /// 语义搜索开关状态（内存态，由 UI 切换）
  bool _semanticEnabled = false;

  // P1 修复 (P1-5): SemanticSearchService 改为构造函数注入，替代 getIt
  SearchBloc(this._searchService, this._semanticSearchService)
      : super(const SearchInitial()) {
    on<SearchQueryChanged>(_onQueryChanged);
    on<SearchSubmitted>(_onSubmitted);
    on<SearchFilterChanged>(_onFilterChanged);
    on<SearchHistoryRequested>(_onHistoryRequested);
    on<SearchSemanticToggled>(_onSemanticToggled);
  }

  Future<void> _onQueryChanged(SearchQueryChanged event, Emitter<SearchState> emit) async {
    _debounceTimer?.cancel();
    if (event.query.isEmpty) {
      emit(const SearchInitial());
      return;
    }
    _debounceTimer = Timer(_debounceDuration, () {
      add(SearchSubmitted(event.query));
    });
  }

  Future<void> _onSubmitted(SearchSubmitted event, Emitter<SearchState> emit) async {
    if (event.query.isEmpty) {
      emit(const SearchInitial());
      return;
    }
    emit(const SearchLoading());
    try {
      final history = await _searchService.getSearchHistory();
      await _searchService.addToSearchHistory(event.query);

      // 当语义搜索开启且向量索引就绪时，使用 Hybrid Retrieval
      // 否则回退到原有 FTS5 关键词检索，不破坏现有搜索功能
      if (_semanticEnabled && await _semanticSearchService.isSemanticReady()) {
        final semanticResults = await _semanticSearchService.search(
          query: event.query,
          hybrid: true,
        );
        final results = semanticResults
            .map((r) => r.toSearchResultModel())
            .toList();
        emit(SearchResults(
          query: event.query,
          results: results,
          searchHistory: history,
          semanticEnabled: true,
        ));
      } else {
        final results = await _searchService.search(event.query);
        emit(SearchResults(
          query: event.query,
          results: results,
          searchHistory: history,
          semanticEnabled: _semanticEnabled,
        ));
      }
    } catch (e) {
      emit(SearchError(e.toString()));
    }
  }

  Future<void> _onFilterChanged(SearchFilterChanged event, Emitter<SearchState> emit) async {
    final currentState = state;
    String currentQuery = '';
    if (currentState is SearchResults) {
      currentQuery = currentState.query;
    }
    if (currentQuery.isEmpty) return;

    emit(const SearchLoading());
    try {
      final results = await _searchService.searchWithFilter(
        query: currentQuery,
        folderId: event.folderId,
        tags: event.tags,
        startDate: event.startDate,
        endDate: event.endDate,
      );
      final history = await _searchService.getSearchHistory();
      emit(SearchResults(
        query: currentQuery,
        results: results,
        searchHistory: history,
        folderId: event.folderId,
        tags: event.tags,
        startDate: event.startDate,
        endDate: event.endDate,
        semanticEnabled: _semanticEnabled,
      ));
    } catch (e) {
      emit(SearchError(e.toString()));
    }
  }

  Future<void> _onHistoryRequested(SearchHistoryRequested event, Emitter<SearchState> emit) async {
    try {
      final history = await _searchService.getSearchHistory();
      final currentState = state;
      if (currentState is SearchResults) {
        emit(currentState.copyWith(searchHistory: history));
      } else {
        emit(SearchResults(
          query: '',
          results: const [],
          searchHistory: history,
          semanticEnabled: _semanticEnabled,
        ));
      }
    } catch (e) {
      emit(SearchError(e.toString()));
    }
  }

  /// 语义搜索开关切换
  ///
  /// 切换后若当前已有查询，自动重新搜索以应用新模式。
  Future<void> _onSemanticToggled(
    SearchSemanticToggled event,
    Emitter<SearchState> emit,
  ) async {
    _semanticEnabled = event.enabled;
    final currentState = state;
    if (currentState is SearchResults && currentState.query.isNotEmpty) {
      // 重新搜索以应用新的检索模式
      await _onSubmitted(SearchSubmitted(currentState.query), emit);
    } else if (currentState is SearchResults) {
      emit(currentState.copyWith(semanticEnabled: _semanticEnabled));
    }
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}
