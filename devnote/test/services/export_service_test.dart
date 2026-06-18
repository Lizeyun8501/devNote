// ExportService 单元测试
//
// 测试导出服务的 Markdown/HTML 导出、批量导出、块到 Markdown 转换功能。
// 使用 Mock 仓库避免数据库依赖，使用临时目录验证文件输出。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import 'package:devnote/features/settings/import_export/export_service.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import 'package:devnote/features/editor/services/editor_service.dart';
import '../../helpers/test_helpers.dart';

// Mock EditorService —— 避免对 SQLite/FFI 的依赖
class MockEditorService extends Mock implements EditorService {}

void main() {
  late MockNoteRepository noteRepository;
  late MockFolderRepository folderRepository;
  late MockTagRepository tagRepository;
  late MockEditorService editorService;
  late ExportService exportService;
  late Directory tempDir;

  setUp(() {
    noteRepository = MockNoteRepository([]);
    folderRepository = MockFolderRepository([]);
    tagRepository = MockTagRepository();
    editorService = MockEditorService();
    exportService = ExportService(
      noteRepository: noteRepository,
      folderRepository: folderRepository,
      tagRepository: tagRepository,
      editorService: editorService,
    );
    tempDir = Directory.systemTemp.createTempSync('export_test_');
  });

  tearDown(() {
    exportService.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ExportService - exportNoteAsMarkdown', () {
    test('导出笔记为 Markdown 文件包含 YAML front matter 和内容', () async {
      final note = createMockNote(
        id: 'note-1',
        title: '测试笔记',
        content: '原始内容',
      );
      noteRepository = MockNoteRepository([note]);
      exportService = ExportService(
        noteRepository: noteRepository,
        folderRepository: folderRepository,
        tagRepository: tagRepository,
        editorService: editorService,
      );

      when(() => editorService.listBlocks(any()))
          .thenAnswer((_) async => []);

      final outputPath = p.join(tempDir.path, 'test_note.md');
      await exportService.exportNoteAsMarkdown('note-1', outputPath);

      final content = await File(outputPath).readAsString();
      // 应包含 YAML front matter
      expect(content, startsWith('---'));
      expect(content, contains('title: 测试笔记'));
      expect(content, contains('created:'));
      expect(content, contains('updated:'));
      // 应包含笔记内容
      expect(content, contains('原始内容'));
    });

    test('导出笔记时包含 block 转换的 Markdown', () async {
      final note = createMockNote(id: 'note-1', title: 'Block 笔记');
      noteRepository = MockNoteRepository([note]);
      exportService = ExportService(
        noteRepository: noteRepository,
        folderRepository: folderRepository,
        tagRepository: tagRepository,
        editorService: editorService,
      );

      final blocks = [
        createMockEditorBlock(
          id: 'block-1',
          content: '标题内容',
          blockType: BlockType.heading1,
          position: 0,
        ),
        createMockEditorBlock(
          id: 'block-2',
          content: '段落内容',
          blockType: BlockType.paragraph,
          position: 1,
        ),
      ];

      when(() => editorService.listBlocks(any()))
          .thenAnswer((_) async => blocks);

      final outputPath = p.join(tempDir.path, 'block_note.md');
      await exportService.exportNoteAsMarkdown('note-1', outputPath);

      final content = await File(outputPath).readAsString();
      expect(content, contains('# 标题内容'));
      expect(content, contains('段落内容'));
    });

    test('笔记不存在时不生成文件', () async {
      when(() => editorService.listBlocks(any()))
          .thenAnswer((_) async => []);

      final outputPath = p.join(tempDir.path, 'nonexistent.md');
      await exportService.exportNoteAsMarkdown('nonexistent', outputPath);

      expect(await File(outputPath).exists(), isFalse);
    });
  });

  group('ExportService - export (批量)', () {
    test('导出所有笔记为 Markdown 格式', () async {
      final notes = [
        createMockNote(id: 'note-1', title: '笔记一', folderId: ''),
        createMockNote(id: 'note-2', title: '笔记二', folderId: ''),
      ];
      noteRepository = MockNoteRepository(notes);
      folderRepository = MockFolderRepository([]);
      exportService = ExportService(
        noteRepository: noteRepository,
        folderRepository: folderRepository,
        tagRepository: tagRepository,
        editorService: editorService,
      );

      when(() => tagRepository.getTagsForNote(any()))
          .thenAnswer((_) async => []);

      await exportService.export(
        range: ExportRange.all,
        format: ExportFormat.markdown,
        targetPath: tempDir.path,
      );

      // 应生成两个 .md 文件
      final files = tempDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList();
      expect(files.length, 2);
    });

    test('导出空笔记列表时不生成文件', () async {
      noteRepository = MockNoteRepository([]);
      folderRepository = MockFolderRepository([]);
      exportService = ExportService(
        noteRepository: noteRepository,
        folderRepository: folderRepository,
        tagRepository: tagRepository,
        editorService: editorService,
      );

      await exportService.export(
        range: ExportRange.all,
        format: ExportFormat.markdown,
        targetPath: tempDir.path,
      );

      final files = tempDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList();
      expect(files, isEmpty);
    });

    test('导出 HTML 格式时生成 .html 文件', () async {
      final note = createMockNote(id: 'note-1', title: 'HTML 笔记', folderId: '');
      noteRepository = MockNoteRepository([note]);
      folderRepository = MockFolderRepository([]);
      exportService = ExportService(
        noteRepository: noteRepository,
        folderRepository: folderRepository,
        tagRepository: tagRepository,
        editorService: editorService,
      );

      when(() => tagRepository.getTagsForNote(any()))
          .thenAnswer((_) async => []);

      await exportService.export(
        range: ExportRange.all,
        format: ExportFormat.html,
        targetPath: tempDir.path,
      );

      final files = tempDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.html'))
          .toList();
      expect(files.length, 1);
      final content = await files.first.readAsString();
      expect(content, contains('<!DOCTYPE html>'));
      expect(content, contains('HTML 笔记'));
    });
  });

  group('ExportService - exportAllAsMarkdown', () {
    test('批量导出所有笔记保持文件夹结构', () async {
      final folder = createMockFolder(id: 'folder-1', name: '我的文件夹');
      final notes = [
        createMockNote(id: 'note-1', title: '笔记一', folderId: 'folder-1'),
        createMockNote(id: 'note-2', title: '笔记二', folderId: ''),
      ];
      noteRepository = MockNoteRepository(notes);
      folderRepository = MockFolderRepository([folder]);
      exportService = ExportService(
        noteRepository: noteRepository,
        folderRepository: folderRepository,
        tagRepository: tagRepository,
        editorService: editorService,
      );

      when(() => editorService.listBlocks(any()))
          .thenAnswer((_) async => []);

      await exportService.exportAllAsMarkdown(tempDir.path);

      final mdFiles = tempDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList();
      expect(mdFiles.length, 2);
    });
  });

  group('ExportService - 进度流', () {
    test('导出过程中发射进度事件', () async {
      final notes = [
        createMockNote(id: 'note-1', title: '笔记一', folderId: ''),
        createMockNote(id: 'note-2', title: '笔记二', folderId: ''),
      ];
      noteRepository = MockNoteRepository(notes);
      folderRepository = MockFolderRepository([]);
      exportService = ExportService(
        noteRepository: noteRepository,
        folderRepository: folderRepository,
        tagRepository: tagRepository,
        editorService: editorService,
      );

      when(() => tagRepository.getTagsForNote(any()))
          .thenAnswer((_) async => []);

      final progressList = <ExportProgress>[];
      final subscription = exportService.progressStream.listen(progressList.add);

      await exportService.export(
        range: ExportRange.all,
        format: ExportFormat.markdown,
        targetPath: tempDir.path,
      );

      await Future.delayed(const Duration(milliseconds: 50));
      subscription.cancel();

      // 应至少有初始进度和完成进度
      expect(progressList, isNotEmpty);
      expect(progressList.last.isComplete, isTrue);
    });
  });
}
