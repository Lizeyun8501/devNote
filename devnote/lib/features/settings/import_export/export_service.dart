// 导出服务 —— 将笔记导出为 Markdown 或 HTML 格式
// 借鉴 Joplin 的导出格式：按文件夹结构组织导出文件
// 来源: https://joplinapp.org/help/apps/import_export/
// 借鉴 Obsidian 的 Markdown 导出风格：保留 front matter 和 wikilink
// 来源: https://help.obsidian.md/Editing+and+formatting/Properties

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:devnote/core/persistence/note_repository.dart';
import 'package:devnote/core/persistence/folder_repository.dart';
import 'package:devnote/core/persistence/tag_repository.dart';
import 'package:devnote/core/persistence/models/note_model.dart';
import 'package:devnote/core/persistence/models/folder_model.dart';
import 'package:devnote/core/persistence/models/tag_model.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import 'package:devnote/features/editor/services/editor_service.dart';

enum ExportRange {
  all,
  folder,
  tag,
}

enum ExportFormat {
  markdown,
  html,
  pdf,
}

class ExportProgress {
  final int current;
  final int total;
  final String currentFile;
  final bool isComplete;

  const ExportProgress({
    this.current = 0,
    this.total = 0,
    this.currentFile = '',
    this.isComplete = false,
  });

  double get progress => total > 0 ? current / total : 0.0;
}

class ExportService {
  final NoteRepository _noteRepository;
  final FolderRepository _folderRepository;
  final TagRepository _tagRepository;
  final EditorService _editorService;
  final _progressController = StreamController<ExportProgress>.broadcast();

  ExportService({
    required NoteRepository noteRepository,
    required FolderRepository folderRepository,
    required TagRepository tagRepository,
    EditorService? editorService,
  })  : _noteRepository = noteRepository,
        _folderRepository = folderRepository,
        _tagRepository = tagRepository,
        _editorService = editorService ?? EditorService();

  Stream<ExportProgress> get progressStream => _progressController.stream;

