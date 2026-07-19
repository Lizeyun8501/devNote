// 笔记 CRUD 集成测试
//
// 测试笔记的完整 CRUD 流程：加载 → 创建 → 选择 → 搜索 → 删除。
// 使用 MockNoteRepository 模拟数据层，验证 NotesBloc 在多步骤操作中的状态流转。
// 通过 IntegrationTestWidgetsFlutterBinding 确保可在设备或 CI 环境中运行。

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:devnote/features/notes/bloc/notes_bloc.dart';
import 'package:devnote/features/notes/bloc/notes_event.dart';
import 'package:devnote/features/notes/bloc/notes_state.dart';
import 'package:devnote/core/persistence/models/note_model.dart';

import '../test/helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('笔记 CRUD 集成流程', () {
    late MockNoteRepository repository;
    late NotesBloc bloc;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // 初始化仓库，预置 3 条笔记
      repository = MockNoteRepository(createMockNotes(3, folderId: 'folder-1'));
      bloc = NotesBloc(
        repository,
        MockFolderRepository([]),
        MockNoteBlockCreationPort(),
      );
    });

    tearDown(() {
      bloc.close();
    });

    testWidgets('完整 CRUD 流程：加载 → 创建 → 选择 → 搜索 → 删除', (tester) async {
      // ============================================================
      // Step 1: 加载笔记列表
      // ============================================================
      bloc.add(const LoadNotes('folder-1'));
      await tester.pumpAndSettle();

      expect(bloc.state, isA<NotesLoaded>());
      expect((bloc.state as NotesLoaded).notes.length, 3);
      expect((bloc.state as NotesLoaded).filterFolderId, 'folder-1');

      // ============================================================
      // Step 2: 创建新笔记
      // ============================================================
      bloc.add(const CreateNote(title: '新笔记', folderId: 'folder-1'));
      await tester.pumpAndSettle();

      final loadedAfterCreate = bloc.state as NotesLoaded;
      expect(loadedAfterCreate.notes.length, 4);
      expect(loadedAfterCreate.notes.first.title, '新笔记');
      // 新创建的笔记应被自动选中
      expect(loadedAfterCreate.selectedNoteId, loadedAfterCreate.notes.first.id);

      // 验证笔记已持久化到仓库
      final createdNote = await repository.getNote(loadedAfterCreate.selectedNoteId!);
      expect(createdNote, isNotNull);
      expect(createdNote!.title, '新笔记');

      // ============================================================
      // Step 3: 选择另一条笔记
      // ============================================================
      final secondNoteId = loadedAfterCreate.notes[1].id;
      bloc.add(SelectNote(secondNoteId));
      await tester.pumpAndSettle();

      expect((bloc.state as NotesLoaded).selectedNoteId, secondNoteId);

      // ============================================================
      // Step 4: 搜索笔记
      // ============================================================
      bloc.add(const SearchNotes('笔记 1'));
      await tester.pumpAndSettle();

      final loadedAfterSearch = bloc.state as NotesLoaded;
      expect(loadedAfterSearch.searchQuery, '笔记 1');
      // 搜索结果应包含标题或内容匹配的笔记
      expect(loadedAfterSearch.notes.isNotEmpty, true);
      // 验证搜索结果确实匹配查询
      for (final note in loadedAfterSearch.notes) {
        final matches = note.title.toLowerCase().contains('笔记 1'.toLowerCase()) ||
            note.content.toLowerCase().contains('笔记 1'.toLowerCase());
        expect(matches, true, reason: '笔记 "${note.title}" 不匹配搜索查询');
      }

      // ============================================================
      // Step 5: 清空搜索
      // ============================================================
      bloc.add(const SearchNotes(''));
      await tester.pumpAndSettle();

      final loadedAfterClear = bloc.state as NotesLoaded;
      expect(loadedAfterClear.searchQuery, isNull);
      expect(loadedAfterClear.notes.length, 4);

      // ============================================================
      // Step 6: 删除笔记
      // ============================================================
      final noteToDelete = loadedAfterClear.notes.first;
      final deleteId = noteToDelete.id;
      bloc.add(DeleteNote(deleteId));
      await tester.pumpAndSettle();

      final loadedAfterDelete = bloc.state as NotesLoaded;
      expect(loadedAfterDelete.notes.length, 3);
      expect(loadedAfterDelete.notes.any((n) => n.id == deleteId), false);
      // 删除选中的笔记后，selectedNoteId 应被清除
      if (noteToDelete.id == loadedAfterClear.selectedNoteId) {
        expect(loadedAfterDelete.selectedNoteId, isNull);
      }

      // 验证笔记已从仓库删除
      final deletedNote = await repository.getNote(deleteId);
      expect(deletedNote, isNull);
    });

    testWidgets('创建笔记后列表保持排序', (tester) async {
      bloc.add(const LoadNotes('folder-1'));
      await tester.pumpAndSettle();

      // 创建多条笔记
      bloc.add(const CreateNote(title: 'Alpha', folderId: 'folder-1'));
      await tester.pumpAndSettle();
      bloc.add(const CreateNote(title: 'Beta', folderId: 'folder-1'));
      await tester.pumpAndSettle();

      final loaded = bloc.state as NotesLoaded;
      expect(loaded.notes.length, 5);

      // 切换为按标题排序
      bloc.add(const ChangeSortBy(NoteSortBy.title));
      await tester.pumpAndSettle();

      final sorted = bloc.state as NotesLoaded;
      final titles = sorted.notes.map((n) => n.title).toList();
      final expectedTitles = List<String>.from(titles)..sort();
      expect(titles, expectedTitles);
    });

    testWidgets('文件夹切换后重新加载笔记', (tester) async {
      // 先加载 folder-1
      bloc.add(const LoadNotes('folder-1'));
      await tester.pumpAndSettle();
      expect((bloc.state as NotesLoaded).notes.length, 3);

      // 向 folder-2 添加笔记
      await repository.createNote(createMockNote(
        id: 'note-f2',
        title: '文件夹2的笔记',
        folderId: 'folder-2',
      ));

      // 切换到 folder-2
      bloc.add(const FilterByFolder('folder-2'));
      await tester.pumpAndSettle();

      final loaded = bloc.state as NotesLoaded;
      expect(loaded.filterFolderId, 'folder-2');
      expect(loaded.notes.length, 1);
      expect(loaded.notes.first.title, '文件夹2的笔记');
    });

    testWidgets('删除不存在的笔记不崩溃', (tester) async {
      bloc.add(const LoadNotes('folder-1'));
      await tester.pumpAndSettle();

      final initialCount = (bloc.state as NotesLoaded).notes.length;

      // 删除不存在的笔记
      bloc.add(const DeleteNote('nonexistent-id'));
      await tester.pumpAndSettle();

      // 列表应保持不变
      expect((bloc.state as NotesLoaded).notes.length, initialCount);
    });

    testWidgets('连续创建多条笔记后列表状态一致', (tester) async {
      bloc.add(const LoadNotes('folder-1'));
      await tester.pumpAndSettle();

      // 连续创建 5 条笔记
      for (var i = 0; i < 5; i++) {
        bloc.add(CreateNote(title: '批量笔记 $i', folderId: 'folder-1'));
        await tester.pumpAndSettle();
      }

      final loaded = bloc.state as NotesLoaded;
      // 原始 3 条 + 新建 5 条 = 8 条
      expect(loaded.notes.length, 8);

      // 验证所有新笔记都已持久化
      for (var i = 0; i < 5; i++) {
        final matching = loaded.notes.where((n) => n.title == '批量笔记 $i').toList();
        expect(matching.length, 1, reason: '批量笔记 $i 应存在且唯一');
      }

      // 最后创建的笔记应被选中
      expect(loaded.selectedNoteId, loaded.notes.first.id);
      expect(loaded.notes.first.title, '批量笔记 4');
    });

    testWidgets('视图模式和排序模式切换保持笔记数据', (tester) async {
      bloc.add(const LoadNotes('folder-1'));
      await tester.pumpAndSettle();

      final originalNotes = (bloc.state as NotesLoaded).notes;

      // 切换到网格视图
      bloc.add(const ChangeViewMode(NoteViewMode.grid));
      await tester.pumpAndSettle();
      expect((bloc.state as NotesLoaded).viewMode, NoteViewMode.grid);
      expect((bloc.state as NotesLoaded).notes, originalNotes);

      // 切换排序方式
      bloc.add(const ChangeSortBy(NoteSortBy.createdAt));
      await tester.pumpAndSettle();
      expect((bloc.state as NotesLoaded).sortBy, NoteSortBy.createdAt);
      // 排序后笔记数量不变
      expect((bloc.state as NotesLoaded).notes.length, originalNotes.length);

      // 切换回列表视图
      bloc.add(const ChangeViewMode(NoteViewMode.list));
      await tester.pumpAndSettle();
      expect((bloc.state as NotesLoaded).viewMode, NoteViewMode.list);
    });
  });

  group('笔记 CRUD 错误处理流程', () {
    testWidgets('仓库异常时进入错误状态', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final errorRepo = MockNoteRepository.withError(Exception('数据库连接失败'));
      final errorBloc = NotesBloc(
        errorRepo,
        MockFolderRepository([]),
        MockNoteBlockCreationPort(),
      );

      errorBloc.add(const LoadNotes('folder-1'));
      await tester.pumpAndSettle();

      expect(errorBloc.state, isA<NotesError>());
      expect((errorBloc.state as NotesError).message, contains('数据库连接失败'));

      errorBloc.close();
    });

    testWidgets('创建笔记失败时进入错误状态', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final errorRepo = MockNoteRepository.withError(Exception('创建失败'));
      final errorBloc = NotesBloc(
        errorRepo,
        MockFolderRepository([]),
        MockNoteBlockCreationPort(),
      );

      errorBloc.add(const CreateNote(title: '测试', folderId: 'folder-1'));
      await tester.pumpAndSettle();

      expect(errorBloc.state, isA<NotesError>());

      errorBloc.close();
    });
  });
}
