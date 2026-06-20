// OneNote 导入服务 —— 从 Microsoft OneNote 导入笔记到 DevNote
//
// 提供两种导入方式：
//
// 方式一：通过 Microsoft Graph API 导入（需要用户 OAuth2 授权）
// - OneNoteGraphImporter 类
// - 流程：OAuth2 授权 → 获取笔记本 → 获取分区 → 获取页面 → 获取 HTML 内容 → 转换为 DevNote blocks
// - 借鉴 Microsoft Graph OneNote API 文档：
//   https://learn.microsoft.com/en-us/graph/api/resources/onenote-api-overview
//
// 方式二：通过导出的 HTML 文件导入（用户从 OneNote 导出为 HTML）
// - OneNoteHtmlImporter 类
// - 流程：扫描目录 → 解析 HTML → 提取图片 → 转换为 DevNote blocks → 创建笔记
// - 借鉴 OneNote HTML 导出格式：
//   https://support.microsoft.com/en-us/office/export-and-import-onenote-notebooks

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'package:devnote/core/persistence/note_repository.dart';
import 'package:devnote/core/persistence/folder_repository.dart';
import 'package:devnote/core/persistence/models/note_model.dart';
import 'package:devnote/core/persistence/models/folder_model.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import 'package:devnote/features/editor/services/editor_service.dart';
import 'package:devnote/features/settings/import_export/onenote_html_parser.dart';
import 'package:devnote/features/settings/import_export/onenote_import_settings.dart';

// ============================================================
// 进度与结果数据类
// ============================================================

/// OneNote 导入进度
class OneNoteImportProgress {
  final int current;
  final int total;
  final String currentFile;
  final bool isComplete;

  const OneNoteImportProgress({
    this.current = 0,
    this.total = 0,
    this.currentFile = '',
    this.isComplete = false,
  });

  double get progress => total > 0 ? current / total : 0.0;
}

/// OneNote 导入结果统计
class OneNoteImportResult {
  final int successCount;
  final int failureCount;
  final List<String> failedFiles;

  const OneNoteImportResult({
    this.successCount = 0,
    this.failureCount = 0,
    this.failedFiles = const [],
  });
}

// ============================================================
// Microsoft Graph API 数据模型
// ============================================================

/// OneNote 笔记本（Graph API）
class OneNoteNotebook {
  final String id;
  final String displayName;
  final DateTime? createdDateTime;
  final DateTime? lastModifiedDateTime;

  const OneNoteNotebook({
    required this.id,
    required this.displayName,
    this.createdDateTime,
    this.lastModifiedDateTime,
  });

  factory OneNoteNotebook.fromJson(Map<String, dynamic> json) {
    return OneNoteNotebook(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      createdDateTime: json['createdDateTime'] != null
          ? DateTime.tryParse(json['createdDateTime'] as String)
          : null,
      lastModifiedDateTime: json['lastModifiedDateTime'] != null
          ? DateTime.tryParse(json['lastModifiedDateTime'] as String)
          : null,
    );
  }
}

/// OneNote 分区（Graph API）
class OneNoteSection {
  final String id;
  final String displayName;
  final String? parentNotebookId;

  const OneNoteSection({
    required this.id,
    required this.displayName,
    this.parentNotebookId,
  });

  factory OneNoteSection.fromJson(Map<String, dynamic> json) {
    return OneNoteSection(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      parentNotebookId: json['parentNotebook']?['id'] as String?,
    );
  }
}

/// OneNote 页面（Graph API）
class OneNotePageMeta {
  final String id;
  final String title;
  final String? sectionId;
  final DateTime? createdDateTime;
  final DateTime? lastModifiedDateTime;

  const OneNotePageMeta({
    required this.id,
    required this.title,
    this.sectionId,
    this.createdDateTime,
    this.lastModifiedDateTime,
  });

  factory OneNotePageMeta.fromJson(Map<String, dynamic> json) {
    return OneNotePageMeta(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled',
      sectionId: json['parentSection']?['id'] as String?,
      createdDateTime: json['createdDateTime'] != null
          ? DateTime.tryParse(json['createdDateTime'] as String)
          : null,
      lastModifiedDateTime: json['lastModifiedDateTime'] != null
          ? DateTime.tryParse(json['lastModifiedDateTime'] as String)
          : null,
    );
  }
}

