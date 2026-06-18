// SearchBloc 单元测试
//
// 测试 SearchBloc 的搜索查询、提交、过滤、历史记录功能。
// 使用 mocktail 模拟 SearchService，避免对 Dispatch/FFI 的依赖。
// 注意：SearchQueryChanged 事件有 300ms 防抖延迟。

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:devnote/features/search/bloc/search_bloc.dart';
import 'package:devnote/features/search/bloc/search_event.dart';
import 'package:devnote/features/search/bloc/search_state.dart';
import 'package:devnote/features/search/search_service.dart';
import '../../helpers/test_helpers.dart';

// Mock SearchService —— 避免对 Dispatch/FFI 的依赖
class MockSearchService extends Mock implements SearchService {}

void main() {
  late MockSearchService mockSearchService;

  setUp(() {
    mockSearchService = MockSearchService();
    // 注册 fallback 值
    registerFallbackValue(<String>[]);
  });

  final mockResults = [
    createMockSearchResult(noteId: 'note-1', title: 'Flutter 笔记', snippet: 'Flutter 内容'),
    createMockSearchResult(noteId: 'note-2', title: 'Dart 笔记', snippet: 'Dart 内容'),
  ];

  group('SearchBloc', () {
    test('初始状态为 SearchInitial', () {
      final bloc = SearchBloc(mockSearchService);
      expect(bloc.state, isA<SearchInitial>());
      bloc.close();
    });

    group('SearchQueryChanged', () {
      blocTest<SearchBloc, SearchState>(
        '查询为空时立即回到 SearchInitial',
        build: () => SearchBloc(mockSearchService),
        act: (bloc) => bloc.add(const SearchQueryChanged('')),
        expect: () => [isA<SearchInitial>()],
      );

      blocTest<SearchBloc, SearchState>(
        '查询非空时防抖 300ms 后触发 SearchSubmitted',
        build: () {
          when(() => mockSearchService.search(any()))
              .thenAnswer((_) async => mockResults);
          when(() => mockSearchService.getSearchHistory())
              .thenAnswer((_) async => <String>[]);
          when(() => mockSearchService.addToSearchHistory(any()))
              .thenAnswer((_) async {});
          return SearchBloc(mockSearchService);
        },
        act: (bloc) => bloc.add(const SearchQueryChanged('Flutter')),
        wait: const Duration(milliseconds: 400),
        verify: (bloc) {
          // 防抖后应触发搜索并进入 SearchResults 状态
          expect(bloc.state, isA<SearchResults>());
        },
      );
    });

    group('SearchSubmitted', () {
      blocTest<SearchBloc, SearchState>(
        '提交搜索时发射 SearchLoading → SearchResults',
        build: () {
          when(() => mockSearchService.search(any()))
              .thenAnswer((_) async => mockResults);
          when(() => mockSearchService.getSearchHistory())
              .thenAnswer((_) async => ['Flutter']);
          when(() => mockSearchService.addToSearchHistory(any()))
              .thenAnswer((_) async {});
          return SearchBloc(mockSearchService);
        },
        act: (bloc) => bloc.add(const SearchSubmitted('Flutter')),
        wait: const Duration(milliseconds: 100),
        expect: () => [
          isA<SearchLoading>(),
          isA<SearchResults>()
              .having((s) => s.query, 'query', 'Flutter')
              .having((s) => s.results.length, '结果数', 2)
              .having((s) => s.searchHistory, '历史记录', ['Flutter']),
        ],
      );

      blocTest<SearchBloc, SearchState>(
        '提交空查询时回到 SearchInitial',
        build: () => SearchBloc(mockSearchService),
        act: (bloc) => bloc.add(const SearchSubmitted('')),
        expect: () => [isA<SearchInitial>()],
      );

      blocTest<SearchBloc, SearchState>(
        '搜索抛出异常时发射 SearchError',
        build: () {
          when(() => mockSearchService.search(any()))
              .thenThrow(Exception('搜索服务不可用'));
          when(() => mockSearchService.getSearchHistory())
              .thenAnswer((_) async => <String>[]);
          when(() => mockSearchService.addToSearchHistory(any()))
              .thenAnswer((_) async {});
          return SearchBloc(mockSearchService);
        },
        act: (bloc) => bloc.add(const SearchSubmitted('Flutter')),
        wait: const Duration(milliseconds: 100),
        expect: () => [
          isA<SearchLoading>(),
          isA<SearchError>(),
        ],
      );
    });

    group('SearchFilterChanged', () {
      blocTest<SearchBloc, SearchState>(
        '有当前查询时应用过滤条件重新搜索',
        build: () {
          when(() => mockSearchService.searchWithFilter(
                query: any(named: 'query'),
                folderId: any(named: 'folderId'),
                tags: any(named: 'tags'),
                startDate: any(named: 'startDate'),
                endDate: any(named: 'endDate'),
              )).thenAnswer((_) async => [mockResults[0]]);
          when(() => mockSearchService.getSearchHistory())
              .thenAnswer((_) async => <String>[]);
          return SearchBloc(mockSearchService);
        },
        seed: () => SearchResults(
          query: 'Flutter',
          results: mockResults,
          searchHistory: [],
        ),
        act: (bloc) => bloc.add(const SearchFilterChanged(
          folderId: 'folder-1',
          tags: ['dart'],
        )),
        wait: const Duration(milliseconds: 100),
        verify: (bloc) {
          final state = bloc.state as SearchResults;
          expect(state.folderId, 'folder-1');
          expect(state.tags, ['dart']);
          expect(state.results.length, 1);
        },
      );

      blocTest<SearchBloc, SearchState>(
        '无当前查询时不执行过滤搜索',
        build: () => SearchBloc(mockSearchService),
        act: (bloc) => bloc.add(const SearchFilterChanged(folderId: 'folder-1')),
        wait: const Duration(milliseconds: 100),
        expect: () => [],
      );
    });

    group('SearchHistoryRequested', () {
      blocTest<SearchBloc, SearchState>(
        '请求历史记录时在 SearchResults 状态下更新历史',
        build: () {
          when(() => mockSearchService.getSearchHistory())
              .thenAnswer((_) async => ['Flutter', 'Dart']);
          return SearchBloc(mockSearchService);
        },
        seed: () => SearchResults(
          query: 'Flutter',
          results: mockResults,
          searchHistory: [],
        ),
        act: (bloc) => bloc.add(const SearchHistoryRequested()),
        wait: const Duration(milliseconds: 100),
        verify: (bloc) {
          final state = bloc.state as SearchResults;
          expect(state.searchHistory, ['Flutter', 'Dart']);
        },
      );

      blocTest<SearchBloc, SearchState>(
        '请求历史记录时在非 SearchResults 状态下创建空结果状态',
        build: () {
          when(() => mockSearchService.getSearchHistory())
              .thenAnswer((_) async => ['Flutter']);
          return SearchBloc(mockSearchService);
        },
        act: (bloc) => bloc.add(const SearchHistoryRequested()),
        wait: const Duration(milliseconds: 100),
        verify: (bloc) {
          final state = bloc.state as SearchResults;
          expect(state.query, isEmpty);
          expect(state.results, isEmpty);
          expect(state.searchHistory, ['Flutter']);
        },
      );
    });
  });
}
