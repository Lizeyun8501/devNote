import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

/// 代码片段数据模型
///
/// ## 借鉴的开源项目
/// - **VS Code Snippets** ([官方文档](https://code.visualstudio.com/docs/editor/userdefinedsnippets)):
///   借鉴其代码片段的结构化存储方式（标题、语言、代码、标签）
/// - **GitHub Gist** ([https://gist.github.com](https://gist.github.com/)):
///   借鉴其代码分享机制，使用标签进行分类管理
class CodeSnippetModel {
  final String id;
  final String title;
  final String language;
  final String code;
  final List<String> tags;
  final DateTime createdAt;

  const CodeSnippetModel({
    required this.id,
    required this.title,
    required this.language,
    required this.code,
    this.tags = const [],
    required this.createdAt,
  });

  CodeSnippetModel copyWith({
    String? id,
    String? title,
    String? language,
    String? code,
    List<String>? tags,
    DateTime? createdAt,
  }) {
    return CodeSnippetModel(
      id: id ?? this.id,
      title: title ?? this.title,
      language: language ?? this.language,
      code: code ?? this.code,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'language': language,
        'code': code,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
      };

  factory CodeSnippetModel.fromJson(Map<String, dynamic> json) =>
      CodeSnippetModel(
        id: json['id'] as String,
        title: json['title'] as String,
        language: json['language'] as String? ?? '',
        code: json['code'] as String,
        tags: (json['tags'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// 代码片段存储服务
///
/// ## 借鉴的开源项目
/// - **VS Code Snippets** ([官方文档](https://code.visualstudio.com/docs/editor/userdefinedsnippets)):
///   借鉴其基于 JSON 文件的本地存储机制，支持片段的增删查改
/// - **GitHub Gist** ([https://gist.github.com](https://gist.github.com/)):
///   借鉴其代码片段的导入导出机制，支持 JSON 文件的导入/导出
///
/// ## 实现说明
/// 使用 JSON 文件持久化代码片段，支持按标签、语言过滤查询。
/// 提供导入/导出功能，方便片段迁移和备份。
class CodeSnippetService {
  static const String _fileName = 'code_snippets.json';
  final List<CodeSnippetModel> _snippets = [];

  List<CodeSnippetModel> get snippets => List.unmodifiable(_snippets);

  /// 获取所有已使用的语言列表
  List<String> get languages {
    final langs = <String>{};
    for (final snippet in _snippets) {
      if (snippet.language.isNotEmpty) {
        langs.add(snippet.language);
      }
    }
    return langs.toList()..sort();
  }

  /// 获取所有已使用的标签列表
  List<String> get allTags {
    final tags = <String>{};
    for (final snippet in _snippets) {
      tags.addAll(snippet.tags);
    }
    return tags.toList()..sort();
  }

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// 从本地文件加载代码片段
  Future<void> load() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
        _snippets.clear();
        _snippets.addAll(
          jsonList
              .map((e) => CodeSnippetModel.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      }
    } catch (_) {
      _snippets.clear();
    }
  }

  /// 保存代码片段到本地文件
  Future<void> save() async {
    final file = await _getFile();
    final jsonList = _snippets.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }

  /// 保存代码片段（借鉴 VS Code Snippets 的结构化存储）
  Future<void> saveSnippet(
    String title,
    String language,
    String code,
    List<String> tags,
  ) async {
    final snippet = CodeSnippetModel(
      id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      title: title,
      language: language,
      code: code,
      tags: tags,
      createdAt: DateTime.now(),
    );
    _snippets.add(snippet);
    await save();
  }

  /// 列出代码片段，支持按标签或语言过滤
  ///
  /// 借鉴 VS Code 的片段过滤机制：按语言/标签筛选
  Future<List<CodeSnippetModel>> listSnippets({
    String? tag,
    String? language,
  }) async {
    var results = List<CodeSnippetModel>.from(_snippets);

    if (tag != null && tag.isNotEmpty) {
      results = results
          .where((s) => s.tags.map((t) => t.toLowerCase()).contains(tag.toLowerCase()))
          .toList();
    }

    if (language != null && language.isNotEmpty) {
      results = results
          .where((s) => s.language.toLowerCase() == language.toLowerCase())
          .toList();
    }

    // 按创建时间倒序
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  /// 删除代码片段
  Future<void> deleteSnippet(String id) async {
    _snippets.removeWhere((s) => s.id == id);
    await save();
  }

  /// 更新代码片段
  Future<void> updateSnippet(String id, {
    String? title,
    String? language,
    String? code,
    List<String>? tags,
  }) async {
    final index = _snippets.indexWhere((s) => s.id == id);
    if (index == -1) throw StateError('Snippet not found: $id');
    _snippets[index] = _snippets[index].copyWith(
      title: title,
      language: language,
      code: code,
      tags: tags,
    );
    await save();
  }

  /// 导出代码片段到 JSON 文件（借鉴 GitHub Gist 的导出格式）
  Future<void> exportSnippets(String path) async {
    final jsonList = _snippets.map((e) => e.toJson()).toList();
    final file = File(path);
    await file.writeAsString(jsonEncode(jsonList));
  }

  /// 从 JSON 文件导入代码片段（借鉴 GitHub Gist 的导入格式）
  Future<void> importSnippets(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Import file not found', path);
    }
    final content = await file.readAsString();
    final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
    final imported = jsonList
        .map((e) => CodeSnippetModel.fromJson(e as Map<String, dynamic>))
        .toList();
    _snippets.addAll(imported);
    await save();
  }

  /// 全文搜索代码片段
  List<CodeSnippetModel> search(String query) {
    if (query.isEmpty) return List.of(_snippets);
    final lowerQuery = query.toLowerCase();
    return _snippets.where((s) {
      return s.title.toLowerCase().contains(lowerQuery) ||
          s.code.toLowerCase().contains(lowerQuery) ||
          s.language.toLowerCase().contains(lowerQuery) ||
          s.tags.any((t) => t.toLowerCase().contains(lowerQuery));
    }).toList();
  }

  /// 复制代码到剪贴板
  Future<void> copyToClipboard(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
  }
}

/// 代码片段收藏管理页面
///
/// ## 借鉴的开源项目
/// - **VS Code Snippets** ([官方文档](https://code.visualstudio.com/docs/editor/userdefinedsnippets)):
///   借鉴其代码片段的展示与编辑界面设计
/// - **GitHub Gist** ([https://gist.github.com](https://gist.github.com/)):
///   借鉴其代码片段的标签管理和搜索功能
class CodeSnippetManager extends StatefulWidget {
  const CodeSnippetManager({super.key});

  @override
  State<CodeSnippetManager> createState() => _CodeSnippetManagerState();
}

class _CodeSnippetManagerState extends State<CodeSnippetManager> {
  final CodeSnippetService _service = CodeSnippetService();
  final TextEditingController _searchController = TextEditingController();
  List<CodeSnippetModel> _displayedSnippets = [];
  String? _filterTag;
  String? _filterLanguage;

  @override
  void initState() {
    super.initState();
    _loadSnippets();
  }

  Future<void> _loadSnippets() async {
    await _service.load();
    _refreshDisplayedSnippets();
  }

  void _refreshDisplayedSnippets() {
    setState(() {
      _displayedSnippets = _service.snippets;
    });
  }

  void _applyFilters() {
    setState(() {
      _displayedSnippets = _service.search(_searchController.text);
      if (_filterTag != null) {
        _displayedSnippets = _displayedSnippets
            .where((s) => s.tags.contains(_filterTag))
            .toList();
      }
      if (_filterLanguage != null) {
        _displayedSnippets = _displayedSnippets
            .where((s) => s.language == _filterLanguage)
            .toList();
      }
    });
  }

  Future<void> _showAddSnippetDialog() async {
    final titleController = TextEditingController();
    final codeController = TextEditingController();
    final languageController = TextEditingController();
    final tagController = TextEditingController();

    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增代码片段'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: languageController,
                decoration: const InputDecoration(
                  labelText: '语言 (如 dart, python, rust)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: '代码'),
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: tagController,
                decoration: const InputDecoration(
                  labelText: '标签 (逗号分隔)',
                  hintText: 'util, async, example',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final title = titleController.text.trim();
              final code = codeController.text.trim();
              final language = languageController.text.trim();
              if (title.isEmpty || code.isEmpty) return;
              final tags = tagController.text
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toList();
              await _service.saveSnippet(title, language, code, tags);
              _refreshDisplayedSnippets();
              if (mounted) Navigator.of(ctx).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _showExportDialog() async {
    // 使用文件选择器导出
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出代码片段',
        fileName: 'code_snippets.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (path != null) {
        await _service.exportSnippets(path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('导出成功')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<void> _showImportDialog() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null && result.files.single.path != null) {
        await _service.importSnippets(result.files.single.path!);
        _refreshDisplayedSnippets();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('导入成功')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  void _deleteSnippet(CodeSnippetModel snippet) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除片段 "${snippet.title}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await _service.deleteSnippet(snippet.id);
              _refreshDisplayedSnippets();
              if (mounted) Navigator.of(ctx).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _copySnippet(CodeSnippetModel snippet) {
    _service.copyToClipboard(snippet.code);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('代码片段收藏'),
        actions: [
          IconButton(
            icon: const Icon(Icons.import_export),
            onPressed: _showImportDialog,
            tooltip: '导入片段',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _showExportDialog,
            tooltip: '导出片段',
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '搜索代码片段...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => _applyFilters(),
            ),
          ),
          // 过滤标签
          if (_service.allTags.isNotEmpty)
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  FilterChip(
                    label: const Text('全部'),
                    selected: _filterTag == null,
                    onSelected: (_) {
                      setState(() => _filterTag = null);
                      _applyFilters();
                    },
                  ),
                  const SizedBox(width: 4),
                  ..._service.allTags.map((tag) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: FilterChip(
                          label: Text(tag),
                          selected: _filterTag == tag,
                          onSelected: (_) {
                            setState(() => _filterTag = _filterTag == tag ? null : tag);
                            _applyFilters();
                          },
                        ),
                      )),
                ],
              ),
            ),
          // 语言过滤器
          if (_service.languages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Wrap(
                spacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('全部语言'),
                    selected: _filterLanguage == null,
                    onSelected: (_) {
                      setState(() => _filterLanguage = null);
                      _applyFilters();
                    },
                  ),
                  ..._service.languages.map((lang) => ChoiceChip(
                        label: Text(lang),
                        selected: _filterLanguage == lang,
                        onSelected: (_) {
                          setState(() =>
                              _filterLanguage = _filterLanguage == lang ? null : lang);
                          _applyFilters();
                        },
                      )),
                ],
              ),
            ),
          // 片段列表
          Expanded(
            child: _displayedSnippets.isEmpty
                ? const Center(
                    child: Text('暂无代码片段，点击右下角按钮添加'),
                  )
                : ListView.builder(
                    itemCount: _displayedSnippets.length,
                    itemBuilder: (context, index) {
                      final snippet = _displayedSnippets[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: ExpansionTile(
                          title: Row(
                            children: [
                              Icon(
                                Icons.code,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(snippet.title)),
                              if (snippet.language.isNotEmpty)
                                Chip(
                                  label: Text(
                                    snippet.language,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                          subtitle: Text(
                            snippet.tags.map((t) => '#$t').join(' '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.copy, size: 20),
                                onPressed: () => _copySnippet(snippet),
                                tooltip: '复制代码',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 20),
                                onPressed: () => _deleteSnippet(snippet),
                                tooltip: '删除',
                              ),
                            ],
                          ),
                          children: [
                            Container(
                              margin: const EdgeInsets.all(8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: SelectableText(
                                snippet.code,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 16,
                                bottom: 8,
                              ),
                              child: Text(
                                '创建于 ${snippet.createdAt.toString().substring(0, 19)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSnippetDialog,
        child: const Icon(Icons.add),
        tooltip: '添加代码片段',
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
