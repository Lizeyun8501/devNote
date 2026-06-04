import 'package:flutter/material.dart';
import 'package:devnote/features/database/bloc/database_state.dart';

class CalendarView extends StatelessWidget {
  final DatabaseModel database;
  final List<FilterModel> filters;

  const CalendarView({
    super.key,
    required this.database,
    this.filters = const [],
  });

  @override
  Widget build(BuildContext context) {
    final dateField = database.fields.where((f) => f.fieldType == 'Date').firstOrNull;
    if (dateField == null) {
      return const Center(child: Text('请添加日期类型字段以使用日历视图'));
    }

    final events = <DateTime, List<DatabaseRowModel>>{};
    for (final row in database.rows) {
      final cell = row.cells.where((c) => c.fieldId == dateField.id).firstOrNull;
      if (cell?.value != null) {
        final dateStr = cell!.value.toString();
        final date = DateTime.tryParse(dateStr);
        if (date != null) {
          final day = DateTime(date.year, date.month, date.day);
          events.putIfAbsent(day, () => []).add(row);
        }
      }
    }

    return CalendarDatePicker(
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      onDateChanged: (date) {
        final dayEvents = events[DateTime(date.year, date.month, date.day)] ?? [];
        if (dayEvents.isNotEmpty && context.mounted) {
          _showDayEvents(context, date, dayEvents);
        }
      },
    );
  }

  void _showDayEvents(BuildContext context, DateTime date, List<DatabaseRowModel> rows) {
    final titleField = database.fields.where((f) => f.fieldType == 'Text').firstOrNull;
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
