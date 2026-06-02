import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/search/bloc/search_event.dart';
import 'package:devnote/features/search/bloc/search_state.dart';
import 'package:devnote/features/search/search_service.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final SearchService _searchService;
  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 300);

  SearchBloc(this._searchService) : super(const SearchInitial()) {
    on<SearchQueryChanged>(_onQueryChanged);
    on<SearchSubmitted>(_onSubmitted);
    on<SearchFilterChanged>(_onFilterChanged);
    on<SearchHistoryRequested>(_onHistoryRequested);
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
      final results = await _searchService.search(event.query);
      final history = await _searchService.getSearchHistory();
      await _searchService.addToSearchHistory(event.query);
      emit(SearchResults(
        query: event.query,
        results: results,
        searchHistory: history,
      ));
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
        ));
      }
    } catch (e) {
      emit(SearchError(e.toString()));
    }
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}