  Future<void> export({
    required ExportRange range,
    required ExportFormat format,
    required String targetPath,
    String? folderId,
    String? tagName,
  }) async {
    _progressController.add(const ExportProgress());

    // 根据导出范围收集笔记
    final notes = await _collectNotes(range: range, folderId: folderId, tagName: tagName);
    if (notes.isEmpty) {
      _progressController.add(const ExportProgress(isComplete: true));
      return;
    }

    // 确保目标目录存在
    final targetDir = Directory(targetPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final total = notes.length;

    for (var i = 0; i < notes.length; i++) {
      final note = notes[i];
      final fileName = _sanitizeFileName(note.title);

      _progressController.add(ExportProgress(
        current: i + 1,
        total: total,
        currentFile: fileName,
        isComplete: false,
      ));

      try {
        // 获取笔记所在文件夹路径，用于在目标目录下重建文件夹结构
        final folderPath = await _buildFolderPath(note.folderId);
        final noteDir = folderPath.isNotEmpty
            ? Directory(p.join(targetPath, folderPath))
            : targetDir;

        if (!await noteDir.exists()) {
          await noteDir.create(recursive: true);
        }

        // 获取笔记标签
        final tags = await _tagRepository.getTagsForNote(note.id);

        // 根据格式写入文件
        final ext = format == ExportFormat.html ? '.html' : '.md';
        final file = File(p.join(noteDir.path, '$fileName$ext'));

        if (format == ExportFormat.markdown) {
          await _writeMarkdownFile(file, note, tags);
        } else {
          await _writeHtmlFile(file, note, tags);
        }
      } catch (_) {
        // 单个文件导出失败不影响整体流程，跳过继续
        continue;
      }
    }

    _progressController.add(ExportProgress(
      current: total,
      total: total,
      currentFile: '',
      isComplete: true,
    ));
  }

  /// 根据导出范围收集笔记
  Future<List<NoteModel>> _collectNotes({
    required ExportRange range,
    String? folderId,
    String? tagName,
  }) async {
    switch (range) {
      case ExportRange.all:
        return _collectAllNotes();
      case ExportRange.folder:
        if (folderId == null) return [];
        return _collectFolderNotes(folderId);
      case ExportRange.tag:
        if (tagName == null) return [];
        return _collectTagNotes(tagName);
    }
  }

  /// 收集所有笔记：遍历所有文件夹获取全部笔记，包括根目录下的笔记
  /// 修复：原代码只从根文件夹获取笔记，遗漏了 folderId 为空字符串的根级别笔记
  Future<List<NoteModel>> _collectAllNotes() async {
    final allNotes = <NoteModel>[];

    // 先获取根级别（folderId 为空）的笔记
    final rootNotes = await _noteRepository.listNotes('');
    allNotes.addAll(rootNotes);

    // 获取根文件夹下的笔记
    final rootFolders = await _folderRepository.listFolders(null);
    for (final folder in rootFolders) {
      final notes = await _noteRepository.listNotes(folder.id);
      allNotes.addAll(notes);
      // 递归获取子文件夹中的笔记
      await _collectSubFolderNotes(folder.id, allNotes);
    }

    return allNotes;
  }

  /// 递归收集子文件夹中的笔记
  Future<void> _collectSubFolderNotes(String parentId, List<NoteModel> result) async {
    final subFolders = await _folderRepository.listFolders(parentId);
    for (final folder in subFolders) {
      final notes = await _noteRepository.listNotes(folder.id);
      result.addAll(notes);
      await _collectSubFolderNotes(folder.id, result);
    }
  }

  /// 收集指定文件夹及其子文件夹下的笔记
  Future<List<NoteModel>> _collectFolderNotes(String folderId) async {
    final notes = <NoteModel>[];
    notes.addAll(await _noteRepository.listNotes(folderId));
    await _collectSubFolderNotes(folderId, notes);
    return notes;
  }

  /// 收集带有指定标签的笔记
  // 借鉴 Joplin 的按标签筛选导出方式
  // 来源: https://joplinapp.org/help/apps/import_export/
  Future<List<NoteModel>> _collectTagNotes(String tagName) async {
    // 由于 TagRepository 没有直接按标签查笔记的方法，
    // 需要遍历所有笔记并筛选匹配标签的笔记
    final allNotes = await _collectAllNotes();
    final result = <NoteModel>[];

    for (final note in allNotes) {
      final tags = await _tagRepository.getTagsForNote(note.id);
      if (tags.any((t) => t.name == tagName)) {
        result.add(note);
      }
    }

    return result;
  }

  /// 构建文件夹路径（从当前文件夹到根的路径）
  Future<String> _buildFolderPath(String folderId) async {
    final segments = <String>[];
    var currentId = folderId;

    while (currentId.isNotEmpty) {
      // 通过 listFolders 查找当前文件夹（需要遍历查找）
      final folder = await _findFolderById(currentId);
      if (folder == null) break;

      segments.insert(0, _sanitizeFileName(folder.name));
      currentId = folder.parentId ?? '';
    }

    return p.joinAll(segments);
  }

  /// 通过 ID 查找文件夹
  /// 由于 FolderRepository 没有 getById 方法，需要遍历查找
  Future<FolderModel?> _findFolderById(String folderId) async {
    return _findFolderInSubtree(null, folderId);
  }

  /// 在文件夹树中递归查找指定 ID 的文件夹
  Future<FolderModel?> _findFolderInSubtree(String? parentId, String targetId) async {
    final folders = await _folderRepository.listFolders(parentId);
    for (final folder in folders) {
      if (folder.id == targetId) return folder;
      final found = await _findFolderInSubtree(folder.id, targetId);
      if (found != null) return found;
    }
    return null;
  }

  /// 将笔记写入 Markdown 文件
  // 借鉴 Obsidian 的导出格式：包含 YAML front matter
  // 来源: https://help.obsidian.md/Editing+and+formatting/Properties
  Future<void> _writeMarkdownFile(File file, NoteModel note, List<TagModel> tags) async {
    final buffer = StringBuffer();

    // 写入 YAML front matter
    buffer.writeln('---');
    buffer.writeln('title: ${note.title}');
    if (tags.isNotEmpty) {
      buffer.writeln('tags: [${tags.map((t) => t.name).join(', ')}]');
    }
    buffer.writeln('created: ${note.createdAt.toIso8601String()}');
    buffer.writeln('updated: ${note.updatedAt.toIso8601String()}');
    buffer.writeln('---');
    buffer.writeln();

    // 写入笔记内容
    buffer.write(note.content);

    await file.writeAsString(buffer.toString());
  }

  /// 将笔记写入 HTML 文件
  Future<void> _writeHtmlFile(File file, NoteModel note, List<TagModel> tags) async {
    final buffer = StringBuffer();

    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="zh-CN">');
    buffer.writeln('<head>');
    buffer.writeln('  <meta charset="UTF-8">');
    buffer.writeln('  <meta name="viewport" content="width=device-width, initial-scale=1.0">');
    buffer.writeln('  <title>${_escapeHtml(note.title)}</title>');
    buffer.writeln('  <style>');
    buffer.writeln('    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }');
    buffer.writeln('    h1 { border-bottom: 1px solid #eee; padding-bottom: 10px; }');
    buffer.writeln('    .meta { color: #888; font-size: 0.85em; margin-bottom: 20px; }');
    buffer.writeln('    .tags span { background: #f0f0f0; border-radius: 3px; padding: 2px 8px; margin-right: 4px; font-size: 0.85em; }');
    buffer.writeln('    pre { background: #f5f5f5; padding: 12px; border-radius: 4px; overflow-x: auto; }');
    buffer.writeln('    code { background: #f5f5f5; padding: 2px 4px; border-radius: 3px; }');
    buffer.writeln('    blockquote { border-left: 3px solid #ddd; margin-left: 0; padding-left: 16px; color: #666; }');
    buffer.writeln('  </style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');

    // 标题
    buffer.writeln('  <h1>${_escapeHtml(note.title)}</h1>');

    // 元信息
    buffer.writeln('  <div class="meta">');
    buffer.writeln('    <div>创建: ${note.createdAt.toLocal().toString()}</div>');
    buffer.writeln('    <div>更新: ${note.updatedAt.toLocal().toString()}</div>');
    if (tags.isNotEmpty) {
      buffer.writeln('    <div class="tags">标签: ${tags.map((t) => '<span>${_escapeHtml(t.name)}</span>').join(' ')}</div>');
    }
    buffer.writeln('  </div>');

    // 内容：将 Markdown 基本语法转换为 HTML
    buffer.writeln('  <div class="content">');
    buffer.writeln(_markdownToHtml(note.content));
    buffer.writeln('  </div>');

    buffer.writeln('</body>');
    buffer.writeln('</html>');

    await file.writeAsString(buffer.toString());
  }

  /// 简易 Markdown 转 HTML
  /// 仅处理常见语法：标题、粗体、斜体、代码块、列表、引用、链接
  String _markdownToHtml(String md) {
    var html = md;

    // 转义 HTML 特殊字符（先于其他处理）
    // 注意：代码块内容需要特殊处理，这里简化处理

    // 代码块：```...```
    html = html.replaceAllMapped(
      RegExp(r'```(\w*)\n([\s\S]*?)```'),
      (m) => '<pre><code>${_escapeHtml(m.group(2)!)}</code></pre>',
    );

    // 行内代码：`...`
    html = html.replaceAllMapped(
      RegExp(r'`([^`]+)`'),
      (m) => '<code>${_escapeHtml(m.group(1)!)}</code>',
    );

    // 标题
    html = html.replaceAllMapped(RegExp(r'^######\s+(.+)$', multiLine: true), (m) => '<h6>${m.group(1)}</h6>');
    html = html.replaceAllMapped(RegExp(r'^#####\s+(.+)$', multiLine: true), (m) => '<h5>${m.group(1)}</h5>');
    html = html.replaceAllMapped(RegExp(r'^####\s+(.+)$', multiLine: true), (m) => '<h4>${m.group(1)}</h4>');
    html = html.replaceAllMapped(RegExp(r'^###\s+(.+)$', multiLine: true), (m) => '<h3>${m.group(1)}</h3>');
    html = html.replaceAllMapped(RegExp(r'^##\s+(.+)$', multiLine: true), (m) => '<h2>${m.group(1)}</h2>');
    html = html.replaceAllMapped(RegExp(r'^#\s+(.+)$', multiLine: true), (m) => '<h1>${m.group(1)}</h1>');

    // 粗体
    html = html.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => '<strong>${m.group(1)}</strong>');
    // 斜体
    html = html.replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => '<em>${m.group(1)}</em>');

