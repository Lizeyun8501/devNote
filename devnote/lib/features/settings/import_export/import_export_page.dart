import 'package:flutter/material.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/core/persistence/folder_repository.dart';
import 'package:devnote/core/persistence/note_repository.dart';
import 'package:devnote/core/persistence/tag_repository.dart';
import 'package:devnote/features/settings/import_export/import_service.dart';
import 'package:devnote/features/settings/import_export/export_service.dart';
import 'package:devnote/features/settings/import_export/widgets/import_progress_dialog.dart';
import 'package:devnote/features/settings/import_export/widgets/export_progress_dialog.dart';

/// 导入导出页面
///
/// 导入流程说明:
/// 1. 选择导入来源 (Markdown文件夹 / Obsidian Vault / Joplin 导出)
/// 2. 设置冲突处理策略 (跳过/覆盖/重命名)
/// 3. 选择目标文件夹
/// 4. 开始导入: 递归扫描 .md 文件 → 解析 frontmatter → 创建笔记和标签
///    借鉴: Joplin 导入流程 (https://joplinapp.org/help/apps/import_export/)
///
/// 导出流程说明:
/// 1. 选择导出范围 (全部笔记/指定文件夹/指定标签)
/// 2. 选择导出格式 (Markdown/HTML/PDF)
/// 3. 选择目标路径
/// 4. 开始导出: 收集笔记 → 按文件夹结构写入 → 生成 frontmatter
///    借鉴: Obsidian 导出格式 (https://help.obsidian.md/)

/// 导出历史记录条目
/// 记录每次导出操作的元信息，用于追溯和重复导出
class ExportHistoryEntry {
  final DateTime timestamp;
  final String format;
  final String range;
  final int noteCount;
  final String? targetPath;

  const ExportHistoryEntry({
    required this.timestamp,
    required this.format,
    required this.range,
    required this.noteCount,
    this.targetPath,
  });

  /// 格式的显示名称
  String get formatLabel {
    switch (format) {
      case 'markdown':
        return 'Markdown';
      case 'html':
        return 'HTML';
      case 'pdf':
        return 'PDF';
      default:
        return format;
    }
  }

  /// 范围的显示名称
  String get rangeLabel {
    switch (range) {
      case 'all':
        return '全部笔记';
      case 'folder':
        return '指定文件夹';
      case 'tag':
        return '指定标签';
      default:
        return range;
    }
  }
}

class ImportExportPage extends StatefulWidget {
  const ImportExportPage({super.key});

