import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/database/bloc/database_state.dart';
import 'package:devnote/features/database/bloc/database_bloc.dart';
import 'package:devnote/features/database/bloc/database_event.dart';
import 'package:devnote/features/database/widgets/cell_editors/text_cell_editor.dart';
import 'package:devnote/features/database/widgets/cell_editors/number_cell_editor.dart';
import 'package:devnote/features/database/widgets/cell_editors/select_cell_editor.dart';
import 'package:devnote/features/database/widgets/cell_editors/date_cell_editor.dart';
import 'package:devnote/features/database/widgets/cell_editors/checkbox_cell_editor.dart';
import 'package:devnote/features/database/widgets/cell_editors/url_cell_editor.dart';

class TableView extends StatelessWidget {
  final DatabaseModel database;
  final List<FilterModel> filters;
  final List<SortModel> sorts;

  const TableView({
    super.key,
    required this.database,
    this.filters = const [],
    this.sorts = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (database.fields.isEmpty) {
      return const Center(child: Text('暂无字段，请添加字段'));
    }

    var rows = _applyFilters(database.rows);
    rows = _applySorts(rows);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: [
            const DataColumn(label: Text('#')),
            ...database.fields.map((field) => DataColumn(
                  label: Text(field.name),
                )),
          ],
          rows: rows.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            return DataRow(
              cells: [
                DataCell(Text('${index + 1}')),
                ...database.fields.map((field) {
                  final cell = row.cells.where((c) => c.fieldId == field.id).firstOrNull;
                  return DataCell(
                    _buildCell(context, field, cell, row.id),
                    onTap: () => _editCell(context, field, cell, row.id),
                  );
                }),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCell(BuildContext context, DatabaseFieldModel field, DatabaseCellModel? cell, String rowId) {
    final value = cell?.value;
    switch (field.fieldType) {
      case 'Checkbox':
        return CheckboxCellEditor(
          value: value == true || value == 1,
          onChanged: (v) => _onCellChanged(context, rowId, field.id, v),
        );
      case 'URL':
        return UrlCellEditor(value: value?.toString() ?? '');
      case 'Number':
        return Text(value?.toString() ?? '', style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]));
      case 'Select':
        final options = field.options['options'] as List<dynamic>? ?? [];
        final match = options.where((o) => o['value'] == value).firstOrNull;
        if (match != null) {
          return Chip(
            label: Text(match['label'] ?? value?.toString() ?? ''),
            backgroundColor: _parseColor(match['color']),
          );
        }
        return Text(value?.toString() ?? '');
      case 'Date':
        return Text(value?.toString() ?? '');
      default:
        return Text(value?.toString() ?? '');
    }
  }

  void _editCell(BuildContext context, DatabaseFieldModel field, DatabaseCellModel? cell, String rowId) {
    switch (field.fieldType) {
      case 'Text':
        TextCellEditor.show(context, value: cell?.value?.toString() ?? '', onSaved: (v) => _onCellChanged(context, rowId, field.id, v));
        break;
      case 'Number':
        NumberCellEditor.show(context, value: cell?.value?.toString() ?? '', onSaved: (v) => _onCellChanged(context, rowId, field.id, v));
        break;
      case 'Select':
      case 'MultiSelect':
        SelectCellEditor.show(context, options: field.options, value: cell?.value, onSaved: (v) => _onCellChanged(context, rowId, field.id, v));
        break;
      case 'Date':
        DateCellEditor.show(context, value: cell?.value?.toString(), onSaved: (v) => _onCellChanged(context, rowId, field.id, v));
        break;
      case 'URL':
        UrlCellEditor.show(context, value: cell?.value?.toString() ?? '', onSaved: (v) => _onCellChanged(context, rowId, field.id, v));
        break;
    }
  }

  void _onCellChanged(BuildContext context, String rowId, String fieldId, dynamic value) {
    context.read<DatabaseBloc>().add(UpdateCell(
          databaseId: database.id,
          rowId: rowId,
          fieldId: fieldId,
          value: value,
        ));
  }

  List<DatabaseRowModel> _applyFilters(List<DatabaseRowModel> rows) {
    if (filters.isEmpty) return rows;
    return rows.where((row) {
      return filters.every((filter) {
        final cell = row.cells.where((c) => c.fieldId == filter.fieldId).firstOrNull;
        final cellValue = cell?.value?.toString() ?? '';
        final filterValue = filter.value?.toString() ?? '';
        switch (filter.operator) {
          case 'contains':
            return cellValue.contains(filterValue);
          case 'equals':
            return cellValue == filterValue;
          case 'not_equals':
            return cellValue != filterValue;
          case 'starts_with':
            return cellValue.startsWith(filterValue);
          case 'is_empty':
            return cellValue.isEmpty;
          case 'is_not_empty':
            return cellValue.isNotEmpty;
          default:
            return true;
        }
      });
    }).toList();
  }

  List<DatabaseRowModel> _applySorts(List<DatabaseRowModel> rows) {
    if (sorts.isEmpty) return rows;
    final sorted = List<DatabaseRowModel>.from(rows);
    for (final sort in sorts.reversed) {
      sorted.sort((a, b) {
        final aCell = a.cells.where((c) => c.fieldId == sort.fieldId).firstOrNull;
        final bCell = b.cells.where((c) => c.fieldId == sort.fieldId).firstOrNull;
        final aVal = aCell?.value?.toString() ?? '';
        final bVal = bCell?.value?.toString() ?? '';
        final cmp = aVal.compareTo(bVal);
        return sort.direction == 'desc' ? -cmp : cmp;
      });
    }
    return sorted;
  }

  Color? _parseColor(dynamic colorValue) {
    if (colorValue is String && colorValue.startsWith('#')) {
      final hex = colorValue.replaceFirst('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    }
    return null;
  }
}
