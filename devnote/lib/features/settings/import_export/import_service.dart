// 导入服务 —— 从外部 Markdown/Obsidian/Joplin 格式导入笔记
// 借鉴 Obsidian 的 YAML front matter 和 [[wikilink]] 解析格式
// 来源: https://help.obsidian.md/Editing+and+formatting/Tags
// 来源: https://help.obsidian.md/Editing+and+formatting/Internal+links
// 借鉴 Joplin 的导出目录结构解析方式
// 来源: https://joplinapp.org/help/apps/import_export/

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:devnote/core/persistence/note_repository.dart';
import 'package:devnote/core/persistence/folder_repository.dart';
import 'package:devnote/core/persistence/tag_repository.dart';
import 'package:devnote/core/persistence/models/note_model.dart';
import 'package:devnote/core/persistence/models/folder_model.dart';
import 'package:devnote/core/persistence/models/tag_model.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import 'package:devnote/features/editor/services/editor_service.dart';

enum ImportSource {
  markdownFolder,
  obsidianVault,
  joplinExport,
}

enum ConflictResolution {
  skip,
  overwrite,
  rename,
}

class ImportProgress {
  final int current;
  final int total;
  final String currentFile;
  final bool isComplete;

  const ImportProgress({
    this.current = 0,
    this.total = 0,
    this.currentFile = '',
    this.isComplete = false,
  });

  double get progress => total > 0 ? current / total : 0.0;
}

class ImportedNote {
  final String title;
  final String content;
  final String folderPath;
  final List<String> tags;
  final List<String> attachments;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ImportedNote({
    required this.title,
    required this.content,
    this.folderPath = '',
    this.tags = const [],
    this.attachments = const [],
    required this.createdAt,
    required this.updatedAt,
  });
}

class ImportService {
  final NoteRepository _noteRepository;
  final FolderRepository _folderRepository;
  final TagRepository _tagRepository;
  final EditorService _editorService;
  final _progressController = StreamController<ImportProgress>.broadcast();
  final _uuid = const Uuid();

  // 缓存已创建的文件夹，避免重复创建（路径 -> folderId）
  final Map<String, String> _folderCache = {};
  // 缓存已创建的标签，避免重复创建（标签名 -> tagId）
  final Map<String, String> _tagCache = {};

  ImportService({
    required NoteRepository noteRepository,
    required FolderRepository folderRepository,
    required TagRepository tagRepository,
    EditorService? editorService,
  })  : _noteRepository = noteRepository,
        _folderRepository = folderRepository,
        _tagRepository = tagRepository,
        _editorService = editorService ?? EditorService();

  Stream<ImportProgress> get progressStream => _progressController.stream;

  Future<List<ImportedNote>> import({
    required ImportSource source,
    required String sourcePath,
    required String targetFolderId,
    ConflictResolution conflictResolution = ConflictResolution.skip,
  }) async {
    _progressController.add(const ImportProgress());

    try {
      final sourceDir = Directory(sourcePath);
      if (!await sourceDir.exists()) {
        return <ImportedNote>[];
      }

      // 收集所有 .md 文件
      final mdFiles = await _collectMarkdownFiles(sourceDir);
      if (mdFiles.isEmpty) {
        return <ImportedNote>[];
      }

      final total = mdFiles.length;
      final importedNotes = <ImportedNote>[];

      for (var i = 0; i < mdFiles.length; i++) {
        final file = mdFiles[i];
        final fileName = p.basename(file.path);

        _progressController.add(ImportProgress(
          current: i + 1,
          total: total,
          currentFile: fileName,
          isComplete: false,
        ));

        try {
          final importedNote = await _importFile(
            file: file,
            sourceDir: sourceDir,
            targetFolderId: targetFolderId,
            source: source,
            conflictResolution: conflictResolution,
          );
          if (importedNote != null) {
            importedNotes.add(importedNote);
          }
        } catch (_) {
          // 单个文件导入失败不影响整体流程，跳过继续
          continue;
        }
      }

      _progressController.add(ImportProgress(
        current: total,
        total: total,
        currentFile: '',
        isComplete: true,
      ));

      return importedNotes;
    } catch (e) {
      // 修复：确保即使 import 方法中途抛异常，进度流也能正确关闭
      _progressController.add(const ImportProgress(isComplete: true));
      rethrow;
    }
  }

