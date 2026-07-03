import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/persistence/models/note_model.dart';
import 'bloc/notes_bloc.dart';
import 'bloc/notes_event.dart';
import 'services/daily_notes_service.dart';

class DailyNotesPage extends StatefulWidget {
  const DailyNotesPage({super.key});

  @override
  State<DailyNotesPage> createState() => _DailyNotesPageState();
}

class _DailyNotesPageState extends State<DailyNotesPage> {
  final _dailyNotesService = getIt<DailyNotesService>();
  DateTime _selectedDate = DateTime.now();
  NoteModel? _dailyNote;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDailyNote();
  }

  Future<void> _loadDailyNote() async {
    setState(() => _loading = true);
    final note = await _dailyNotesService.findDailyNote(_selectedDate);
    if (mounted) {
      setState(() {
        _dailyNote = note;
        _loading = false;
      });
    }
  }

  void _goToPreviousDay() {
    setState(() {
      _selectedDate = _dailyNotesService.getPreviousDay(_selectedDate);
    });
    _loadDailyNote();
  }

  void _goToNextDay() {
    setState(() {
      _selectedDate = _dailyNotesService.getNextDay(_selectedDate);
    });
    _loadDailyNote();
  }

  void _goToToday() {
    setState(() {
      _selectedDate = DateTime.now();
    });
    _loadDailyNote();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadDailyNote();
    }
  }

  Future<void> _createDailyNote() async {
    final title = await _dailyNotesService.generateDailyNoteTitle(_selectedDate);
    final templateBlocks = await _dailyNotesService.getTemplateBlocks();
    final config = await _dailyNotesService.getConfig();

    if (mounted) {
      context.read<NotesBloc>().add(
        CreateDailyNote(
          title: title,
          folderName: config.folder,
          templateBlocks: templateBlocks ?? [],
        ),
      );
      // 创建后重新加载以显示新笔记
      // 等待一小段时间让 BLoC 完成数据库写入
      Future.delayed(const Duration(milliseconds: 300), _loadDailyNote);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _dailyNotesService.getFriendlyDateLabel(_selectedDate);
    final dateStr = DateFormat('yyyy年MM月dd日 EEEE', 'zh_CN').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(dateLabel),
            Text(
              dateStr,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _goToPreviousDay,
            tooltip: '前一天',
          ),
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: _goToToday,
            tooltip: '今天',
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _goToNextDay,
            tooltip: '后一天',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _pickDate,
            tooltip: '选择日期',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dailyNote == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.note_add,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '$dateLabel 没有日记',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('创建日记'),
                        onPressed: _createDailyNote,
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.note, color: Colors.blue),
                        title: Text(_dailyNote!.title),
                        subtitle: Text(
                          '创建于 ${DateFormat('yyyy-MM-dd HH:mm').format(_dailyNote!.createdAt)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          context.go('/notes/${_dailyNote!.id}');
                        },
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createDailyNote,
        child: const Icon(Icons.add),
      ),
    );
  }
}