// ============================================================
// OneNoteGraphImporter —— 通过 Microsoft Graph API 导入
// ============================================================

/// Microsoft Graph API 导入器
///
/// 使用 OAuth2 授权流程访问用户的 OneNote 笔记本：
/// 1. initiateAuth: 启动 OAuth2 授权，打开浏览器让用户登录
/// 2. handleAuthCallback: 处理授权回调，提取 access_token
/// 3. fetchNotebooks/fetchSections/fetchPages: 获取笔记本结构
/// 4. fetchPageContent: 获取页面 HTML 内容
/// 5. convertPageToBlocks: 将 HTML 转换为 DevNote blocks
///
/// 借鉴 Microsoft Graph OneNote API：
/// https://learn.microsoft.com/en-us/graph/api/resources/onenote-api-overview
class OneNoteGraphImporter {
  static const String _graphBaseUrl = 'https://graph.microsoft.com/v1.0/me/onenote';
  static const String _oauthBaseUrl = 'https://login.microsoftonline.com/common/oauth2/v2.0';
  static const List<String> _scopes = [
    'Notes.Read',
    'offline_access',
  ];

  final http.Client _httpClient;
  final OneNoteHtmlParser _parser;
  final _progressController = StreamController<OneNoteImportProgress>.broadcast();

  String? _accessToken;

  OneNoteGraphImporter({http.Client? httpClient, OneNoteHtmlParser? parser})
      : _httpClient = httpClient ?? http.Client(),
        _parser = parser ?? OneNoteHtmlParser();

  Stream<OneNoteImportProgress> get progressStream => _progressController.stream;

  String? get accessToken => _accessToken;

  bool get isAuthorized => _accessToken != null && _accessToken!.isNotEmpty;

