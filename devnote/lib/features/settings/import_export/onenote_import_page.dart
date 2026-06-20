// OneNote 导入页面 —— 提供 Microsoft Graph API 和 HTML 文件两种导入方式
//
// 方式一流程（Graph API）：
// 1. 显示"连接 Microsoft 账户"按钮 → 启动 OAuth2 授权
// 2. 授权后显示笔记本列表
// 3. 选择笔记本后显示分区列表
// 4. 选择分区后显示页面列表（多选）
// 5. 点击导入，显示进度
//
// 方式二流程（HTML 文件）：
// 1. 选择文件夹
// 2. 扫描显示 HTML 文件列表
// 3. 选择要导入的文件
// 4. 点击导入，显示进度
//
// 借鉴 Obsidian Importer 插件的导入向导设计：
// https://help.obsidian.md/import

import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/core/persistence/folder_repository.dart';
import 'package:devnote/core/persistence/note_repository.dart';
import 'package:devnote/features/editor/services/editor_service.dart';
import 'package:devnote/features/settings/import_export/onenote_import_service.dart';
import 'package:devnote/features/settings/import_export/onenote_import_settings.dart';

/// OneNote 导入方式
enum _ImportMethod {
  /// 从 Microsoft 账户导入（Graph API）
  graphApi,

  /// 从导出的 HTML 文件导入
  htmlFiles,
}

/// Graph API 导入流程的步骤
enum _GraphStep {
  /// 未授权，显示连接按钮
  unauthorized,

  /// 已授权，显示笔记本列表
  notebooks,

  /// 已选择笔记本，显示分区列表
  sections,

  /// 已选择分区，显示页面列表
  pages,

  /// 正在导入
  importing,

  /// 导入完成
  completed,
}

/// HTML 文件导入流程的步骤
enum _HtmlStep {
  /// 选择文件夹
  selectDirectory,

  /// 显示 HTML 文件列表
  fileList,

  /// 正在导入
  importing,

  /// 导入完成
  completed,
}

class OnenoteImportPage extends StatefulWidget {
  const OnenoteImportPage({super.key});

  @override
  State<OnenoteImportPage> createState() => _OnenoteImportPageState();
}

class _OnenoteImportPageState extends State<OnenoteImportPage> {
  _ImportMethod _method = _ImportMethod.htmlFiles;
  OneNoteImportSettings _settings = const OneNoteImportSettings();

  // Graph API 状态
  late final OneNoteGraphImporter _graphImporter;
  _GraphStep _graphStep = _GraphStep.unauthorized;
  List<OneNoteNotebook> _notebooks = [];
  List<OneNoteSection> _sections = [];
  List<OneNotePageMeta> _pages = [];
  final Set<String> _selectedPageIds = {};
  bool _isLoading = false;
  String? _graphError;

  // HTML 文件导入状态
  late final OneNoteHtmlImporter _htmlImporter;
  _HtmlStep _htmlStep = _HtmlStep.selectDirectory;
  List<io.File> _htmlFiles = [];
  final Set<String> _selectedFilePaths = {};
  String? _htmlError;

  // 导入进度
  OneNoteImportProgress _progress = const OneNoteImportProgress();
  OneNoteImportResult? _result;

