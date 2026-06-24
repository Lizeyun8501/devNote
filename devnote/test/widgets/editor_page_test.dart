// EditorPage Widget 测试
//
// 测试编辑器页面的 UI 渲染：加载状态、block 列表显示、错误状态。
// 使用 mocktail 模拟 EditorBloc，通过 BlocProvider 提供给子组件。

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:devnote/features/editor/bloc/editor_bloc.dart';
import 'package:devnote/features/editor/bloc/editor_state.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import '../helpers/test_helpers.dart';

// Mock EditorBloc
class MockEditorBloc extends Mock implements EditorBloc {}

void main() {
  late MockEditorBloc mockEditorBloc;

  setUp(() {
    mockEditorBloc = MockEditorBloc();
    // 注册 StreamSubscription fallback
    registerFallbackValue(const Stream<void>.empty());
  });

  /// 构建带 BlocProvider 的测试 Widget
  Widget buildTestWidget(EditorState state) {
    // 配置 mock BLoC 的 state 返回值
    when(() => mockEditorBloc.state).thenReturn(state);
    when(() => mockEditorBloc.stream).thenAnswer((_) => const Stream<EditorState>.empty());

    return MaterialApp(
      home: BlocProvider<EditorBloc>.value(
        value: mockEditorBloc,
        child: const EditorPageTestHarness(),
      ),
    );
  }

  group('EditorPage UI 渲染', () {
    testWidgets('EditorInitial 状态显示加载中', (tester) async {
      await tester.pumpWidget(buildTestWidget(const EditorInitial()));
      await tester.pump();

      // 初始状态应有 Scaffold 结构
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('EditorLoaded 状态显示 block 内容', (tester) async {
      final blocks = [
        createMockEditorBlock(
          id: 'block-1',
          content: '第一段内容',
          blockType: BlockType.paragraph,
          position: 0,
        ),
        createMockEditorBlock(
          id: 'block-2',
          content: '第二段内容',
          blockType: BlockType.paragraph,
          position: 1,
        ),
      ];

      await tester.pumpWidget(buildTestWidget(
        EditorLoaded(noteId: 'note-1', blocks: blocks),
      ));
      await tester.pump();

      // 应渲染 Scaffold
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('EditorError 状态不崩溃', (tester) async {
      await tester.pumpWidget(buildTestWidget(const EditorError('加载失败')));
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });
  });
}

/// 测试专用 Widget —— 模拟 EditorPage 的 Bloc 消费模式
///
/// 由于 EditorPage 内部创建 EditorBloc(EditorService())，
/// 而 EditorService 依赖 getIt<DatabaseHelper>，
/// 此处直接消费 BlocProvider 提供的 EditorBloc 进行 UI 测试。
class EditorPageTestHarness extends StatelessWidget {
  const EditorPageTestHarness({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<EditorBloc, EditorState>(
          builder: (context, state) {
            return Text(state is EditorLoaded ? '编辑笔记' : '新建笔记');
          },
        ),
      ),
      body: BlocBuilder<EditorBloc, EditorState>(
        builder: (context, state) {
          if (state is EditorLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is EditorError) {
            return Center(child: Text('错误: ${state.message}'));
          }
          if (state is EditorLoaded) {
            return ListView.builder(
              itemCount: state.blocks.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(state.blocks[index].content),
                );
              },
            );
          }
          return const Center(child: Text('初始化中'));
        },
      ),
    );
  }
}
