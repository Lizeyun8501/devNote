import 'package:flutter/material.dart';
import '../../core/di/injection.dart';
import '../notes/services/daily_notes_service.dart';
import '../templates/models/note_template.dart';
import '../templates/services/template_service.dart';

class DailyNotesSettingsPage extends StatefulWidget {
  const DailyNotesSettingsPage({super.key});

  @override
  State<DailyNotesSettingsPage> createState() => _DailyNotesSettingsPageState();
}

class _DailyNotesSettingsPageState extends State<DailyNotesSettingsPage> {
  final _dailyNotesService = getIt<DailyNotesService>();
  final _templateService = getIt<TemplateService>();
  DailyNotesConfig? _config;
  List<NoteTemplate> _templates = [];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await _dailyNotesService.getConfig();
    final templates = await _templateService.getAllTemplates();
    setState(() {
      _config = config;
      _templates = templates;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_config == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Notes 设置')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.date_range),
            title: const Text('日期格式'),
            subtitle: Text(_config!.dateFormat),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showDateFormatDialog,
          ),
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('存放文件夹'),
            subtitle: Text(_config!.folder),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showFolderDialog,
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('默认模板'),
            subtitle: Text(_getTemplateName()),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showTemplateDialog,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.auto_mode),
            title: const Text('自动创建'),
            subtitle: const Text('每天自动创建 Daily Note'),
            value: _config!.autoCreate,
            onChanged: (value) async {
              final newConfig = _config!.copyWith(autoCreate: value);
              await _dailyNotesService.saveConfig(newConfig);
              setState(() => _config = newConfig);
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('预览', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '今天的标题：${_dailyNotesService.getTodayDateString(format: _config!.dateFormat)}',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getTemplateName() {
    if (_config!.templateId == null) return '无';
    final template =
        _templates.where((t) => t.id == _config!.templateId).firstOrNull;
    return template?.name ?? '未知';
  }

  void _showDateFormatDialog() {
    final formats = [
      'yyyy-MM-dd',
      'yyyy/MM/dd',
      'yyyy年MM月dd日',
      'MM-dd-yyyy',
      'dd-MM-yyyy'
    ];
    showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('选择日期格式'),
        children: formats.map((format) {
          return SimpleDialogOption(
            onPressed: () async {
              final newConfig = _config!.copyWith(dateFormat: format);
              await _dailyNotesService.saveConfig(newConfig);
              setState(() => _config = newConfig);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text(format),
          );
        }).toList(),
      ),
    );
  }

  void _showFolderDialog() {
    final controller = TextEditingController(text: _config!.folder);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('存放文件夹'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '输入文件夹名称',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final newConfig = _config!.copyWith(folder: controller.text);
              await _dailyNotesService.saveConfig(newConfig);
              setState(() => _config = newConfig);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showTemplateDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('选择模板'),
        children: [
          SimpleDialogOption(
            onPressed: () async {
              final newConfig = _config!.copyWith(clearTemplate: true);
              await _dailyNotesService.saveConfig(newConfig);
              setState(() => _config = newConfig);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('无'),
          ),
          ..._templates.map((template) {
            return SimpleDialogOption(
              onPressed: () async {
                final newConfig = _config!.copyWith(templateId: template.id);
                await _dailyNotesService.saveConfig(newConfig);
                setState(() => _config = newConfig);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: Row(
                children: [
                  Icon(_getCategoryIcon(template.category), size: 20),
                  const SizedBox(width: 8),
                  Text(template.name),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(TemplateCategory category) {
    switch (category) {
      case TemplateCategory.meeting:
        return Icons.groups;
      case TemplateCategory.reading:
        return Icons.menu_book;
      case TemplateCategory.project:
        return Icons.assignment;
      case TemplateCategory.daily:
        return Icons.calendar_today;
      case TemplateCategory.todo:
        return Icons.checklist;
      case TemplateCategory.study:
        return Icons.school;
      case TemplateCategory.research:
        return Icons.science;
      case TemplateCategory.other:
        return Icons.description;
    }
  }
}
