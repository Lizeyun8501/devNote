// 日历视图 —— 按日期字段展示事件的月历网格
// 借鉴 Notion 的日历视图设计
// 来源: https://www.notion.so
// 借鉴内容: 月历网格中用圆点标记有事件的日期、点击日期弹出事件列表、
//         月份切换动画、今天高亮

import 'package:flutter/material.dart';
import 'package:devnote/features/database/bloc/database_state.dart';

class CalendarView extends StatefulWidget {
  final DatabaseModel database;
  final List<FilterModel> filters;

  const CalendarView({
    super.key,
    required this.database,
    this.filters = const [],
  });

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  late DateTime _currentMonth;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  }

  /// 获取日期字段
  DatabaseFieldModel? get _dateField =>
      widget.database.fields.where((f) => f.fieldType == 'Date').firstOrNull;

  /// 获取标题字段
  DatabaseFieldModel? get _titleField =>
      widget.database.fields.where((f) => f.fieldType == 'Text').firstOrNull;

  /// 按日期分组事件
  Map<DateTime, List<DatabaseRowModel>> get _eventsByDate {
    final dateField = _dateField;
    if (dateField == null) return {};

    final events = <DateTime, List<DatabaseRowModel>>{};
    for (final row in widget.database.rows) {
      final cell = row.cells.where((c) => c.fieldId == dateField.id).firstOrNull;
      if (cell?.value != null) {
        final date = DateTime.tryParse(cell!.value.toString());
        if (date != null) {
          final day = DateTime(date.year, date.month, date.day);
          events.putIfAbsent(day, () => []).add(row);
        }
      }
    }
    return events;
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    });
  }

  void _goToToday() {
    setState(() {
      _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
      _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateField = _dateField;
    if (dateField == null) {
      return const Center(child: Text('请添加日期类型字段以使用日历视图'));
    }

    final events = _eventsByDate;

    return Column(
      children: [
        _buildHeader(),
        const Divider(height: 1),
        Expanded(child: _buildMonthGrid(events)),
        if (_selectedDate != null && events[_selectedDate] != null)
          _buildEventList(events[_selectedDate]!),
      ],
    );
  }

  Widget _buildHeader() {
    final monthName = '${_currentMonth.year}年${_currentMonth.month}月';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _previousMonth,
          ),
          Expanded(
            child: Text(
              monthName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _nextMonth,
          ),
          TextButton(
            onPressed: _goToToday,
            child: const Text('今天'),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthGrid(Map<DateTime, List<DatabaseRowModel>> events) {
    const dayNames = ['一', '二', '三', '四', '五', '六', '日'];
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    // 周一=1, 周日=7
    final startWeekday = firstDay.weekday;
    final daysInMonth = lastDay.day;
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    return Column(
      children: [
        // 星期标题行
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: dayNames.map((name) => Expanded(
              child: Center(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 4),
        // 日期网格
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: startWeekday - 1 + daysInMonth,
            itemBuilder: (context, index) {
              // 前面的空白格
              if (index < startWeekday - 1) {
                return const SizedBox.shrink();
              }
              final day = index - startWeekday + 2;
              final date = DateTime(_currentMonth.year, _currentMonth.month, day);
              final isToday = date == today;
              final isSelected = date == _selectedDate;
              final dayEvents = events[date] ?? [];

              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedDate = date;
                  });
                  if (dayEvents.isNotEmpty) {
                    _showDayEvents(date, dayEvents);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : isToday
                            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                            : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? Theme.of(context).colorScheme.onPrimary
                              : isToday
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                        ),
                      ),
                      if (dayEvents.isNotEmpty)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            dayEvents.length > 3 ? 3 : dayEvents.length,
                            (_) => Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEventList(List<DatabaseRowModel> rows) {
    final titleField = _titleField;
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          String title = '空行';
          if (titleField != null) {
            final cell = row.cells.where((c) => c.fieldId == titleField.id).firstOrNull;
            title = cell?.value?.toString() ?? '空行';
          }
          return ListTile(
            dense: true,
            leading: const Icon(Icons.event, size: 16),
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          );
        },
      ),
    );
  }

  void _showDayEvents(DateTime date, List<DatabaseRowModel> rows) {
    final titleField = _titleField;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(),
          ...rows.map((row) {
            String title = '空行';
            if (titleField != null) {
              final cell = row.cells.where((c) => c.fieldId == titleField.id).firstOrNull;
              title = cell?.value?.toString() ?? '空行';
            }
            return ListTile(title: Text(title));
          }),
        ],
      ),
    );
  }
}
