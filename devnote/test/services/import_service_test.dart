// ImportService 单元测试
//
// 测试导入服务的 Markdown/Obsidian/Joplin 格式解析、目录批量导入功能。
// 使用 Mock 仓库避免数据库依赖，使用临时目录准备测试文件。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import 'package:devnote/features/settings/import_export/import_service.dart';
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
  late ImportService importService;
  late Directory tempDir;

  setUp(() {
    noteRepository = MockNoteRepository([]);
    folderRepository = MockFolderRepository([]);
    tagRepository = MockTagRepository();
    editorService = MockEditorService();
    importService = ImportService(
      noteRepository: noteRepository,
      folderRepository: folderRepository,
      tagRepository: tagRepository,
      editorService: editorService,
    );
    tempDir = Directory.systemTemp.createTempSync('import_test_');

    // 默认 mock：createBlock 返回一个 block
    when(() => editorService.createBlock(
          noteId: any(named: 'noteId'),
          blockType: any(named: 'blockType'),
          content: any(named: 'content'),
          position: any(named: 'position'),
        )).thenAnswer((invocation) async {
      return createMockEditorBlock(
        id: 'block-${invocation.positionalArguments}',
        content: invocation.namedArguments[#content] as String,
        blockType: invocation.namedArguments[#blockType] as BlockType,
        position: invocation.namedArguments[#position] as int,
      );
    });
  });

  tearDown(() {
    importService.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ImportService - importFromMarkdown', () {
    test('导入普通 Markdown 文件创建笔记', () async {
      final mdContent = '''# 测试标题

这是段落内容。

- 列表项 1
- 列表项 2
''';
      final filePath = p.join(tempDir.path, 'test.md');
      await File(filePath).writeAsString(mdContent);

      final noteId = await importService.importFromMarkdown(filePath);

      expect(noteId, isNotEmpty);
      // 验证笔记已创建
      final note = await noteRepository.getNote(noteId);
      expect(note, isNotNull);
      expect(note!.title, '测试标题');
    });

    test('导入带 YAML front matter 的 Markdown 文件', () async {
      final mdContent = '''---
title: Obsidian 笔记
created: 2024-01-01T10:00:00
updated: 2024-01-02T12:00:00
---

# Obsidian 笔记

内容段落
''';
      final filePath = p.join(tempDir.path, 'obsidian.md');
      await File(filePath).writeAsString(mdContent);

      final noteId = await importService.importFromMarkdown(filePath);

      final note = await noteRepository.getNote(noteId);
      expect(note, isNotNull);
      expect(note!.title, 'Obsidian 笔记');
      // front matter 应被去除
      expect(note.content, isNot(contains('---')));
      expect(note.content, contains('内容段落'));
    });

    test('导入无标题的 Markdown 文件使用文件名作为标题', () async {
      final mdContent = '只有段落内容，没有标题';
      final filePath = p.join(tempDir.path, '无标题文件.md');
      await File(filePath).writeAsString(mdContent);

      final noteId = await importService.importFromMarkdown(filePath);

      final note = await noteRepository.getNote(noteId);
      expect(note, isNotNull);
      expect(note!.title, '无标题文件');
    });

    test('导入 Markdown 文件时解析为多个 block', () async {
      final mdContent = '''# 标题

段落内容

```dart
void main() {}
```

- 列表项
''';
      final filePath = p.join(tempDir.path, 'blocks.md');
      await File(filePath).writeAsString(mdContent);

      await importService.importFromMarkdown(filePath);

      // 验证 createBlock 被调用多次（标题、段落、代码块、列表）
      verify(() => editorService.createBlock(
            noteId: any(named: 'noteId'),
            blockType: BlockType.heading1,
            content: any(named: 'content'),
            position: any(named: 'position'),
          )).called(1);
    });
  });

  group('ImportService - importFromDirectory', () {
    test('批量导入目录下所有 .md 文件', () async {
      // 准备多个 .md 文件
      await File(p.join(tempDir.path, 'note1.md'))
          .writeAsString('# 笔记一\n\n内容一');
      await File(p.join(tempDir.path, 'note2.md'))
          .writeAsString('# 笔记二\n\n内容二');
      // 非 .md 文件应被忽略
      await File(p.join(tempDir.path, 'readme.txt'))
          .writeAsString('不是 markdown');

      final count = await importService.importFromDirectory(tempDir.path);

      expect(count, 2);
    });

    test('空目录导入返回 0', () async {
      final emptyDir = Directory(p.join(tempDir.path, 'empty'))
        ..createSync();

      final count = await importService.importFromDirectory(emptyDir.path);

      expect(count, 0);
    });

    test('导入子目录中的 Markdown 文件', () async {
      final subDir = Directory(p.join(tempDir.path, 'sub'))
        ..createSync();
      await File(p.join(subDir.path, 'sub_note.md'))
          .writeAsString('# 子目录笔记');

      final count = await importService.importFromDirectory(tempDir.path);

      expect(count, 1);
    });
  });

  group('ImportService - import (Obsidian/Joplin)', () {
    test('导入 Obsidian 风格 Markdown 解析标签和 wikilink', () async {
      final mdContent = '''---
title: Obsidian 笔记
tags: [标签1, 标签2]
---

# Obsidian 笔记

内容包含 [[双向链接]] 和 #行内标签
''';
      final filePath = p.join(tempDir.path, 'obsidian_note.md');
      await File(filePath).writeAsString(mdContent);

      // 准备源目录结构
      final sourceDir = Directory(p.join(tempDir.path, 'obsidian_source'))
        ..createSync();
      await File(p.join(sourceDir.path, 'obsidian_note.md'))
          .writeAsString(mdContent);

      when(() => tagRepository.getAllTags()).thenAnswer((_) async => []);

      final imported = await importService.import(
        source: ImportSource.obsidianVault,
        sourcePath: sourceDir.path,
        targetFolderId: '',
      );

      expect(imported.length, 1);
      expect(imported.first.title, 'Obsidian 笔记');
      // 应解析出标签
      expect(imported.first.tags, containsAll(['标签1', '标签2']));
    });

    test('导入 Joplin 风格 Markdown 解析 front matter', () async {
      final mdContent = '''---
title: Joplin 笔记
tags: work, personal
created: 2024-01-01T10:00:00
---

Joplin 内容
''';
      final sourceDir = Directory(p.join(tempDir.path, 'joplin_source'))
        ..createSync();
      await File(p.join(sourceDir.path, 'joplin_note.md'))
          .writeAsString(mdContent);

      when(() => tagRepository.getAllTags()).thenAnswer((_) async => []);

      final imported = await importService.import(
        source: ImportSource.joplinExport,
        sourcePath: sourceDir.path,
        targetFolderId: '',
      );

      expect(imported.length, 1);
      expect(imported.first.title, 'Joplin 笔记');
      expect(imported.first.tags, containsAll(['work', 'personal']));
    });

    test('导入普通 Markdown 文件夹使用文件名作为标题', () async {
      final sourceDir = Directory(p.join(tempDir.path, 'plain_source'))
        ..createSync();
      await File(p.join(sourceDir.path, 'plain_note.md'))
          .writeAsString('# 普通笔记\n\n内容');

      final imported = await importService.import(
        source: ImportSource.markdownFolder,
        sourcePath: sourceDir.path,
        targetFolderId: '',
      );

      expect(imported.length, 1);
      expect(imported.first.title, '普通笔记');
    });

    test('源目录不存在时返回空列表', () async {
      final imported = await importService.import(
        source: ImportSource.markdownFolder,
        sourcePath: '/nonexistent/path',
        targetFolderId: '',
      );

      expect(imported, isEmpty);
    });

    test('冲突策略为 skip 时跳过同名笔记', () async {
      final existingNote = createMockNote(
        id: 'existing',
        title: '同名笔记',
        folderId: '',
      );
      noteRepository = MockNoteRepository([existingNote]);
      importService = ImportService(
        noteRepository: noteRepository,
        folderRepository: folderRepository,
        tagRepository: tagRepository,
        editorService: editorService,
      );

      final sourceDir = Directory(p.join(tempDir.path, 'conflict_source'))
        ..createSync();
      await File(p.join(sourceDir.path, 'note.md'))
          .writeAsString('# 同名笔记\n\n内容');

      final imported = await importService.import(
        source: ImportSource.markdownFolder,
        sourcePath: sourceDir.path,
        targetFolderId: '',
        conflictResolution: ConflictResolution.skip,
      );

      // 同名笔记应被跳过
      expect(imported, isEmpty);
    });
  });

  group('ImportService - 进度流', () {
    test('导入过程中发射进度事件', () async {
      final sourceDir = Directory(p.join(tempDir.path, 'progress_source'))
        ..createSync();
      await File(p.join(sourceDir.path, 'note1.md'))
          .writeAsString('# 笔记一');
      await File(p.join(sourceDir.path, 'note2.md'))
          .writeAsString('# 笔记二');

      when(() => tagRepository.getAllTags()).thenAnswer((_) async => []);

      final progressList = <ImportProgress>[];
      final subscription = importService.progressStream.listen(progressList.add);

      await importService.import(
        source: ImportSource.markdownFolder,
        sourcePath: sourceDir.path,
        targetFolderId: '',
      );

      await Future.delayed(const Duration(milliseconds: 50));
      subscription.cancel();

      expect(progressList, isNotEmpty);
      expect(progressList.last.isComplete, isTrue);
    });
  });
}
