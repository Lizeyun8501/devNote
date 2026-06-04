import 'package:flutter/material.dart';
import 'package:devnote/features/database/bloc/database_state.dart';

class KanbanView extends StatelessWidget {
  final DatabaseModel database;
  final List<FilterModel> filters;

  const KanbanView({
    super.key,
    required this.database,
    this.filters = const [],
  });

  @override
  Widget build(BuildContext context) {
    final groupField = database.fields.where((f) => f.fieldType == 'Select').firstOrNull;
    if (groupField == null) {
      return const Center(child: Text('请添加选择类型字段以使用看板视图'));
    }

    final options = groupField.options['options'] as List<dynamic>? ?? [];
    final columns = <String, List<DatabaseRowModel>>{};

    for (final option in options) {
      final label = option['value']?.toString() ?? option['label']?.toString() ?? '';
      columns[label] = [];
    }
    columns[''] = [];

    for (final row in database.rows) {
      final cell = row.cells.where((c) => c.fieldId == groupField.id).firstOrNull;
      final value = cell?.value?.toString() ?? '';
      if (columns.containsKey(value)) {
        columns[value]!.add(row);
      } else {
        columns['']!.add(row);
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: columns.entries.map((entry) {
          return _KanbanColumn(
            title: entry.key.isEmpty ? '未分组' : entry.key,
            rows: entry.value,
            fields: database.fields,
          );
        }).toList(),
      ),
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  final String title;
  final List<DatabaseRowModel> rows;
  final List<DatabaseFieldModel> fields;

  const _KanbanColumn({
    required this.title,
    required this.rows,
    required this.fields,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
                  Text('${rows.length}', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Divider(height: 1),
            ...rows.map((row) => _KanbanCard(row: row, fields: fields)),
          ],
        ),
      ),
    );
  }
}

class _KanbanCard extends StatelessWidget {
  final DatabaseRowModel row;
  final List<DatabaseFieldModel> fields;

  const _KanbanCard({
    required this.row,
    required this.fields,
  });

  @override
  Widget build(BuildContext context) {
    final displayFields = fields.where((f) => f.fieldType != 'Select').take(3);
    return ListTile(
      dense: true,
      title: Text(
        _getFirstTextValue() ?? '空行',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: displayFields.map((field) {
          final cell = row.cells.where((c) => c.fieldId == field.id).firstOrNull;
          return Text(
            '${field.name}: ${cell?.value?.toString() ?? ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          );
        }).toList(),
      ),
    );
  }

  String? _getFirstTextValue() {
    final textField = fields.where((f) => f.fieldType == 'Text').firstOrNull;
    if (textField == null) return null;
    final cell = row.cells.where((c) => c.fieldId == textField.id).firstOrNull;
    return cell?.value?.toString();
  }
}