    // 引用块
    html = html.replaceAllMapped(RegExp(r'^>\s+(.+)$', multiLine: true), (m) => '<blockquote>${m.group(1)}</blockquote>');

    // 无序列表
    html = html.replaceAllMapped(RegExp(r'^[-*]\s+(.+)$', multiLine: true), (m) => '<li>${m.group(1)}</li>');

    // 链接
    html = html.replaceAllMapped(RegExp(r'\[([^\]]+)\]\(([^)]+)\)'), (m) => '<a href="${m.group(2)}">${m.group(1)}</a>');

    // [[wikilink]] 转为简单链接
    // 借鉴 Obsidian 的 wikilink 格式
    // 来源: https://help.obsidian.md/Editing+and+formatting/Internal+links
    html = html.replaceAllMapped(
      RegExp(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]'),
      (m) => '<a href="${_escapeHtml(m.group(1)!)}.html">${_escapeHtml(m.group(2) ?? m.group(1)!)}</a>',
    );

    // 段落：将连续空行分隔的文本包裹在 <p> 标签中
    html = html.replaceAllMapped(
      RegExp(r'([^\n]+)(?:\n\n|\n*$)'),
      (m) {
        final text = m.group(1)!.trim();
        if (text.isEmpty) return '';
        // 跳过已经是 HTML 标签的行
        if (text.startsWith('<')) return text;
        return '<p>${_escapeHtml(text)}</p>';
      },
    );

