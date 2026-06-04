import 'package:flutter/material.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/core/persistence/folder_repository.dart';
import 'package:devnote/core/persistence/note_repository.dart';
import 'package:devnote/core/persistence/tag_repository.dart';
import 'package:devnote/features/settings/import_export/import_service.dart';
import 'package:devnote/features/settings/import_export/export_service.dart';
import 'package:devnote/features/settings/import_export/widgets/import_progress_dialog.dart';
import 'package:devnote/features/settings/import_export/widgets/export_progress_dialog.dart';

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
        ],
      ),
    );
  }

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
          value: ImportSource.markdownFolder,
          groupValue: _importSource,
          onChanged: (value) {
            setState(() {
              _importSource = value!;
            });
          },
        ),
        RadioListTile<ImportSource>(
          title: const Text('Obsidian Vault'),
          value: ImportSource.obsidianVault,
          groupValue: _importSource,
          onChanged: (value) {
            setState(() {
              _importSource = value!;
            });
          },
        ),
        RadioListTile<ImportSource>(
          title: const Text('Joplin 导出'),
          value: ImportSource.joplinExport,
          groupValue: _importSource,
          onChanged: (value) {
            setState(() {
              _importSource = value!;
            });
          },
        ),
        ListTile(
          title: const Text('冲突处理'),
          subtitle: Text(_conflictResolutionLabel),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showConflictResolutionDialog,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _startImport,
              child: const Text('开始导入'),
            ),
          ),
        ),
      ],
    );
  }

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
        RadioListTile<ExportRange>(
          title: const Text('全部笔记'),
          value: ExportRange.all,
          groupValue: _exportRange,
          onChanged: (value) {
            setState(() {
              _exportRange = value!;
            });
          },
        ),
        RadioListTile<ExportRange>(
          title: const Text('指定文件夹'),
          value: ExportRange.folder,
          groupValue: _exportRange,
          onChanged: (value) {
            setState(() {
              _exportRange = value!;
            });
          },
        ),
        RadioListTile<ExportRange>(
          title: const Text('指定标签'),
          value: ExportRange.tag,
          groupValue: _exportRange,
          onChanged: (value) {
            setState(() {
              _exportRange = value!;
            });
          },
        ),
        const SizedBox(height: 8),
        RadioListTile<ExportFormat>(
          title: const Text('Markdown'),
          value: ExportFormat.markdown,
          groupValue: _exportFormat,
          onChanged: (value) {
            setState(() {
              _exportFormat = value!;
            });
          },
        ),
        RadioListTile<ExportFormat>(
          title: const Text('HTML'),
          value: ExportFormat.html,
          groupValue: _exportFormat,
          onChanged: (value) {
            setState(() {
              _exportFormat = value!;
            });
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _startExport,
              child: const Text('开始导出'),
            ),
          ),
        ),
      ],
    );
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

    await _exportService.export(
      range: _exportRange,
      format: _exportFormat,
      targetPath: '',
    );

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
