// NotesBloc 单元测试
//
// 测试 NotesBloc 的所有事件处理器：加载、创建、删除、选中、搜索、过滤、排序、分页。
// 使用 bloc_test 包验证状态流转，使用 MockNoteRepository 避免数据库依赖。

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:devnote/features/notes/bloc/notes_bloc.dart';
import 'package:devnote/features/notes/bloc/notes_event.dart';
import 'package:devnote/features/notes/bloc/notes_state.dart';
import 'package:devnote/core/persistence/models/note_model.dart';
import '../helpers/test_helpers.dart';

void main() {
  // 预置测试数据
  final testNotes = [
    createMockNote(
      id: 'note-1',
      title: '第一条笔记',
      content: 'Hello',
      updatedAt: DateTime(2024, 1, 2),
    ),
    createMockNote(
      id: 'note-2',
      title: '第二条笔记',
      content: 'World',
      updatedAt: DateTime(2024, 1, 3),
    ),
    createMockNote(
      id: 'note-3',
      title: 'Flutter',
      content: 'DevNote',
      updatedAt: DateTime(2024, 1, 1),
    ),
  ];

  group('NotesBloc', () {
    test('初始状态为 NotesInitial', () {
      final bloc = NotesBloc(MockNoteRepository([]), MockFolderRepository([]), MockNoteBlockCreationPort());
      expect(bloc.state, isA<NotesInitial>());
      bloc.close();
    });

    group('LoadNotes', () {
      blocTest<NotesBloc, NotesState>(
        '加载笔记列表成功时发射 NotesLoaded，按 updatedAt 降序排序',
        build: () => NotesBloc(MockNoteRepository(testNotes), MockFolderRepository([]), MockNoteBlockCreationPort()),
        act: (bloc) => bloc.add(const LoadNotes('folder-1')),
        wait: const Duration(milliseconds: 100),
        expect: () => [
          isA<NotesLoaded>().having(
            (s) => s.notes.map((n) => n.id).toList(),
            '按 updatedAt 降序',
            ['note-2', 'note-1', 'note-3'],
          ),
        ],
      );

      blocTest<NotesBloc, NotesState>(
        '加载笔记列表失败时发射 NotesError',
        build: () =>
            NotesBloc(MockNoteRepository.withError(Exception('数据库错误')), MockFolderRepository([]), MockNoteBlockCreationPort()),
        act: (bloc) => bloc.add(const LoadNotes('folder-1')),
        wait: const Duration(milliseconds: 100),
        expect: () => [isA<NotesError>()],
      );
    });

    group('CreateNote', () {
      blocTest<NotesBloc, NotesState>(
        '在 NotesLoaded 状态下创建笔记，新笔记插入列表头部并选中',
        build: () => NotesBloc(MockNoteRepository(testNotes), MockFolderRepository([]), MockNoteBlockCreationPort()),
        seed: () => NotesLoaded(notes: testNotes, filterFolderId: 'folder-1'),
        act: (bloc) =>
            bloc.add(const CreateNote(title: '新笔记', folderId: 'folder-1')),
        wait: const Duration(milliseconds: 100),
        verify: (bloc) {
          final state = bloc.state;
          expect(state, isA<NotesLoaded>());
          final loaded = state as NotesLoaded;
          // 新笔记应在列表头部
          expect(loaded.notes.first.title, '新笔记');
          // 新笔记应被选中
          expect(loaded.selectedNoteId, isNotNull);
        },
      );

      blocTest<NotesBloc, NotesState>(
        '在 NotesInitial 状态下创建笔记，切换到 NotesLoaded',
        build: () => NotesBloc(MockNoteRepository([]), MockFolderRepository([]), MockNoteBlockCreationPort()),
        act: (bloc) =>
            bloc.add(const CreateNote(title: '新笔记', folderId: 'folder-1')),
        wait: const Duration(milliseconds: 100),
        expect: () => [isA<NotesLoaded>()],
      );

      blocTest<NotesBloc, NotesState>(
        '创建笔记失败时发射 NotesError',
        build: () =>
            NotesBloc(MockNoteRepository.withError(Exception('创建失败')), MockFolderRepository([]), MockNoteBlockCreationPort()),
        act: (bloc) =>
            bloc.add(const CreateNote(title: '新笔记', folderId: 'folder-1')),
        wait: const Duration(milliseconds: 100),
        expect: () => [isA<NotesError>()],
      );
    });

    group('DeleteNote', () {
      blocTest<NotesBloc, NotesState>(
        '删除笔记后从列表移除',
        build: () => NotesBloc(MockNoteRepository(testNotes), MockFolderRepository([]), MockNoteBlockCreationPort()),
        seed: () => NotesLoaded(notes: testNotes, selectedNoteId: 'note-1'),
        act: (bloc) => bloc.add(const DeleteNote('note-1')),
        wait: const Duration(milliseconds: 100),
        verify: (bloc) {
          final loaded = bloc.state as NotesLoaded;
          expect(loaded.notes.any((n) => n.id == 'note-1'), isFalse);
          // 删除选中的笔记后 selectedNoteId 应清空
          expect(loaded.selectedNoteId, isNull);
        },
      );

      blocTest<NotesBloc, NotesState>(
        '删除笔记失败时发射 NotesError',
        build: () =>
            NotesBloc(MockNoteRepository.withError(Exception('删除失败')), MockFolderRepository([]), MockNoteBlockCreationPort()),
        seed: () => NotesLoaded(notes: testNotes),
        act: (bloc) => bloc.add(const DeleteNote('note-1')),
        wait: const Duration(milliseconds: 100),
        expect: () => [isA<NotesError>()],
      );
    });

    group('SelectNote', () {
      blocTest<NotesBloc, NotesState>(
        '选中笔记时更新 selectedNoteId',
        build: () => NotesBloc(MockNoteRepository(testNotes), MockFolderRepository([]), MockNoteBlockCreationPort()),
        seed: () => NotesLoaded(notes: testNotes),
        act: (bloc) => bloc.add(const SelectNote('note-2')),
        expect: () => [
          NotesLoaded(notes: testNotes, selectedNoteId: 'note-2'),
        ],
      );
    });

    group('SearchNotes', () {
      blocTest<NotesBloc, NotesState>(
        '搜索时根据标题和内容过滤笔记',
        build: () => NotesBloc(MockNoteRepository(testNotes), MockFolderRepository([]), MockNoteBlockCreationPort()),
        seed: () => NotesLoaded(notes: testNotes, filterFolderId: 'folder-1'),
        act: (bloc) => bloc.add(const SearchNotes('Flutter')),
        wait: const Duration(milliseconds: 100),
        verify: (bloc) {
          final loaded = bloc.state as NotesLoaded;
          expect(loaded.searchQuery, 'Flutter');
          // 应只匹配标题或内容包含 'Flutter' 的笔记
          expect(loaded.notes.length, 1);
          expect(loaded.notes.first.title, 'Flutter');
        },
      );

      blocTest<NotesBloc, NotesState>(
        '搜索关键词为空时恢复完整列表',
        build: () => NotesBloc(MockNoteRepository(testNotes), MockFolderRepository([]), MockNoteBlockCreationPort()),
        seed: () => NotesLoaded(
          notes: [testNotes[2]],
          searchQuery: 'Flutter',
          filterFolderId: 'folder-1',
        ),
        act: (bloc) => bloc.add(const SearchNotes('')),
        wait: const Duration(milliseconds: 100),
        verify: (bloc) {
          final loaded = bloc.state as NotesLoaded;
          expect(loaded.searchQuery, isNull);
          expect(loaded.notes.length, 3);
        },
      );
    });

    group('FilterByTag', () {
      blocTest<NotesBloc, NotesState>(
        '按标签过滤时更新 filterTagId',
        build: () => NotesBloc(MockNoteRepository(testNotes), MockFolderRepository([]), MockNoteBlockCreationPort()),
        seed: () => NotesLoaded(notes: testNotes),
        act: (bloc) => bloc.add(const FilterByTag('tag-1')),
        expect: () => [
          NotesLoaded(notes: testNotes, filterTagId: 'tag-1'),
        ],
      );
    });

    group('FilterByFolder', () {
      blocTest<NotesBloc, NotesState>(
        '按文件夹过滤时重新加载该文件夹的笔记',
        build: () => NotesBloc(MockNoteRepository(testNotes), MockFolderRepository([]), MockNoteBlockCreationPort()),
        seed: () => NotesLoaded(notes: []),
        act: (bloc) => bloc.add(const FilterByFolder('folder-1')),
        wait: const Duration(milliseconds: 100),
        verify: (bloc) {
          final loaded = bloc.state as NotesLoaded;
          expect(loaded.filterFolderId, 'folder-1');
          expect(loaded.notes.length, 3);
        },
      );
    });

    group('ChangeViewMode', () {
      blocTest<NotesBloc, NotesState>(
        '切换视图模式为网格',
        build: () => NotesBloc(MockNoteRepository(testNotes), MockFolderRepository([]), MockNoteBlockCreationPort()),
        seed: () => NotesLoaded(notes: testNotes),
        act: (bloc) => bloc.add(const ChangeViewMode(NoteViewMode.grid)),
        expect: () => [
          NotesLoaded(notes: testNotes, viewMode: NoteViewMode.grid),
        ],
      );
    });

    group('ChangeSortBy', () {
      blocTest<NotesBloc, NotesState>(
        '按标题排序时列表按字母顺序排列',
        build: () => NotesBloc(MockNoteRepository(testNotes), MockFolderRepository([]), MockNoteBlockCreationPort()),
        seed: () => NotesLoaded(notes: testNotes),
        act: (bloc) => bloc.add(const ChangeSortBy(NoteSortBy.title)),
        expect: () => [
          isA<NotesLoaded>().having(
            (s) => s.notes.map((n) => n.title).toList(),
            '按标题升序',
            ['Flutter', '第一条笔记', '第二条笔记'],
          ),
        ],
      );

      blocTest<NotesBloc, NotesState>(
        '按创建时间排序时列表按 createdAt 降序排列',
        build: () => NotesBloc(MockNoteRepository(testNotes), MockFolderRepository([]), MockNoteBlockCreationPort()),
        seed: () => NotesLoaded(notes: testNotes),
        act: (bloc) => bloc.add(const ChangeSortBy(NoteSortBy.createdAt)),
        expect: () => [
          isA<NotesLoaded>(),
        ],
      );
    });

    group('LoadMoreNotes', () {
      blocTest<NotesBloc, NotesState>(
        '分页加载更多笔记时追加到列表',
        build: () {
          // 准备 25 条笔记，分页大小 20
          final manyNotes = createMockNotes(25);
          return NotesBloc(MockNoteRepository(manyNotes), MockFolderRepository([]), MockNoteBlockCreationPort());
        },
        seed: () {
          final firstPage = createMockNotes(20);
          return NotesLoaded(
            notes: firstPage,
            filterFolderId: 'folder-1',
            hasMore: true,
            currentPage: 0,
          );
        },
        act: (bloc) => bloc.add(const LoadMoreNotes('folder-1')),
        wait: const Duration(milliseconds: 100),
        verify: (bloc) {
          final loaded = bloc.state as NotesLoaded;
          expect(loaded.currentPage, 1);
        },
      );

      blocTest<NotesBloc, NotesState>(
        'hasMore 为 false 时不加载更多',
        build: () => NotesBloc(MockNoteRepository(testNotes), MockFolderRepository([]), MockNoteBlockCreationPort()),
        seed: () => NotesLoaded(notes: testNotes, hasMore: false),
        act: (bloc) => bloc.add(const LoadMoreNotes('folder-1')),
        wait: const Duration(milliseconds: 100),
        expect: () => [],
      );
    });
  });
}