  /// 启动 OAuth2 授权流程
  ///
  /// 构造授权 URL 并通过 url_launcher 打开系统浏览器，让用户登录 Microsoft 账户并授权。
  /// 授权完成后，Microsoft 会重定向到 [redirectUri] 并附带 access_token（implicit flow）
  /// 或 code（authorization code flow）。
  ///
  /// 借鉴 Microsoft identity platform OAuth2 隐式授权流程：
  /// https://learn.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-implicit-grant-flow
  Future<void> initiateAuth(String clientId, String redirectUri) async {
    final authUrl = Uri.parse('$_oauthBaseUrl/authorize').replace(queryParameters: {
      'client_id': clientId,
      'response_type': 'token',
      'redirect_uri': redirectUri,
      'scope': _scopes.join(' '),
      'response_mode': 'fragment',
    });

    if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
      throw Exception('无法打开浏览器进行 Microsoft 账户授权');
    }
  }

  /// 处理授权回调，从回调 URL 中提取 access_token
  ///
  /// 隐式授权流程中，access_token 位于 URL fragment（# 后面）。
  /// 回调 URL 格式：{redirectUri}#access_token=...&token_type=...&expires_in=...
  Future<void> handleAuthCallback(String callbackUrl) async {
    final uri = Uri.parse(callbackUrl);
    final fragment = uri.fragment;

    if (fragment.isEmpty) {
      throw Exception('授权回调 URL 中未找到 access_token');
    }

    final params = Uri.splitQueryString(fragment);
    final token = params['access_token'];
    final error = params['error'];

    if (error != null) {
      throw Exception('授权失败: $error - ${params['error_description']}');
    }

    if (token == null || token.isEmpty) {
      throw Exception('授权回调 URL 中未找到 access_token');
    }

    _accessToken = token;
  }

  /// 获取所有笔记本
  Future<List<OneNoteNotebook>> fetchNotebooks() async {
    _ensureAuthorized();
    final response = await _httpClient.get(
      Uri.parse('$_graphBaseUrl/notebooks'),
      headers: _authHeaders,
    );

    if (response.statusCode != 200) {
      throw Exception('获取笔记本列表失败: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final value = data['value'] as List? ?? [];
    return value
        .map((json) => OneNoteNotebook.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// 获取指定笔记本下的分区
  Future<List<OneNoteSection>> fetchSections(String notebookId) async {
    _ensureAuthorized();
    final response = await _httpClient.get(
      Uri.parse('$_graphBaseUrl/notebooks/$notebookId/sections'),
      headers: _authHeaders,
    );

    if (response.statusCode != 200) {
      throw Exception('获取分区列表失败: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final value = data['value'] as List? ?? [];
    return value
        .map((json) => OneNoteSection.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// 获取指定分区下的页面
  Future<List<OneNotePageMeta>> fetchPages(String sectionId) async {
    _ensureAuthorized();
    final response = await _httpClient.get(
      Uri.parse('$_graphBaseUrl/sections/$sectionId/pages'),
      headers: _authHeaders,
    );

    if (response.statusCode != 200) {
      throw Exception('获取页面列表失败: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final value = data['value'] as List? ?? [];
    return value
        .map((json) => OneNotePageMeta.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// 获取页面 HTML 内容
  ///
  /// Microsoft Graph API 返回的页面内容为 OneNote 特有的 HTML 格式。
  /// 参考：https://learn.microsoft.com/en-us/graph/api/page-get
  Future<String> fetchPageContent(String pageId) async {
    _ensureAuthorized();
    final response = await _httpClient.get(
      Uri.parse('$_graphBaseUrl/pages/$pageId/content'),
      headers: _authHeaders,
    );

    if (response.statusCode != 200) {
      throw Exception('获取页面内容失败: ${response.statusCode} - ${response.body}');
    }

    return response.body;
  }

  /// 将 OneNote HTML 内容转换为 DevNote blocks
  ///
  /// 使用 OneNoteHtmlParser 解析 HTML，然后将 OneNoteBlock 转换为 BlockModel。
  List<BlockModel> convertPageToBlocks(String htmlContent, {String noteId = ''}) {
    final page = _parser.parse(htmlContent);
    return _convertBlocks(page.blocks, noteId);
  }

  /// 批量导入选中的页面到 DevNote
  ///
  /// [pageIds] 要导入的页面 ID 列表
  /// [settings] 导入设置
  /// [noteRepository] 笔记仓库
  /// [folderRepository] 文件夹仓库
  /// [editorService] 编辑器服务（用于创建 blocks）
  Future<OneNoteImportResult> importPages({
    required List<OneNotePageMeta> pages,
    required OneNoteImportSettings settings,
    required NoteRepository noteRepository,
    required FolderRepository folderRepository,
    required EditorService editorService,
  }) async {
    var successCount = 0;
    var failureCount = 0;
    final failedFiles = <String>[];
    final total = pages.length;

    for (var i = 0; i < pages.length; i++) {
      final pageMeta = pages[i];
      _progressController.add(OneNoteImportProgress(
        current: i + 1,
        total: total,
        currentFile: pageMeta.title,
        isComplete: false,
      ));

      try {
        final htmlContent = await fetchPageContent(pageMeta.id);
        final page = _parser.parse(htmlContent);

        // 创建目标文件夹（保留 OneNote 结构时按笔记本/分区创建文件夹）
        String folderId = settings.targetFolderId;
        if (settings.preserveOriginalStructure && pageMeta.sectionId != null) {
          folderId = await _ensureFolderPath(
            folderRepository,
            settings.targetFolderId,
            pageMeta.title,
          );
        }

        // 创建笔记
        final noteId = const Uuid().v4();
        final now = DateTime.now();
        final note = NoteModel(
          id: noteId,
          title: page.title,
          content: _blocksToMarkdown(page.blocks),
          folderId: folderId,
          createdAt: page.createdDateTime ?? now,
          updatedAt: page.modifiedDateTime ?? now,
        );
        await noteRepository.createNote(note);

        // 创建 blocks
        final blocks = _convertBlocks(page.blocks, noteId);
        for (var j = 0; j < blocks.length; j++) {
          await editorService.createBlock(
            noteId: noteId,
            blockType: blocks[j].blockType,
            content: blocks[j].content,
            position: j,
          );
        }

        successCount++;
      } catch (e) {
        failureCount++;
        failedFiles.add(pageMeta.title);
      }
    }

    _progressController.add(OneNoteImportProgress(
      current: total,
      total: total,
      currentFile: '',
      isComplete: true,
    ));

    return OneNoteImportResult(
      successCount: successCount,
      failureCount: failureCount,
      failedFiles: failedFiles,
    );
  }

  void _ensureAuthorized() {
    if (!isAuthorized) {
      throw Exception('尚未完成 Microsoft 账户授权，请先调用 initiateAuth');
    }
  }

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer $_accessToken',
        'Accept': 'application/json',
      };

  /// 确保文件夹路径存在，返回最终文件夹 ID
  Future<String> _ensureFolderPath(
    FolderRepository folderRepository,
    String parentFolderId,
    String folderName,
  ) async {
    final subFolders = await folderRepository.listFolders(
      parentFolderId.isEmpty ? null : parentFolderId,
    );
    final existing = subFolders.where((f) => f.name == folderName).toList();

    if (existing.isNotEmpty) {
      return existing.first.id;
    }

    final now = DateTime.now();
    final folder = FolderModel(
      id: const Uuid().v4(),
      name: folderName,
      parentId: parentFolderId.isEmpty ? null : parentFolderId,
      createdAt: now,
      updatedAt: now,
    );
    await folderRepository.createFolder(folder);
    return folder.id;
  }

  void dispose() {
    _progressController.close();
    _httpClient.close();
  }
}

// ============================================================
// OneNoteHtmlImporter —— 通过导出的 HTML 文件导入
// ============================================================

/// HTML 文件导入器
///
/// 扫描用户从 OneNote 导出的 HTML 文件目录，解析每个文件并转换为 DevNote 笔记。
/// 支持 OneNote 导出的标准 HTML 格式，包括：
/// - 页面标题（<title> 或 <h1>）
/// - 内容块（<div data-id="...">）
/// - 图片（<img data-src="...">）
/// - 表格、列表、代码块、引用等
class OneNoteHtmlImporter {
  final NoteRepository _noteRepository;
  final FolderRepository _folderRepository;
  final EditorService _editorService;
  final OneNoteHtmlParser _parser;
  final _progressController = StreamController<OneNoteImportProgress>.broadcast();
  final _uuid = const Uuid();

  OneNoteHtmlImporter({
    required NoteRepository noteRepository,
    required FolderRepository folderRepository,
    EditorService? editorService,
    OneNoteHtmlParser? parser,
  })  : _noteRepository = noteRepository,
        _folderRepository = folderRepository,
        _editorService = editorService ?? EditorService(),
        _parser = parser ?? OneNoteHtmlParser();

  Stream<OneNoteImportProgress> get progressStream => _progressController.stream;

  /// 扫描目录下的所有 .html 文件
  Future<List<File>> importFromDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final htmlFiles = <File>[];
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.html')) {
          htmlFiles.add(entity);
        }
      }
    } catch (_) {
      // 权限不足等异常，返回已收集的文件
    }
    return htmlFiles;
  }

  /// 解析单个 HTML 文件，返回 OneNotePage 对象
  Future<OneNotePage> parseHtmlFile(String filePath) async {
    final file = File(filePath);
    final html = await file.readAsString();
    return _parser.parse(html);
  }

  /// 将 HTML 字符串转换为 DevNote blocks
  List<BlockModel> convertHtmlToBlocks(String html, {String noteId = ''}) {
    final page = _parser.parse(html);
    return _convertBlocks(page.blocks, noteId);
  }

  /// 提取 HTML 中的图片并复制到媒体目录
  ///
  /// [html] HTML 内容
  /// [basePath] HTML 文件所在目录（用于解析相对路径）
  /// 返回图片在新媒体目录中的路径列表
  Future<List<String>> extractImages(String html, String basePath) async {
    final page = _parser.parse(html);
    final mediaDir = await _getMediaDirectory();
    final copiedPaths = <String>[];

    for (final image in page.images) {
      if (image.isTagIcon) continue; // 跳过 OneNote 标签图标

      final sourcePath = _resolveImagePath(image.src, basePath);
      if (sourcePath == null) continue;

      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) continue;

      // 生成唯一文件名，避免冲突
      final ext = p.extension(sourcePath);
      final newFileName = '${_uuid.v4()}$ext';
      final destPath = p.join(mediaDir.path, newFileName);

      try {
        await sourceFile.copy(destPath);
        copiedPaths.add(destPath);
      } catch (_) {
        // 复制失败跳过
      }
    }

    return copiedPaths;
  }

  /// 提取页面元数据（标题、创建时间、修改时间）
  Map<String, dynamic> preserveMetadata(String html) {
    final page = _parser.parse(html);
    return {
      'title': page.title,
      'createdDateTime': page.createdDateTime?.toIso8601String(),
      'modifiedDateTime': page.modifiedDateTime?.toIso8601String(),
      'metadata': page.metadata,
    };
  }

  /// 批量导入 HTML 文件到 DevNote
  ///
  /// [filePaths] 要导入的 HTML 文件路径列表
  /// [settings] 导入设置
  Future<OneNoteImportResult> importFiles({
    required List<String> filePaths,
    required OneNoteImportSettings settings,
  }) async {
    var successCount = 0;
    var failureCount = 0;
    final failedFiles = <String>[];
    final total = filePaths.length;

    for (var i = 0; i < filePaths.length; i++) {
      final filePath = filePaths[i];
      final fileName = p.basename(filePath);

      _progressController.add(OneNoteImportProgress(
        current: i + 1,
        total: total,
        currentFile: fileName,
        isComplete: false,
      ));

      try {
        await _importSingleFile(filePath, settings);
        successCount++;
      } catch (e) {
        failureCount++;
        failedFiles.add(fileName);
      }
    }

    _progressController.add(OneNoteImportProgress(
      current: total,
      total: total,
      currentFile: '',
      isComplete: true,
    ));

    return OneNoteImportResult(
      successCount: successCount,
      failureCount: failureCount,
      failedFiles: failedFiles,
    );
  }

  /// 导入单个 HTML 文件
  Future<String> _importSingleFile(
    String filePath,
    OneNoteImportSettings settings,
  ) async {
    final file = File(filePath);
    final html = await file.readAsString();
    final page = _parser.parse(html);

    // 提取并复制图片
    if (settings.importImages) {
      final basePath = file.parent.path;
      await extractImages(html, basePath);
    }

    // 创建目标文件夹（保留原始结构时按文件名创建子文件夹）
    String folderId = settings.targetFolderId;
    if (settings.preserveOriginalStructure) {
      folderId = await _ensureFolderPath(
        settings.targetFolderId,
        p.basenameWithoutExtension(filePath),
      );
    }

    // 创建笔记
    final noteId = _uuid.v4();
    final now = DateTime.now();
    final note = NoteModel(
      id: noteId,
      title: page.title,
      content: _blocksToMarkdown(page.blocks),
      folderId: folderId,
      createdAt: page.createdDateTime ?? now,
      updatedAt: page.modifiedDateTime ?? now,
    );
    await _noteRepository.createNote(note);

    // 创建 blocks
    final blocks = _convertBlocks(page.blocks, noteId);
    for (var j = 0; j < blocks.length; j++) {
      await _editorService.createBlock(
        noteId: noteId,
        blockType: blocks[j].blockType,
        content: blocks[j].content,
        position: j,
      );
    }

    return noteId;
  }

  /// 确保文件夹路径存在
  Future<String> _ensureFolderPath(
    String parentFolderId,
    String folderName,
  ) async {
    final subFolders = await _folderRepository.listFolders(
      parentFolderId.isEmpty ? null : parentFolderId,
    );
    final existing = subFolders.where((f) => f.name == folderName).toList();

    if (existing.isNotEmpty) {
      return existing.first.id;
    }

    final now = DateTime.now();
    final folder = FolderModel(
      id: _uuid.v4(),
      name: folderName,
      parentId: parentFolderId.isEmpty ? null : parentFolderId,
      createdAt: now,
      updatedAt: now,
    );
    await _folderRepository.createFolder(folder);
    return folder.id;
  }

  /// 获取媒体存储目录
  Future<Directory> _getMediaDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(appDir.path, 'media', 'onenote_import'));
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir;
  }

  /// 解析图片路径（支持相对路径和绝对路径）
  String? _resolveImagePath(String src, String basePath) {
    if (src.isEmpty) return null;

    // 跳过 data URI 和网络图片
    if (src.startsWith('data:') || src.startsWith('http://') || src.startsWith('https://')) {
      return null;
    }

    // 绝对路径直接返回
    if (p.isAbsolute(src)) return src;

    // 相对路径基于 basePath 解析
    return p.join(basePath, src);
  }

  void dispose() {
    _progressController.close();
  }
}

// ============================================================
// 共享转换辅助函数
// ============================================================

/// 将 OneNoteBlock 列表转换为 DevNote BlockModel 列表
List<BlockModel> _convertBlocks(List<OneNoteBlock> blocks, String noteId) {
  final result = <BlockModel>[];
  final now = DateTime.now();
  const uuid = Uuid();

  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    final blockType = _mapBlockType(block.type);
    final content = _buildBlockContent(block);

    result.add(BlockModel(
      id: uuid.v4(),
      noteId: noteId,
      blockType: blockType,
      content: content,
      position: i,
      language: block.language,
      createdAt: now,
      updatedAt: now,
    ));
  }

  return result;
}

/// OneNoteBlockType 映射到 DevNote BlockType
BlockType _mapBlockType(OneNoteBlockType type) {
  switch (type) {
    case OneNoteBlockType.paragraph:
      return BlockType.paragraph;
    case OneNoteBlockType.heading:
      // heading 级别在 content 中处理，这里统一用 heading1
      // 实际级别通过 BlockType.heading1-6 区分
      return BlockType.heading1;
    case OneNoteBlockType.image:
      return BlockType.image;
    case OneNoteBlockType.table:
      return BlockType.tableBlock;
    case OneNoteBlockType.unorderedList:
      return BlockType.list;
    case OneNoteBlockType.orderedList:
      return BlockType.orderedList;
    case OneNoteBlockType.code:
      return BlockType.codeBlock;
    case OneNoteBlockType.quote:
      return BlockType.quote;
    case OneNoteBlockType.taskList:
      return BlockType.taskListBlock;
    case OneNoteBlockType.divider:
      return BlockType.paragraph;
  }
}

/// 根据块类型构建内容字符串
String _buildBlockContent(OneNoteBlock block) {
  switch (block.type) {
    case OneNoteBlockType.heading:
      final level = block.headingLevel ?? 1;
      final prefix = '#' * level.clamp(1, 6);
      return '$prefix ${block.content}';
    case OneNoteBlockType.unorderedList:
      return block.listItems.map((item) => '- $item').join('\n');
    case OneNoteBlockType.orderedList:
      var index = 1;
      return block.listItems.map((item) => '${index++}. $item').join('\n');
    case OneNoteBlockType.taskList:
      return block.listItems.map((item) {
        if (item.startsWith('[x]')) {
          return '- [x] ${item.substring(3).trim()}';
        } else if (item.startsWith('[ ]')) {
          return '- [ ] ${item.substring(3).trim()}';
        }
        return '- $item';
      }).join('\n');
    case OneNoteBlockType.table:
      return _tableToMarkdown(block.tableRows, block.tableHasHeader);
    case OneNoteBlockType.image:
      return block.image != null ? '![${block.image!.alt}](${block.image!.src})' : '';
    case OneNoteBlockType.code:
      return block.content;
    case OneNoteBlockType.quote:
      return block.content;
    case OneNoteBlockType.divider:
      return '---';
    case OneNoteBlockType.paragraph:
      return block.content;
  }
}

/// 表格转换为 Markdown 格式
String _tableToMarkdown(List<List<String>> rows, bool hasHeader) {
  if (rows.isEmpty) return '';

  final buffer = StringBuffer();
  final maxCols = rows.fold<int>(0, (max, row) => row.length > max ? row.length : max);

  // 表头
  if (hasHeader && rows.isNotEmpty) {
    final header = rows.first;
    buffer.write('| ');
    buffer.write(header.asMap().entries.map((e) {
      return e.value.isEmpty ? ' ' : e.value;
    }).take(maxCols).join(' | '));
    buffer.writeln(' |');
    // 分隔行
    buffer.writeln('| ${List.filled(maxCols, '---').join(' | ')} |');
    // 表体
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      buffer.write('| ');
      buffer.write(List.generate(maxCols, (idx) {
        return idx < row.length && row[idx].isNotEmpty ? row[idx] : ' ';
      }).join(' | '));
      buffer.writeln(' |');
    }
  } else {
    // 无表头，所有行作为普通行
    for (final row in rows) {
      buffer.write('| ');
      buffer.write(List.generate(maxCols, (idx) {
        return idx < row.length && row[idx].isNotEmpty ? row[idx] : ' ';
      }).join(' | '));
      buffer.writeln(' |');
    }
  }

  return buffer.toString().trimRight();
}

/// 将 OneNoteBlock 列表转换为 Markdown 文本（用于 NoteModel.content 字段）
String _blocksToMarkdown(List<OneNoteBlock> blocks) {
  return blocks.map(_buildBlockContent).where((s) => s.isNotEmpty).join('\n\n');
}
