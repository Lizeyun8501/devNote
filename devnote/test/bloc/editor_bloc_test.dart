// EditorBloc 单元测试
//
// 测试 EditorBloc 的 block 级编辑操作：加载、插入、更新、删除、移动、切换类型、撤销/重做、选中。
// 使用 mocktail 模拟 EditorService，避免对 SQLite/FFI 的依赖。

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:devnote/features/editor/bloc/editor_bloc.dart';
import 'package:devnote/features/editor/bloc/editor_event.dart';
import 'package:devnote/features/editor/bloc/editor_state.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import 'package:devnote/features/editor/services/editor_service.dart';
import '../../helpers/test_helpers.dart';

// Mock EditorService —— 避免对 SQLite/FFI 的依赖
class MockEditorService extends Mock implements EditorService {}

void main() {
  late MockEditorService mockEditorService;

  setUp(() {
    mockEditorService = MockEditorService();
    // 注册 mocktail 的 fallback 值（用于枚举参数匹配）
    registerFallbackValue(BlockType.paragraph);
  });

  // 预置 block 数据
  final block1 = createMockEditorBlock(
    id: 'block-1',
    content: '第一段',
    position: 0,
  );
  final block2 = createMockEditorBlock(
    id: 'block-2',
    content: '第二段',
    position: 1,
  );

  group('EditorBloc', () {
    test('初始状态为 EditorInitial', () {
      final bloc = EditorBloc(mockEditorService);
      expect(bloc.state, isA<EditorInitial>());
      bloc.close();
    });

    group('LoadNote', () {
      blocTest<EditorBloc, EditorState>(
        '加载笔记成功时发射 EditorLoading → EditorLoaded',
        build: () {
          when(() => mockEditorService.loadBlocks(any()))
              .thenAnswer((_) async => {});
          when(() => mockEditorService.listBlocks(any()))
              .thenAnswer((_) async => [block1, block2]);
          return EditorBloc(mockEditorService);
        },
        act: (bloc) => bloc.add(const LoadNote('note-1')),
        wait: const Duration(milliseconds: 100),
        expect: () => [
          isA<EditorLoading>(),
          isA<EditorLoaded>()
              .having((s) => s.noteId, 'noteId', 'note-1')
              .having((s) => s.blocks.length, 'blocks 长度', 2),
        ],
      );

      blocTest<EditorBloc, EditorState>(
        '加载空笔记时自动创建默认段落 block',
        build: () {
          when(() => mockEditorService.loadBlocks(any()))
              .thenAnswer((_) async => {});
          when(() => mockEditorService.listBlocks(any()))
              .thenAnswer((_) async => <BlockModel>[]);
          when(() => mockEditorService.createBlock(
                noteId: any(named: 'noteId'),
                blockType: any(named: 'blockType'),
                content: any(named: 'content'),
                position: any(named: 'position'),
              )).thenAnswer((_) async => createMockEditorBlock(
                id: 'new-block',
                content: '',
                position: 0,
              ));
          return EditorBloc(mockEditorService);
        },
        act: (bloc) => bloc.add(const LoadNote('note-1')),
        wait: const Duration(milliseconds: 100),
        verify: (bloc) {
          final loaded = bloc.state as EditorLoaded;
          expect(loaded.blocks.length, 1);
          expect(loaded.blocks.first.content, isEmpty);
        },
      );

      blocTest<EditorBloc, EditorState>(
        '加载失败时降级创建默认段落 block',
        build: () {
          when(() => mockEditorService.loadBlocks(any()))
              .thenThrow(Exception('加载失败'));
          when(() => mockEditorService.createBlock(
                noteId: any(named: 'noteId'),
                blockType: any(named: 'blockType'),
                content: any(named: 'content'),
                position: any(named: 'position'),
              )).thenAnswer((_) async => createMockEditorBlock(
                id: 'fallback-block',
                content: '',
                position: 0,
              ));
          return EditorBloc(mockEditorService);
        },
        act: (bloc) => bloc.add(const LoadNote('note-1')),
        wait: const Duration(milliseconds: 100),
        expect: () => [
          isA<EditorLoading>(),
          isA<EditorLoaded>(),
        ],
      );
    });

    group('InsertBlock', () {
      blocTest<EditorBloc, EditorState>(
        '插入新 block 后列表长度增加',
        build: () {
          when(() => mockEditorService.createBlock(
                noteId: any(named: 'noteId'),
                blockType: any(named: 'blockType'),
                content: any(named: 'content'),
                position: any(named: 'position'),
              )).thenAnswer((_) async => createMockEditorBlock(
                id: 'new-block',
                content: '新内容',
                position: 1,
              ));
          return EditorBloc(mockEditorService);
        },
        seed: () => EditorLoaded(noteId: 'note-1', blocks: [block1]),
        act: (bloc) => bloc.add(const InsertBlock(
          noteId: 'note-1',
          blockType: BlockType.paragraph,
          content: '新内容',
          position: 1,
        )),
        wait: const Duration(milliseconds: 100),
        verify: (bloc) {
          final loaded = bloc.state as EditorLoaded;
          expect(loaded.blocks.length, 2);
          expect(loaded.activeBlockId, 'new-block');
        },
      );

      blocTest<EditorBloc, EditorState>(
        '插入失败时发射 EditorError',
        build: () {
          when(() => mockEditorService.createBlock(
                noteId: any(named: 'noteId'),
                blockType: any(named: 'blockType'),
                content: any(named: 'content'),
                position: any(named: 'position'),
              )).thenThrow(Exception('插入失败'));
          return EditorBloc(mockEditorService);
        },
        seed: () => EditorLoaded(noteId: 'note-1', blocks: [block1]),
        act: (bloc) => bloc.add(const InsertBlock(
          noteId: 'note-1',
          blockType: BlockType.paragraph,
          content: '新内容',
          position: 1,
        )),
        wait: const Duration(milliseconds: 100),
        expect: () => [isA<EditorError>()],
      );
    });

    group('UpdateBlock', () {
      blocTest<EditorBloc, EditorState>(
        '更新 block 内容后列表反映新内容',
        build: () {
          when(() => mockEditorService.updateBlock(
                blockId: any(named: 'blockId'),
                content: any(named: 'content'),
              )).thenAnswer((_) async {});
          return EditorBloc(mockEditorService);
        },
        seed: () => EditorLoaded(noteId: 'note-1', blocks: [block1, block2]),
        act: (bloc) => bloc.add(const UpdateBlock(
          blockId: 'block-1',
          content: '更新后的内容',
        )),
        wait: const Duration(milliseconds: 100),
        verify: (bloc) {
          final loaded = bloc.state as EditorLoaded;
          expect(loaded.blocks.first.content, '更新后的内容');
          // 撤销栈应记录操作前的状态
          expect(loaded.undoStack.length, 1);
        },
      );
    });

    group('DeleteBlock', () {
      blocTest<EditorBloc, EditorState>(
        '删除 block 后列表长度减少',
        build: () {
          when(() => mockEditorService.deleteBlock(any()))
              .thenAnswer((_) async {});
          return EditorBloc(mockEditorService);
        },
        seed: () => EditorLoaded(noteId: 'note-1', blocks: [block1, block2]),
        act: (bloc) => bloc.add(const DeleteBlock('block-1')),
        wait: const Duration(milliseconds: 100),
        verify: (bloc) {
          final loaded = bloc.state as EditorLoaded;
          expect(loaded.blocks.length, 1);
          expect(loaded.blocks.first.id, 'block-2');
        },
      );

      blocTest<EditorBloc, EditorState>(
        '删除最后一个 block 时自动创建默认段落',
        build: () {
          when(() => mockEditorService.deleteBlock(any()))
              .thenAnswer((_) async {});
          when(() => mockEditorService.createBlock(
                noteId: any(named: 'noteId'),
                blockType: any(named: 'blockType'),
                content: any(named: 'content'),
                position: any(named: 'position'),
              )).thenAnswer((_) async => createMockEditorBlock(
                id: 'auto-block',
                content: '',
                position: 0,
              ));
          return EditorBloc(mockEditorService);
        },
        seed: () => EditorLoaded(noteId: 'note-1', blocks: [block1]),
        act: (bloc) => bloc.add(const DeleteBlock('block-1')),
        wait: const Duration(milliseconds: 100),
        verify: (bloc) {
          final loaded = bloc.state as EditorLoaded;
          expect(loaded.blocks.length, 1);
          expect(loaded.activeBlockId, 'auto-block');
        },
      );
    });

    group('MoveBlock', () {
      blocTest<EditorBloc, EditorState>(
        '移动 block 到新位置后顺序更新',
        build: () {
          when(() => mockEditorService.moveBlock(
                blockId: any(named: 'blockId'),
                newPosition: any(named: 'newPosition'),
              )).thenAnswer((_) async {});
          return EditorBloc(mockEditorService);
        },
        seed: () => EditorLoaded(noteId: 'note-1', blocks: [block1, block2]),
        act: (bloc) => bloc.add(const MoveBlock(blockId: 'block-1', newPosition: 1)),
        wait: const Duration(milliseconds: 100),
        verify: (bloc) {
          final loaded = bloc.state as EditorLoaded;
          // block-1 移到位置 1，block-2 移到位置 0
          expect(loaded.blocks[0].id, 'block-2');
          expect(loaded.blocks[1].id, 'block-1');
        },
      );
    });

    group('ToggleBlockType', () {
      blocTest<EditorBloc, EditorState>(
        '切换 block 类型为标题',
        build: () {
          when(() => mockEditorService.updateBlockType(
                blockId: any(named: 'blockId'),
                newType: any(named: 'newType'),
              )).thenAnswer((_) async {});
          return EditorBloc(mockEditorService);
        },
        seed: () => EditorLoaded(noteId: 'note-1', blocks: [block1]),
        act: (bloc) => bloc.add(const ToggleBlockType(
          blockId: 'block-1',
          newType: BlockType.heading1,
        )),
        wait: const Duration(milliseconds: 100),
        verify: (bloc) {
          final loaded = bloc.state as EditorLoaded;
          expect(loaded.blocks.first.blockType, BlockType.heading1);
        },
      );
    });

    group('UndoEvent / RedoEvent', () {
      blocTest<EditorBloc, EditorState>(
        '撤销操作恢复到上一个状态',
        build: () {
          when(() => mockEditorService.updateBlock(
                blockId: any(named: 'blockId'),
                content: any(named: 'content'),
              )).thenAnswer((_) async {});
          return EditorBloc(mockEditorService);
        },
        seed: () => EditorLoaded(
          noteId: 'note-1',
          blocks: [
            createMockEditorBlock(id: 'block-1', content: '新内容', position: 0),
          ],
          undoStack: [
            [block1],
          ],
        ),
        act: (bloc) => bloc.add(const UndoEvent()),
        expect: () => [
          isA<EditorLoaded>().having(
            (s) => s.blocks.first.content,
            '恢复旧内容',
            '第一段',
          ),
        ],
      );

      blocTest<EditorBloc, EditorState>(
        '重做操作恢复撤销前的状态',
        build: () {
          when(() => mockEditorService.updateBlock(
                blockId: any(named: 'blockId'),
                content: any(named: 'content'),
              )).thenAnswer((_) async {});
          return EditorBloc(mockEditorService);
        },
        seed: () => EditorLoaded(
          noteId: 'note-1',
          blocks: [block1],
          redoStack: [
            [createMockEditorBlock(id: 'block-1', content: '新内容', position: 0)],
          ],
        ),
        act: (bloc) => bloc.add(const RedoEvent()),
        expect: () => [
          isA<EditorLoaded>().having(
            (s) => s.blocks.first.content,
            '重做后的内容',
            '新内容',
          ),
        ],
      );
    });

    group('SelectBlock', () {
      blocTest<EditorBloc, EditorState>(
        '选中 block 时更新 activeBlockId',
        build: () => EditorBloc(mockEditorService),
        seed: () => EditorLoaded(noteId: 'note-1', blocks: [block1, block2]),
        act: (bloc) => bloc.add(const SelectBlock('block-2')),
        expect: () => [
          isA<EditorLoaded>().having((s) => s.activeBlockId, 'activeBlockId', 'block-2'),
        ],
      );
    });
  });
}