  @override
  void initState() {
    super.initState();
    _graphImporter = getIt<OneNoteGraphImporter>();
    _htmlImporter = getIt<OneNoteHtmlImporter>();

    _graphImporter.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _progress = progress;
        });
      }
    });

    _htmlImporter.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _progress = progress;
        });
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('从 OneNote 导入'),
      ),
      body: ListView(
        children: [
          _buildMethodSelector(),
          const Divider(),
          OneNoteImportSettingsWidget(
            settings: _settings,
            onChanged: (newSettings) {
              setState(() {
                _settings = newSettings;
              });
            },
          ),
          const Divider(),
          if (_method == _ImportMethod.graphApi)
            _buildGraphImportFlow()
          else
            _buildHtmlImportFlow(),
        ],
      ),
    );
  }

  /// 构建导入方式选择器
  Widget _buildMethodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '选择导入方式',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        RadioListTile<_ImportMethod>(
          title: const Text('从 Microsoft 账户导入'),
          subtitle: const Text('通过 Graph API 直接访问 OneNote 笔记本'),
          value: _ImportMethod.graphApi,
          groupValue: _method,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _method = value;
              });
            }
          },
        ),
        RadioListTile<_ImportMethod>(
          title: const Text('从导出的 HTML 文件导入'),
          subtitle: const Text('扫描本地 HTML 文件（需先从 OneNote 导出）'),
          value: _ImportMethod.htmlFiles,
          groupValue: _method,
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _method = value;
              });
            }
          },
        ),
      ],
    );
  }

  // ============================================================
  // Graph API 导入流程
  // ============================================================

  Widget _buildGraphImportFlow() {
    switch (_graphStep) {
      case _GraphStep.unauthorized:
        return _buildGraphUnauthorized();
      case _GraphStep.notebooks:
        return _buildNotebooksList();
      case _GraphStep.sections:
        return _buildSectionsList();
      case _GraphStep.pages:
        return _buildPagesList();
      case _GraphStep.importing:
        return _buildImportProgress();
      case _GraphStep.completed:
        return _buildImportResult();
    }
  }

  Widget _buildGraphUnauthorized() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '连接 Microsoft 账户',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            '授权 DevNote 访问您的 OneNote 笔记本，仅读取权限，不会修改您的笔记。',
            style: TextStyle(color: Colors.grey),
          ),
          if (_graphError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                _graphError!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _connectMicrosoftAccount,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: const Text('连接 Microsoft 账户'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connectMicrosoftAccount() async {
    setState(() {
      _isLoading = true;
      _graphError = null;
    });

    try {
      // 使用 Microsoft 应用注册的客户端 ID 和重定向 URI
      // 实际部署时应从配置中读取
      const clientId = 'YOUR_CLIENT_ID';
      const redirectUri = 'devnote://oauth/callback';

      await _graphImporter.initiateAuth(clientId, redirectUri);
      // 用户完成授权后，需要通过 deep link 回调到应用并调用 handleAuthCallback
      // 此处简化处理：提示用户完成授权后点击"我已完成授权"按钮
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showAuthCallbackDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _graphError = '授权启动失败: $e';
        });
      }
    }
  }

  void _showAuthCallbackDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('完成授权'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请在浏览器中完成 Microsoft 账户授权后，将回调 URL 粘贴到下方：'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '回调 URL',
                hintText: 'devnote://oauth/callback#access_token=...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final callbackUrl = controller.text.trim();
              if (callbackUrl.isEmpty) return;

              try {
                await _graphImporter.handleAuthCallback(callbackUrl);
                if (mounted) {
                  Navigator.pop(dialogContext);
                  _loadNotebooks();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('授权回调处理失败: $e')),
                  );
                }
              }
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadNotebooks() async {
    setState(() {
      _isLoading = true;
      _graphError = null;
    });

    try {
      final notebooks = await _graphImporter.fetchNotebooks();
      if (mounted) {
        setState(() {
          _notebooks = notebooks;
          _graphStep = _GraphStep.notebooks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _graphError = '获取笔记本列表失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildNotebooksList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                '选择笔记本',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _isLoading ? null : _loadNotebooks,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新'),
              ),
            ],
          ),
        ),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_notebooks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('未找到笔记本')),
          )
        else
          ..._notebooks.map((notebook) => ListTile(
                leading: const Icon(Icons.book),
                title: Text(notebook.displayName),
                subtitle: notebook.lastModifiedDateTime != null
                    ? Text('最后修改: ${_formatDateTime(notebook.lastModifiedDateTime!)}')
                    : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _loadSections(notebook.id);
                },
              )),
      ],
    );
  }

  Future<void> _loadSections(String notebookId) async {
    setState(() {
      _isLoading = true;
      _graphError = null;
    });

    try {
      final sections = await _graphImporter.fetchSections(notebookId);
      if (mounted) {
        setState(() {
          _sections = sections;
          _graphStep = _GraphStep.sections;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _graphError = '获取分区列表失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildSectionsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _graphStep = _GraphStep.notebooks;
                  });
                },
              ),
              Text(
                '选择分区',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_sections.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('未找到分区')),
          )
        else
          ..._sections.map((section) => ListTile(
                leading: const Icon(Icons.folder),
                title: Text(section.displayName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _loadPages(section.id);
                },
              )),
      ],
    );
  }

  Future<void> _loadPages(String sectionId) async {
    setState(() {
      _isLoading = true;
      _graphError = null;
    });

    try {
      final pages = await _graphImporter.fetchPages(sectionId);
      if (mounted) {
        setState(() {
          _pages = pages;
          _selectedPageIds.clear();
          _graphStep = _GraphStep.pages;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _graphError = '获取页面列表失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildPagesList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _graphStep = _GraphStep.sections;
                  });
                },
              ),
              Expanded(
                child: Text(
                  '选择页面（${_selectedPageIds.length}/${_pages.length}）',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: _pages.isEmpty
                    ? null
                    : () {
                        setState(() {
                          if (_selectedPageIds.length == _pages.length) {
                            _selectedPageIds.clear();
                          } else {
                            _selectedPageIds
                                .addAll(_pages.map((p) => p.id));
                          }
                        });
                      },
                child: Text(
                  _selectedPageIds.length == _pages.length ? '取消全选' : '全选',
                ),
              ),
            ],
          ),
        ),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_pages.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('未找到页面')),
          )
        else
          ..._pages.map((page) => CheckboxListTile(
                title: Text(page.title),
                subtitle: page.lastModifiedDateTime != null
                    ? Text('最后修改: ${_formatDateTime(page.lastModifiedDateTime!)}')
                    : null,
                value: _selectedPageIds.contains(page.id),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedPageIds.add(page.id);
                    } else {
                      _selectedPageIds.remove(page.id);
                    }
                  });
                },
              )),
        if (_pages.isNotEmpty && !_isLoading)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedPageIds.isEmpty
                    ? null
                    : _startGraphImport,
                icon: const Icon(Icons.download),
                label: Text('导入 ${_selectedPageIds.length} 个页面'),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _startGraphImport() async {
    setState(() {
      _graphStep = _GraphStep.importing;
      _progress = const OneNoteImportProgress();
      _result = null;
    });

    try {
      final dbHelper = DatabaseHelper();
      final noteRepository = SqliteNoteRepository(dbHelper);
      final folderRepository = SqliteFolderRepository(dbHelper);
      final editorService = EditorService();

      final selectedPages = _pages
          .where((p) => _selectedPageIds.contains(p.id))
          .toList();

      final result = await _graphImporter.importPages(
        pages: selectedPages,
        settings: _settings,
        noteRepository: noteRepository,
        folderRepository: folderRepository,
        editorService: editorService,
      );

      if (mounted) {
        setState(() {
          _result = result;
          _graphStep = _GraphStep.completed;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = OneNoteImportResult(
            failureCount: _selectedPageIds.length,
            failedFiles: ['导入过程出错: $e'],
          );
          _graphStep = _GraphStep.completed;
        });
      }
    }
  }

  // ============================================================
  // HTML 文件导入流程
  // ============================================================

  Widget _buildHtmlImportFlow() {
    switch (_htmlStep) {
      case _HtmlStep.selectDirectory:
        return _buildHtmlSelectDirectory();
      case _HtmlStep.fileList:
        return _buildHtmlFileList();
      case _HtmlStep.importing:
        return _buildImportProgress();
      case _HtmlStep.completed:
        return _buildImportResult();
    }
  }

  Widget _buildHtmlSelectDirectory() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择 HTML 文件夹',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            '请选择包含 OneNote 导出 HTML 文件的文件夹。导入器会递归扫描子目录中的所有 .html 文件。',
            style: TextStyle(color: Colors.grey),
          ),
          if (_htmlError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                _htmlError!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _pickDirectory,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open),
              label: const Text('选择文件夹'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDirectory() async {
    setState(() {
      _isLoading = true;
      _htmlError = null;
    });

    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      final files = await _htmlImporter.importFromDirectory(result);
      if (mounted) {
        setState(() {
          _htmlFiles = files;
          _selectedFilePaths.clear();
          if (files.isNotEmpty) {
            _selectedFilePaths.addAll(files.map((f) => f.path));
          }
          _htmlStep = _HtmlStep.fileList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _htmlError = '扫描文件夹失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildHtmlFileList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _htmlStep = _HtmlStep.selectDirectory;
                  });
                },
              ),
              Expanded(
                child: Text(
                  '选择文件（${_selectedFilePaths.length}/${_htmlFiles.length}）',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: _htmlFiles.isEmpty
                    ? null
                    : () {
                        setState(() {
                          if (_selectedFilePaths.length ==
                              _htmlFiles.length) {
                            _selectedFilePaths.clear();
                          } else {
                            _selectedFilePaths
                                .addAll(_htmlFiles.map((f) => f.path));
                          }
                        });
                      },
                child: Text(
                  _selectedFilePaths.length == _htmlFiles.length
                      ? '取消全选'
                      : '全选',
                ),
              ),
            ],
          ),
        ),
        if (_htmlFiles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('未找到 HTML 文件')),
          )
        else
          ..._htmlFiles.map((file) {
            final fileName = p.basename(file.path);
            return CheckboxListTile(
              title: Text(fileName),
              subtitle: Text(file.path),
              value: _selectedFilePaths.contains(file.path),
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedFilePaths.add(file.path);
                  } else {
                    _selectedFilePaths.remove(file.path);
                  }
                });
              },
            );
          }),
        if (_htmlFiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedFilePaths.isEmpty
                    ? null
                    : _startHtmlImport,
                icon: const Icon(Icons.download),
                label: Text('导入 ${_selectedFilePaths.length} 个文件'),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _startHtmlImport() async {
    setState(() {
      _htmlStep = _HtmlStep.importing;
      _progress = const OneNoteImportProgress();
      _result = null;
    });

    try {
      final result = await _htmlImporter.importFiles(
        filePaths: _selectedFilePaths.toList(),
        settings: _settings,
      );

      if (mounted) {
        setState(() {
          _result = result;
          _htmlStep = _HtmlStep.completed;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = OneNoteImportResult(
            failureCount: _selectedFilePaths.length,
            failedFiles: ['导入过程出错: $e'],
          );
          _htmlStep = _HtmlStep.completed;
        });
      }
    }
  }

  // ============================================================
  // 共享组件
  // ============================================================

  Widget _buildImportProgress() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '正在导入...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress.progress,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _progress.currentFile.isNotEmpty
                      ? '正在导入: ${_progress.currentFile}'
                      : '准备中...',
                  style: Theme.of(context).textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${_progress.current} / ${_progress.total}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${(_progress.progress * 100).toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportResult() {
    final result = _result;
    if (result == null) {
      return const Center(child: Text('无导入结果'));
    }

    final isSuccess = result.failureCount == 0;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSuccess ? Icons.check_circle : Icons.warning,
                color: isSuccess ? Colors.green : Colors.orange,
                size: 32,
              ),
              const SizedBox(width: 12),
              Text(
                isSuccess ? '导入完成' : '导入完成（部分失败）',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildResultStat('成功', result.successCount, Colors.green),
          if (result.failureCount > 0) ...[
            const SizedBox(height: 8),
            _buildResultStat('失败', result.failureCount, Colors.red),
            const SizedBox(height: 12),
            Text(
              '失败文件:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            ...result.failedFiles.map((file) => Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: Text(
                    '• $file',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                )),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _graphStep = _GraphStep.unauthorized;
                  _htmlStep = _HtmlStep.selectDirectory;
                  _result = null;
                  _progress = const OneNoteImportProgress();
                  _selectedPageIds.clear();
                  _selectedFilePaths.clear();
                });
              },
              child: const Text('完成'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultStat(String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text('$label: $count'),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