    return html;
  }

  /// HTML 特殊字符转义
  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  /// 文件名安全化：去除不合法字符
  String _sanitizeFileName(String name) {
    // 去除文件名中不允许的字符
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  }

  /// 将笔记导出为 Markdown 文件
  /// 借鉴 Obsidian 的纯 Markdown 存储策略 —— 零数据锁定
  // 来源: https://help.obsidian.md/Editing+and+formatting/Properties
  Future<void> exportNoteAsMarkdown(String noteId, String outputPath) async {
    final note = await _noteRepository.getNote(noteId);
    if (note == null) return;

    // 获取笔记的所有块
    final blocks = await _editorService.listBlocks(noteId);

    final buffer = StringBuffer();

    // 写入 YAML front matter，保留元数据以便往返导入
    buffer.writeln('---');
    buffer.writeln('title: ${note.title}');
    buffer.writeln('created: ${note.createdAt.toIso8601String()}');
    buffer.writeln('updated: ${note.updatedAt.toIso8601String()}');
    buffer.writeln('---');
    buffer.writeln();

    if (blocks.isEmpty) {
      // 无块数据时回退到 note.content（兼容旧数据）
      buffer.write(note.content);
    } else {
      // 逐块转换为 Markdown
      for (final block in blocks) {
        buffer.writeln(_blockToMarkdown(block));
        buffer.writeln();
      }
    }

    // 确保输出目录存在并写入文件
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(buffer.toString());
  }

  /// 批量导出所有笔记为 Markdown 文件（保持文件夹结构）
  Future<void> exportAllAsMarkdown(String outputDir) async {
    final notes = await _collectAllNotes();

    final dir = Directory(outputDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    for (final note in notes) {
      try {
        // 重建文件夹结构
        final folderPath = await _buildFolderPath(note.folderId);
        final noteDir = folderPath.isNotEmpty
            ? Directory(p.join(outputDir, folderPath))
            : dir;
        if (!await noteDir.exists()) {
          await noteDir.create(recursive: true);
        }

        // 文件名 = 笔记标题（清理非法字符）
        final fileName = _sanitizeFileName(note.title);
        final outputPath = p.join(noteDir.path, '$fileName.md');
        await exportNoteAsMarkdown(note.id, outputPath);
      } catch (_) {
        // 单个笔记导出失败不影响整体流程，跳过继续
        continue;
      }
    }
  }

  /// 将单个块转换为 Markdown 文本
  String _blockToMarkdown(BlockModel block) {
    switch (block.blockType) {
      case BlockType.heading1:
        return '# ${block.content}';
      case BlockType.heading2:
        return '## ${block.content}';
      case BlockType.heading3:
        return '### ${block.content}';
      case BlockType.heading4:
        return '#### ${block.content}';
      case BlockType.heading5:
        return '##### ${block.content}';
      case BlockType.heading6:
        return '###### ${block.content}';
      case BlockType.paragraph:
        return block.content;
      case BlockType.codeBlock:
        final lang = block.language ?? '';
        return '```$lang\n${block.content}\n```';
      case BlockType.quote:
        return block.content.split('\n').map((l) => '> $l').join('\n');
      case BlockType.list:
        return block.content
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .map((l) => '- $l')
            .join('\n');
      case BlockType.orderedList:
        var idx = 1;
        return block.content
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .map((l) => '${idx++}. $l')
            .join('\n');
      case BlockType.taskListBlock:
        // 任务列表内容已包含 - [x] / - [ ] 前缀
        return block.content;
      case BlockType.tableBlock:
        // 表格内容为原始 Markdown 表格语法
        return block.content;
      case BlockType.image:
        // 图片内容可能为路径或完整 Markdown 语法
        if (block.content.startsWith('![')) {
          return block.content;
        }
        return '![image](${block.content})';
      case BlockType.latexBlock:
        return '\$\$\n${block.content}\n\$\$';
      case BlockType.pdf:
        // PDF 块内容为 JSON 元数据，导出为占位链接
        return '[PDF](${block.content})';
      case BlockType.whiteboard:
        // 白板内容为元素 JSON，导出为占位符（无法用 Markdown 表示）
        return '[Whiteboard]';
      case BlockType.audio:
        // 音频块内容为文件路径，导出为占位链接
        return '[Audio](${block.content})';
    }
  }

  void dispose() {
    _progressController.close();
  }
}
