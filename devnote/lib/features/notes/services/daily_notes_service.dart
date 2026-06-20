import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/di/injection.dart';
import '../../../core/persistence/database_helper.dart';
import '../../../core/persistence/models/note_model.dart';
import '../../templates/models/note_template.dart';
import '../../templates/services/template_service.dart';

/// Daily Notes 服务
/// 管理每日笔记的创建、查找和导航
class DailyNotesService {
  static const _dateFormatKey = 'daily_notes_date_format';
  static const _folderKey = 'daily_notes_folder';
  static const _templateKey = 'daily_notes_template_id';
  static const _autoCreateKey = 'daily_notes_auto_create';

  final TemplateService _templateService = getIt<TemplateService>();

  /// 获取今天的日期字符串
  String getTodayDateString({String? format}) {
    final now = DateTime.now();
    return _formatDate(now, format ?? 'yyyy-MM-dd');
  }

  /// 格式化日期
  String _formatDate(DateTime date, String format) {
    return format
        .replaceAll('yyyy', date.year.toString())
        .replaceAll('MM', date.month.toString().padLeft(2, '0'))
        .replaceAll('dd', date.day.toString().padLeft(2, '0'))
        .replaceAll('HH', date.hour.toString().padLeft(2, '0'))
        .replaceAll('mm', date.minute.toString().padLeft(2, '0'));
  }

  /// 获取 Daily Notes 配置
  Future<DailyNotesConfig> getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return DailyNotesConfig(
      dateFormat: prefs.getString(_dateFormatKey) ?? 'yyyy-MM-dd',
      folder: prefs.getString(_folderKey) ?? 'Daily Notes',
      templateId: prefs.getString(_templateKey),
      autoCreate: prefs.getBool(_autoCreateKey) ?? false,
    );
  }

  /// 保存 Daily Notes 配置
  Future<void> saveConfig(DailyNotesConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dateFormatKey, config.dateFormat);
    await prefs.setString(_folderKey, config.folder);
    if (config.templateId != null) {
      await prefs.setString(_templateKey, config.templateId!);
    } else {
      await prefs.remove(_templateKey);
    }
    await prefs.setBool(_autoCreateKey, config.autoCreate);
  }

  /// 生成 Daily Note 的标题
  Future<String> generateDailyNoteTitle(DateTime date) async {
    final config = await getConfig();
    return _formatDate(date, config.dateFormat);
  }

  /// 检查今天的 Daily Note 是否已存在
  /// 需要通过 NoteRepository 查询，这里返回标题供调用方查询
  Future<String> getTodayNoteTitle() async {
    return generateDailyNoteTitle(DateTime.now());
  }

  /// 查找指定日期的 Daily Note。
  /// 根据配置的日期格式生成标题，再从数据库查询匹配的笔记。
  /// Daily Notes 存放在配置的文件夹中，这里通过标题全局查询
  /// （标题已包含日期，唯一性足够）。
  Future<NoteModel?> findDailyNote(DateTime date) async {
    final title = await generateDailyNoteTitle(date);
    final db = await getIt<DatabaseHelper>().database;
    final results = await db.query(
      'notes',
      where: 'title = ?',
      whereArgs: [title],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return NoteModel.fromJson(results.first);
  }

  /// 获取模板内容（如果配置了模板）
  Future<List<TemplateBlock>?> getTemplateBlocks() async {
    final config = await getConfig();
    if (config.templateId == null) return null;

    final templates = await _templateService.getAllTemplates();
    final template =
        templates.where((t) => t.id == config.templateId).firstOrNull;
    return template?.blocks;
  }

  /// 获取前一天的日期
  DateTime getPreviousDay(DateTime date) {
    return date.subtract(const Duration(days: 1));
  }

  /// 获取后一天的日期
  DateTime getNextDay(DateTime date) {
    return date.add(const Duration(days: 1));
  }

  /// 获取本周的日期列表（周一到周日）
  List<DateTime> getWeekDates(DateTime date) {
    final weekday = date.weekday; // 1=Monday, 7=Sunday
    final monday = date.subtract(Duration(days: weekday - 1));
    return List.generate(7, (i) => monday.add(Duration(days: i)));
  }

  /// 获取本月的日期列表
  List<DateTime> getMonthDates(DateTime date) {
    final firstDay = DateTime(date.year, date.month, 1);
    final lastDay = DateTime(date.year, date.month + 1, 0);
    final days = lastDay.day;
    return List.generate(days, (i) => firstDay.add(Duration(days: i)));
  }

  /// 检查是否是今天
  bool isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// 检查是否是昨天
  bool isYesterday(DateTime date) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day;
  }

  /// 获取日期的友好显示
  String getFriendlyDateLabel(DateTime date) {
    if (isToday(date)) return '今天';
    if (isYesterday(date)) return '昨天';

    final now = DateTime.now();
    final diff = now.difference(date).inDays;

    if (diff == 1) return '昨天';
    if (diff > 0 && diff < 7) return '$diff 天前';
    if (diff >= 7 && diff < 30) return '${(diff / 7).floor()} 周前';

    return _formatDate(date, 'yyyy-MM-dd');
  }
}

/// Daily Notes 配置
class DailyNotesConfig {
  final String dateFormat;
  final String folder;
  final String? templateId;
  final bool autoCreate;

  DailyNotesConfig({
    required this.dateFormat,
    required this.folder,
    this.templateId,
    required this.autoCreate,
  });

  DailyNotesConfig copyWith({
    String? dateFormat,
    String? folder,
    String? templateId,
    bool? autoCreate,
    bool clearTemplate = false,
  }) =>
      DailyNotesConfig(
        dateFormat: dateFormat ?? this.dateFormat,
        folder: folder ?? this.folder,
        templateId: clearTemplate ? null : (templateId ?? this.templateId),
        autoCreate: autoCreate ?? this.autoCreate,
      );
}