  @override
  State<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends State<ImportExportPage> {
  ImportSource _importSource = ImportSource.markdownFolder;
  ConflictResolution _conflictResolution = ConflictResolution.skip;
  ExportRange _exportRange = ExportRange.all;
  ExportFormat _exportFormat = ExportFormat.markdown;

  late final ImportService _importService;
  late final ExportService _exportService;

  /// 导出历史记录列表
  /// 数据来源: 每次成功导出后自动记录
  final List<ExportHistoryEntry> _exportHistory = [];

  /// 导入进度状态
  double _importProgress = 0.0;
  String _importCurrentFile = '';
  bool _isImporting = false;

  /// 导出进度状态
  double _exportProgress = 0.0;
  String _exportCurrentFile = '';
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    final dbHelper = DatabaseHelper();
    _importService = ImportService(
      noteRepository: SqliteNoteRepository(dbHelper),
      folderRepository: SqliteFolderRepository(dbHelper),
      tagRepository: SqliteTagRepository(dbHelper),
    );
    _exportService = ExportService(
      noteRepository: SqliteNoteRepository(dbHelper),
      folderRepository: SqliteFolderRepository(dbHelper),
      tagRepository: SqliteTagRepository(dbHelper),
    );

    // 监听导入进度流，更新页面状态
    _importService.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _importProgress = progress.progress;
          _importCurrentFile = progress.currentFile;
          _isImporting = !progress.isComplete;
        });
      }
    });

    // 监听导出进度流，更新页面状态
    _exportService.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _exportProgress = progress.progress;
          _exportCurrentFile = progress.currentFile;
          _isExporting = !progress.isComplete;
        });
      }
    });
  }

  @override
  void dispose() {
    _importService.dispose();
    _exportService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入导出'),
      ),
      body: ListView(
        children: [
          _buildImportSection(),
          const Divider(),
          _buildExportSection(),
          const Divider(),
          _buildExportHistorySection(),
        ],
      ),
    );
  }

  /// 构建导入区域
  /// 导入来源说明:
  /// - Markdown 文件夹: 标准 .md 文件，仅解析基本标题和内容
  /// - Obsidian Vault: 额外解析 [[wikilink]] 和 YAML Properties
  /// - Joplin 导出: 解析 Joplin 特有的 metadata 字段
  Widget _buildImportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            '导入',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        RadioListTile<ImportSource>(
          title: const Text('Markdown 文件夹'),
          subtitle: const Text('标准 .md 文件导入'),
          value: ImportSource.markdownFolder,
          groupValue: _importSource,
          onChanged: _isImporting ? null : (value) {
            setState(() {
              _importSource = value!;
            });
          },
        ),
        RadioListTile<ImportSource>(
          title: const Text('Obsidian Vault'),
          subtitle: const Text('支持 [[wikilink]] 和 Properties'),
          value: ImportSource.obsidianVault,
          groupValue: _importSource,
          onChanged: _isImporting ? null : (value) {
            setState(() {
              _importSource = value!;
            });
          },
        ),
        RadioListTile<ImportSource>(
          title: const Text('Joplin 导出'),
          subtitle: const Text('解析 Joplin metadata 字段'),
          value: ImportSource.joplinExport,
          groupValue: _importSource,
          onChanged: _isImporting ? null : (value) {
            setState(() {
              _importSource = value!;
            });
          },
        ),
        ListTile(
          title: const Text('冲突处理'),
          subtitle: Text(_conflictResolutionLabel),
          trailing: const Icon(Icons.chevron_right),
          onTap: _isImporting ? null : _showConflictResolutionDialog,
        ),
        // 导入进度指示器
        if (_isImporting) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _importProgress,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _importCurrentFile.isNotEmpty ? '正在导入: $_importCurrentFile' : '准备中...',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '${(_importProgress * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isImporting ? null : _startImport,
              icon: _isImporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download),
              label: Text(_isImporting ? '导入中...' : '开始导入'),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建导出区域
  /// 导出格式说明:
  /// - Markdown: 包含 YAML frontmatter，保留笔记结构，适合导入 Obsidian/Typora
  /// - HTML: 单文件，包含样式，适合浏览器查看和分享
  /// - PDF: 通过 HTML 转换，适合打印和归档 (需要 pdf_export_service)
  Widget _buildExportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            '导出',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        // 导出范围选择
        RadioListTile<ExportRange>(
          title: const Text('全部笔记'),
          subtitle: const Text('导出所有文件夹中的笔记'),
          value: ExportRange.all,
          groupValue: _exportRange,
          onChanged: _isExporting ? null : (value) {
            setState(() {
              _exportRange = value!;
            });
          },
        ),
        RadioListTile<ExportRange>(
          title: const Text('指定文件夹'),
          subtitle: const Text('仅导出所选文件夹及其子文件夹'),
          value: ExportRange.folder,
          groupValue: _exportRange,
          onChanged: _isExporting ? null : (value) {
            setState(() {
              _exportRange = value!;
            });
          },
        ),
        RadioListTile<ExportRange>(
          title: const Text('指定标签'),
          subtitle: const Text('仅导出带有特定标签的笔记'),
          value: ExportRange.tag,
          groupValue: _exportRange,
          onChanged: _isExporting ? null : (value) {
            setState(() {
              _exportRange = value!;
            });
          },
        ),
        const SizedBox(height: 8),
        // 导出格式选择
        // 借鉴 Joplin 的多格式导出设计
        // 来源: https://joplinapp.org/help/apps/import_export/
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '导出格式',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        RadioListTile<ExportFormat>(
          title: const Text('Markdown'),
          subtitle: const Text('包含 frontmatter 元数据，适合进一步编辑'),
          value: ExportFormat.markdown,
          groupValue: _exportFormat,
          onChanged: _isExporting ? null : (value) {
            setState(() {
              _exportFormat = value!;
            });
          },
        ),
        RadioListTile<ExportFormat>(
          title: const Text('HTML'),
          subtitle: const Text('单文件，浏览器可直接查看'),
          value: ExportFormat.html,
          groupValue: _exportFormat,
          onChanged: _isExporting ? null : (value) {
            setState(() {
              _exportFormat = value!;
            });
          },
        ),
        RadioListTile<ExportFormat>(
          title: const Text('PDF'),
          subtitle: const Text('适合打印和归档，通过 HTML 转换'),
          value: ExportFormat.pdf,
          groupValue: _exportFormat,
          onChanged: _isExporting ? null : (value) {
            setState(() {
              _exportFormat = value!;
            });
          },
        ),
        // 导出进度指示器
        if (_isExporting) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _exportProgress,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _exportCurrentFile.isNotEmpty ? '正在导出: $_exportCurrentFile' : '准备中...',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '${(_exportProgress * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isExporting ? null : _startExport,
              icon: _isExporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_upload),
              label: Text(_isExporting ? '导出中...' : '开始导出'),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建导出历史记录区域
  /// 记录每次导出操作的时间、格式、范围、笔记数量
  Widget _buildExportHistorySection() {
    if (_exportHistory.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              '导出历史',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Center(
              child: Text(
                '暂无导出记录',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '导出历史',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _exportHistory.clear();
                  });
                },
                child: const Text('清空'),
              ),
            ],
          ),
        ),
        ..._exportHistory.map((entry) => ListTile(
              leading: _exportFormatIcon(entry.format),
              title: Text('${entry.formatLabel} 格式导出'),
              subtitle: Text(
                '${entry.rangeLabel} · ${entry.noteCount} 篇笔记 · ${_formatDateTime(entry.timestamp)}',
              ),
              trailing: const Icon(Icons.chevron_right, size: 16),
              dense: true,
              onTap: () {
                // 可扩展：点击查看详情或重新导出
              },
            )),
      ],
    );
  }

  /// 根据格式返回对应的图标
  Widget _exportFormatIcon(String format) {
    switch (format) {
      case 'markdown':
        return const Icon(Icons.description, color: Colors.blueGrey);
      case 'html':
        return const Icon(Icons.html, color: Colors.orange);
      case 'pdf':
        return const Icon(Icons.picture_as_pdf, color: Colors.red);
      default:
        return const Icon(Icons.insert_drive_file);
    }
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String get _conflictResolutionLabel {
    switch (_conflictResolution) {
      case ConflictResolution.skip:
        return '跳过';
      case ConflictResolution.overwrite:
        return '覆盖';
      case ConflictResolution.rename:
        return '重命名';
    }
  }

  void _showConflictResolutionDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('冲突处理方式'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              setState(() {
                _conflictResolution = ConflictResolution.skip;
              });
              Navigator.pop(dialogContext);
            },
            child: const Text('跳过'),
          ),
          SimpleDialogOption(
            onPressed: () {
              setState(() {
                _conflictResolution = ConflictResolution.overwrite;
              });
              Navigator.pop(dialogContext);
            },
            child: const Text('覆盖'),
          ),
          SimpleDialogOption(
            onPressed: () {
              setState(() {
                _conflictResolution = ConflictResolution.rename;
              });
              Navigator.pop(dialogContext);
            },
            child: const Text('重命名'),
          ),
        ],
      ),
    );
  }

  Future<void> _startImport() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ImportProgressDialog(
        importService: _importService,
      ),
    );

    await _importService.import(
      source: _importSource,
      sourcePath: '',
      targetFolderId: '',
      conflictResolution: _conflictResolution,
    );

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _startExport() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ExportProgressDialog(
        exportService: _exportService,
      ),
    );

    // 记录导出操作开始时间
    final startTime = DateTime.now();

    await _exportService.export(
      range: _exportRange,
      format: _exportFormat,
      targetPath: '',
    );

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();

      // 记录导出历史
      setState(() {
        _exportHistory.insert(
          0,
          ExportHistoryEntry(
            timestamp: startTime,
            format: _exportFormat.name,
            range: _exportRange.name,
            noteCount: 0, // 实际应通过 exportService 获取准确数量
            targetPath: '',
          ),
        );
      });
    }
  }
}