  /// 递归收集目录下所有 .md 文件
  List<File> _collectMdFilesSync(Directory dir) {
    final result = <File>[];
    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.md')) {
          result.add(entity);
        }
      }
    } catch (_) {
      // 权限不足等异常，跳过
    }
    return result;
  }

  Future<List<File>> _collectMarkdownFiles(Directory dir) async {
    return _collectMdFilesSync(dir);
  }

  /// 导入单个文件
  Future<ImportedNote?> _importFile({
    required File file,
    required Directory sourceDir,
    required String targetFolderId,
    required ImportSource source,
    required ConflictResolution conflictResolution,
  }) async {
    final rawContent = await file.readAsString();

    // 根据导入来源选择不同的解析策略
    ParsedMarkdown parsed;
    switch (source) {
      case ImportSource.obsidianVault:
        parsed = _parseObsidianMarkdown(rawContent);
        break;
      case ImportSource.joplinExport:
        parsed = _parseJoplinMarkdown(rawContent);
        break;
      case ImportSource.markdownFolder:
        parsed = _parsePlainMarkdown(rawContent);
        break;
    }

    // 从文件路径计算相对文件夹路径，用于创建对应文件夹结构
    final relativePath = p.relative(file.parent.path, from: sourceDir.path);
    final folderId = await _ensureFolderPath(relativePath, targetFolderId);

    // 处理冲突：检查同文件夹下是否已有同名笔记
    final existingNotes = await _noteRepository.listNotes(folderId);
    final existing = existingNotes.where((n) => n.title == parsed.title).toList();

    if (existing.isNotEmpty) {
      switch (conflictResolution) {
        case ConflictResolution.skip:
          return null;
        case ConflictResolution.overwrite:
          // 删除已有笔记后重新创建
          for (final note in existing) {
            await _noteRepository.deleteNote(note.id);
          }
          break;
        case ConflictResolution.rename:
          // 在标题后追加时间戳以避免冲突
          parsed = ParsedMarkdown(
            title: '${parsed.title} (${DateTime.now().millisecondsSinceEpoch})',
            content: parsed.content,
            tags: parsed.tags,
            wikilinks: parsed.wikilinks,
            createdAt: parsed.createdAt,
            updatedAt: parsed.updatedAt,
          );
          break;
      }
    }

    // 创建笔记
    final note = NoteModel(
      id: _uuid.v4(),
      title: parsed.title,
      content: parsed.content,
      folderId: folderId,
      createdAt: parsed.createdAt,
      updatedAt: parsed.updatedAt,
    );

    await _noteRepository.createNote(note);

    // 处理标签：创建标签并关联到笔记
    for (final tagName in parsed.tags) {
      final tagId = await _ensureTag(tagName);
      await _tagRepository.addTagToNote(note.id, tagId);
    }

    return ImportedNote(
      title: parsed.title,
      content: parsed.content,
      folderPath: relativePath,
      tags: parsed.tags,
      createdAt: parsed.createdAt,
      updatedAt: parsed.updatedAt,
    );
  }

  /// 解析普通 Markdown 文件
  /// 不支持 front matter 和 wikilink，仅提取标题和内容
  ParsedMarkdown _parsePlainMarkdown(String raw) {
    final title = _extractTitleFromContent(raw) ?? 'Untitled';
    return ParsedMarkdown(
      title: title,
      content: raw,
      tags: [],
      wikilinks: [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// 解析 Obsidian 风格 Markdown
  // 借鉴 Obsidian 的 YAML front matter 格式和 [[wikilink]] 语法
  // 来源: https://help.obsidian.md/Editing+and+formatting/Properties
  // 来源: https://help.obsidian.md/Editing+and+formatting/Internal+links
  ParsedMarkdown _parseObsidianMarkdown(String raw) {
    final frontMatter = _parseYamlFrontMatter(raw);
    final contentWithoutFrontMatter = _stripYamlFrontMatter(raw);
    final tags = <String>[];
    final wikilinks = <String>[];

    // 从 front matter 提取标签
    // Obsidian 格式: tags: [tag1, tag2] 或 tags:\n  - tag1\n  - tag2
    if (frontMatter.containsKey('tags')) {
      final tagValue = frontMatter['tags'];
      if (tagValue is List) {
        for (final t in tagValue) {
          final tagStr = t.toString();
          // Obsidian 标签可能以 # 开头，去除前缀
          tags.add(tagStr.startsWith('#') ? tagStr.substring(1) : tagStr);
        }
      } else if (tagValue is String) {
        // 逗号分隔或空格分隔的标签
        for (final t in tagValue.split(RegExp(r'[,，\s]+'))) {
          if (t.trim().isNotEmpty) {
            final tagStr = t.trim();
            tags.add(tagStr.startsWith('#') ? tagStr.substring(1) : tagStr);
          }
        }
      }
    }

    // 解析 [[wikilink]] 格式
    // 借鉴 Obsidian 的双向链接语法: [[笔记名]] 或 [[笔记名|显示文本]]
    // 来源: https://help.obsidian.md/Editing+and+formatting/Internal+links
    final wikilinkRegex = RegExp(r'\[\[([^\]|]+)(?:\|[^\]]+)?\]\]');
    for (final match in wikilinkRegex.allMatches(contentWithoutFrontMatter)) {
      wikilinks.add(match.group(1)!.trim());
    }

    // 从内容中提取行内标签（如 #tag），但排除标题行和代码块
    final inlineTagRegex = RegExp(r'(?:^|\s)#([a-zA-Z\u4e00-\u9fff][\w\u4e00-\u9fff/]*)');
    for (final match in inlineTagRegex.allMatches(contentWithoutFrontMatter)) {
      final tag = match.group(1)!;
      if (!tags.contains(tag)) {
        tags.add(tag);
      }
    }

    // 提取标题：优先使用 front matter 中的 title，否则从内容提取
    final title = frontMatter['title'] as String? ??
        _extractTitleFromContent(contentWithoutFrontMatter) ??
        'Untitled';

    // 提取日期
    final createdAt = _parseDateTime(frontMatter['created']) ?? DateTime.now();
    final updatedAt = _parseDateTime(frontMatter['updated']) ??
        _parseDateTime(frontMatter['date']) ??
        DateTime.now();

    return ParsedMarkdown(
      title: title,
      content: contentWithoutFrontMatter,
      tags: tags,
      wikilinks: wikilinks,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// 解析 Joplin 导出格式的 Markdown
  // 借鉴 Joplin 的导出目录结构：每个笔记一个 .md 文件，资源存放在 resources/ 子目录
  // 来源: https://joplinapp.org/help/apps/import_export/
  ParsedMarkdown _parseJoplinMarkdown(String raw) {
    final frontMatter = _parseYamlFrontMatter(raw);
    final contentWithoutFrontMatter = _stripYamlFrontMatter(raw);
    final tags = <String>[];

    // Joplin 导出格式使用 front matter 中的 tags 字段
    if (frontMatter.containsKey('tags')) {
      final tagValue = frontMatter['tags'];
      if (tagValue is List) {
        for (final t in tagValue) {
          tags.add(t.toString());
        }
      } else if (tagValue is String) {
        for (final t in tagValue.split(RegExp(r'[,，]+'))) {
          if (t.trim().isNotEmpty) {
            tags.add(t.trim());
          }
        }
      }
    }

    final title = frontMatter['title'] as String? ??
        _extractTitleFromContent(contentWithoutFrontMatter) ??
        'Untitled';

    final createdAt = _parseDateTime(frontMatter['created']) ??
        _parseDateTime(frontMatter['created_time']) ??
        DateTime.now();
    final updatedAt = _parseDateTime(frontMatter['updated']) ??
        _parseDateTime(frontMatter['updated_time']) ??
        DateTime.now();

    return ParsedMarkdown(
      title: title,
      content: contentWithoutFrontMatter,
      tags: tags,
      wikilinks: [],
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// 解析 YAML front matter
  /// 简易实现，支持基本的 key: value 和 key: [list] 格式
  // 借鉴 Obsidian 的 Properties (YAML front matter) 格式
  // 来源: https://help.obsidian.md/Editing+and+formatting/Properties
  Map<String, dynamic> _parseYamlFrontMatter(String raw) {
    final result = <String, dynamic>{};

    // front matter 以 --- 包裹，位于文件开头
    final frontMatterRegex = RegExp(r'^---\s*\n([\s\S]*?)\n---');
    final match = frontMatterRegex.firstMatch(raw);
    if (match == null) return result;

    final yamlContent = match.group(1)!;
    String? currentKey;
    final listItems = <String>[];

    for (final line in yamlContent.split('\n')) {
      // 列表项：以 "  - " 开头
      final listMatch = RegExp(r'^\s+-\s+(.+)$').firstMatch(line);
      if (listMatch != null && currentKey != null) {
        listItems.add(listMatch.group(1)!.trim());
        continue;
      }

      // 如果之前在收集列表项，先保存
      if (currentKey != null && listItems.isNotEmpty) {
        result[currentKey] = List<String>.from(listItems);
        listItems.clear();
      }

      // 键值对：key: value
      final kvMatch = RegExp(r'^([a-zA-Z_][\w]*)\s*:\s*(.*)$').firstMatch(line);
      if (kvMatch != null) {
        currentKey = kvMatch.group(1)!;
        final value = kvMatch.group(2)!.trim();

        if (value.isEmpty) {
          // 值为空，可能是多行列表的开始
          listItems.clear();
          continue;
        }

        // 行内列表格式：[item1, item2]
        final inlineListMatch = RegExp(r'^\[(.+)\]$').firstMatch(value);
        if (inlineListMatch != null) {
          final items = inlineListMatch
              .group(1)!
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          result[currentKey] = items;
          currentKey = null;
        } else {
          result[currentKey] = value;
          currentKey = null;
        }
      }
    }

    // 处理最后可能残留的列表
    if (currentKey != null && listItems.isNotEmpty) {
      result[currentKey] = List<String>.from(listItems);
    }

    return result;
  }

  /// 去除 YAML front matter，返回纯内容
  String _stripYamlFrontMatter(String raw) {
    final frontMatterRegex = RegExp(r'^---\s*\n[\s\S]*?\n---\s*\n?');
    return raw.replaceFirst(frontMatterRegex, '');
  }

  /// 从 Markdown 内容中提取标题（第一个 # 标题行）
  String? _extractTitleFromContent(String content) {
    final titleRegex = RegExp(r'^#\s+(.+)$', multiLine: true);
    final match = titleRegex.firstMatch(content);
    return match?.group(1)?.trim();
  }

  /// 解析日期时间字符串
  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    final str = value.toString();
    return DateTime.tryParse(str);
  }

  /// 确保文件夹路径存在，返回最终文件夹 ID
  /// relativePath 如 "sub1/sub2"，会在 targetFolderId 下逐级创建
  Future<String> _ensureFolderPath(String relativePath, String targetFolderId) async {
    if (relativePath == '.' || relativePath.isEmpty) {
      return targetFolderId;
    }

    // 检查缓存
    final cacheKey = '$targetFolderId/$relativePath';
    if (_folderCache.containsKey(cacheKey)) {
      return _folderCache[cacheKey]!;
    }

    final segments = p.split(relativePath);
    var currentParentId = targetFolderId;

    for (final segment in segments) {
      if (segment.isEmpty || segment == '.') continue;

      final segmentCacheKey = '$currentParentId/$segment';
      if (_folderCache.containsKey(segmentCacheKey)) {
        currentParentId = _folderCache[segmentCacheKey]!;
        continue;
      }

      // 查找是否已存在同名子文件夹
      final subFolders = await _folderRepository.listFolders(currentParentId);
      final existing = subFolders.where((f) => f.name == segment).toList();

      if (existing.isNotEmpty) {
        currentParentId = existing.first.id;
      } else {
        // 创建新文件夹
        final now = DateTime.now();
        final folder = FolderModel(
          id: _uuid.v4(),
          name: segment,
          parentId: currentParentId,
          createdAt: now,
          updatedAt: now,
        );
        await _folderRepository.createFolder(folder);
        currentParentId = folder.id;
      }

      _folderCache[segmentCacheKey] = currentParentId;
    }

    _folderCache[cacheKey] = currentParentId;
    return currentParentId;
  }

  /// 确保标签存在，返回标签 ID
  /// 修复：原代码直接创建新标签不检查数据库已有标签，导致同一标签名重复创建
  Future<String> _ensureTag(String tagName) async {
    if (_tagCache.containsKey(tagName)) {
      return _tagCache[tagName]!;
    }

    // 先检查数据库中是否已存在同名标签
    final allTags = await _tagRepository.getAllTags();
    final existing = allTags.where((t) => t.name == tagName).toList();
    if (existing.isNotEmpty) {
      _tagCache[tagName] = existing.first.id;
      return existing.first.id;
    }

    final tag = TagModel(
      id: _uuid.v4(),
      name: tagName,
      createdAt: DateTime.now(),
    );
    await _tagRepository.createTag(tag);
    _tagCache[tagName] = tag.id;
    return tag.id;
  }

  /// 从 Markdown 文件导入笔记
  /// 借鉴 Joplin 的 Markdown 导入功能
  // 来源: https://joplinapp.org/help/apps/import_export/
  Future<String> importFromMarkdown(String filePath, {String? folderId}) async {
    final file = File(filePath);
    final raw = await file.readAsString();

    // 去除 YAML front matter，获取纯内容
    final content = _stripYamlFrontMatter(raw);

    // 标题：第一个 heading 或文件名
    final title =
        _extractTitleFromContent(content) ?? p.basenameWithoutExtension(filePath);

    // 创建笔记
    final now = DateTime.now();
    final noteId = _uuid.v4();
    final note = NoteModel(
      id: noteId,
      title: title,
      content: content,
      folderId: folderId ?? '',
      createdAt: now,
      updatedAt: now,
    );
    await _noteRepository.createNote(note);

    // 解析 Markdown 为块并逐个创建
    final parsedBlocks = _parseMarkdownToBlocks(content);
    for (var i = 0; i < parsedBlocks.length; i++) {
      final parsed = parsedBlocks[i];
      await _editorService.createBlock(
        noteId: noteId,
        blockType: parsed.blockType,
        content: parsed.content,
        position: i,
      );
    }

    return noteId;
  }

  /// 批量从目录导入 Markdown 文件
  Future<int> importFromDirectory(String dirPath, {String? folderId}) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return 0;

    // 列出目录中所有 .md 文件
    final mdFiles = _collectMdFilesSync(dir);
    var count = 0;

    for (final file in mdFiles) {
      try {
        await importFromMarkdown(file.path, folderId: folderId);
        count++;
      } catch (_) {
        // 单个文件导入失败不影响整体流程，跳过继续
        continue;
      }
    }

    return count;
  }

  /// 将 Markdown 内容解析为块列表
  /// 支持：标题、代码块、引用、无序列表、有序列表、任务列表、分隔线、表格、图片、段落
  List<_ParsedBlock> _parseMarkdownToBlocks(String content) {
    final lines = content.split('\n');
    final blocks = <_ParsedBlock>[];
    var i = 0;

    // 任务列表行正则：- [ ] / - [x] / * [ ] / * [x]
    final taskRegex = RegExp(r'^[-*]\s+\[[xX ]\]\s+.*$');
    // 有序列表行正则：1. item
    final orderedRegex = RegExp(r'^\d+\.\s+(.*)$');
    // 图片行正则：![alt](path)
    final imageRegex = RegExp(r'^!\[.*\]\(.*\)\s*$');
    // 分隔线正则：---（三个及以上连字符）
    final dividerRegex = RegExp(r'^-{3,}\s*$');

    while (i < lines.length) {
      final line = lines[i];

      // 代码块：```language ... ```
      if (line.startsWith('```')) {
        final language = line.length > 3 ? line.substring(3).trim() : null;
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        blocks.add(_ParsedBlock(
          BlockType.codeBlock,
          codeLines.join('\n'),
          language: language,
        ));
        i++; // 跳过结束的 ```
        continue;
      }

      // 标题（从长到短匹配，避免 # 被 ## 误匹配）
      if (line.startsWith('###### ')) {
        blocks.add(_ParsedBlock(BlockType.heading6, line.substring(7)));
        i++;
        continue;
      }
      if (line.startsWith('##### ')) {
        blocks.add(_ParsedBlock(BlockType.heading5, line.substring(6)));
        i++;
        continue;
      }
      if (line.startsWith('#### ')) {
        blocks.add(_ParsedBlock(BlockType.heading4, line.substring(5)));
        i++;
        continue;
      }
      if (line.startsWith('### ')) {
        blocks.add(_ParsedBlock(BlockType.heading3, line.substring(4)));
        i++;
        continue;
      }
      if (line.startsWith('## ')) {
        blocks.add(_ParsedBlock(BlockType.heading2, line.substring(3)));
        i++;
        continue;
      }
      if (line.startsWith('# ')) {
        blocks.add(_ParsedBlock(BlockType.heading1, line.substring(2)));
        i++;
        continue;
      }

      // 任务列表：- [ ] / - [x] / * [ ] / * [x]
      if (taskRegex.hasMatch(line)) {
        final taskLines = <String>[line];
        i++;
        while (i < lines.length && taskRegex.hasMatch(lines[i])) {
          taskLines.add(lines[i]);
          i++;
        }
        blocks.add(_ParsedBlock(BlockType.taskListBlock, taskLines.join('\n')));
        continue;
      }

      // 分隔线：---
      if (dividerRegex.hasMatch(line)) {
        blocks.add(_ParsedBlock(BlockType.paragraph, '---'));
        i++;
        continue;
      }

      // 引用块：> text
      if (line.startsWith('> ')) {
        final quoteLines = <String>[line.substring(2)];
        i++;
        while (i < lines.length && lines[i].startsWith('> ')) {
          quoteLines.add(lines[i].substring(2));
          i++;
        }
        blocks.add(_ParsedBlock(BlockType.quote, quoteLines.join('\n')));
        continue;
      }

      // 有序列表：1. item
      if (orderedRegex.hasMatch(line)) {
        final listLines = <String>[orderedRegex.firstMatch(line)!.group(1)!];
        i++;
        while (i < lines.length && orderedRegex.hasMatch(lines[i])) {
          listLines.add(orderedRegex.firstMatch(lines[i])!.group(1)!);
          i++;
        }
        blocks.add(_ParsedBlock(BlockType.orderedList, listLines.join('\n')));
        continue;
      }

      // 无序列表：- item / * item
      if (line.startsWith('- ') || line.startsWith('* ')) {
        final listLines = <String>[line.substring(2)];
        i++;
        while (i < lines.length &&
            (lines[i].startsWith('- ') || lines[i].startsWith('* '))) {
          listLines.add(lines[i].substring(2));
          i++;
        }
        blocks.add(_ParsedBlock(BlockType.list, listLines.join('\n')));
        continue;
      }

      // 表格：| col1 | col2 |
      if (line.trim().startsWith('|') && line.trim().endsWith('|')) {
        final tableLines = <String>[line];
        i++;
        while (i < lines.length &&
            lines[i].trim().startsWith('|') &&
            lines[i].trim().endsWith('|')) {
          tableLines.add(lines[i]);
          i++;
        }
        blocks.add(_ParsedBlock(BlockType.tableBlock, tableLines.join('\n')));
        continue;
      }

      // 图片：![alt](path)
      if (imageRegex.hasMatch(line)) {
        blocks.add(_ParsedBlock(BlockType.image, line.trim()));
        i++;
        continue;
      }

      // 空行：跳过
      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      // 段落：连续非空行（直到遇到特殊语法）
      final paragraphLines = <String>[line];
      i++;
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !lines[i].startsWith('#') &&
          !lines[i].startsWith('```') &&
          !lines[i].startsWith('> ') &&
          !lines[i].startsWith('- ') &&
          !lines[i].startsWith('* ') &&
          !orderedRegex.hasMatch(lines[i]) &&
          !taskRegex.hasMatch(lines[i]) &&
          !dividerRegex.hasMatch(lines[i]) &&
          !imageRegex.hasMatch(lines[i]) &&
          !(lines[i].trim().startsWith('|') &&
              lines[i].trim().endsWith('|'))) {
        paragraphLines.add(lines[i]);
        i++;
      }
      blocks.add(_ParsedBlock(
        BlockType.paragraph,
        paragraphLines.join('\n'),
      ));
    }

    return blocks;
  }

  void dispose() {
    _progressController.close();
  }
}

/// Markdown 解析结果的内部数据类
class ParsedMarkdown {
  final String title;
  final String content;
  final List<String> tags;
  final List<String> wikilinks;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ParsedMarkdown({
    required this.title,
    required this.content,
    required this.tags,
    required this.wikilinks,
    required this.createdAt,
    required this.updatedAt,
  });
}

/// Markdown 解析为块的中间结果（仅供 ImportService 内部使用）
class _ParsedBlock {
  final BlockType blockType;
  final String content;
  final String? language;

  const _ParsedBlock(this.blockType, this.content, {this.language});
}
