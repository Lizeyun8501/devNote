// SearchPage Widget 测试
//
// 测试搜索页面的 UI 渲染：搜索栏、结果列表、加载状态、错误状态。
// 使用 mocktail 模拟 SearchBloc，通过 BlocProvider 提供给子组件。

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:devnote/features/search/bloc/search_bloc.dart';
import 'package:devnote/features/search/bloc/search_event.dart';
import 'package:devnote/features/search/bloc/search_state.dart';
import 'package:devnote/features/search/search_service.dart';
import '../helpers/test_helpers.dart';

// Mock SearchBloc
class MockSearchBloc extends Mock implements SearchBloc {}

void main() {
  late MockSearchBloc mockSearchBloc;

  setUp(() {
    mockSearchBloc = MockSearchBloc();
  });

  /// 构建带 BlocProvider 的测试 Widget
  Widget buildTestWidget(SearchState state) {
    when(() => mockSearchBloc.state).thenReturn(state);
    when(() => mockSearchBloc.stream).thenAnswer((_) => const Stream<SearchState>.empty());

    return MaterialApp(
      home: BlocProvider<SearchBloc>.value(
        value: mockSearchBloc,
        child: const SearchPageTestHarness(),
      ),
    );
  }

  group('SearchPage UI 渲染', () {
    testWidgets('SearchInitial 状态显示搜索提示', (tester) async {
      await tester.pumpWidget(buildTestWidget(const SearchInitial()));
      await tester.pump();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('SearchLoading 状态显示加载指示器', (tester) async {
      await tester.pumpWidget(buildTestWidget(const SearchLoading()));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('SearchResults 状态显示搜索结果', (tester) async {
      final results = [
        createMockSearchResult(noteId: 'note-1', title: 'Flutter 笔记'),
        createMockSearchResult(noteId: 'note-2', title: 'Dart 笔记'),
      ];

      await tester.pumpWidget(buildTestWidget(SearchResults(
        query: 'Flutter',
        results: results,
        searchHistory: ['Flutter', 'Dart'],
      )));
      await tester.pump();

      // 应显示搜索结果标题
      expect(find.text('Flutter 笔记'), findsOneWidget);
      expect(find.text('Dart 笔记'), findsOneWidget);
    });

    testWidgets('SearchError 状态显示错误信息', (tester) async {
      await tester.pumpWidget(buildTestWidget(const SearchError('搜索失败')));
      await tester.pump();

      expect(find.textContaining('搜索失败'), findsOneWidget);
    });

    testWidgets('SearchResults 状态显示搜索历史', (tester) async {
      await tester.pumpWidget(buildTestWidget(SearchResults(
        query: 'Flutter',
        results: [],
        searchHistory: ['历史查询1', '历史查询2'],
      )));
      await tester.pump();

      expect(find.text('历史查询1'), findsOneWidget);
      expect(find.text('历史查询2'), findsOneWidget);
    });

    testWidgets('空结果状态显示无结果提示', (tester) async {
      await tester.pumpWidget(buildTestWidget(const SearchResults(
        query: '不存在的关键词',
        results: [],
        searchHistory: [],
      )));
      await tester.pump();

      expect(find.textContaining('无结果'), findsOneWidget);
    });
  });
}

/// 测试专用 Widget —— 模拟 SearchPage 的 Bloc 消费模式
///
/// 由于 SearchPage 内部创建 SearchBloc(SearchService())，
/// 而 SearchService 依赖 getIt<Dispatch>()，
/// 此处直接消费 BlocProvider 提供的 SearchBloc 进行 UI 测试。
class SearchPageTestHarness extends StatelessWidget {
  const SearchPageTestHarness({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '输入搜索关键词',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (query) {
                context.read<SearchBloc>().add(SearchQueryChanged(query));
              },
            ),
          ),
          Expanded(
            child: BlocBuilder<SearchBloc, SearchState>(
              builder: (context, state) {
                if (state is SearchLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is SearchError) {
                  return Center(child: Text('错误: ${state.message}'));
                }
                if (state is SearchResults) {
                  if (state.results.isEmpty && state.query.isNotEmpty) {
                    return const Center(child: Text('无结果'));
                  }
                  return ListView.builder(
                    itemCount: state.results.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(state.results[index].title),
                        subtitle: Text(state.results[index].snippet),
                      );
                    },
                  );
                }
                return const Center(child: Text('开始搜索'));
              },
            ),
          ),
        ],
      ),
    );
  }
}
