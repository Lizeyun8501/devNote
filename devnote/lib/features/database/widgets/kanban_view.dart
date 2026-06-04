// 看板视图 —— 按 Select 字段分组的拖拽式看板
// 借鉴 Notion 的看板拖拽分组设计
// 来源: https://www.notion.so
// 借鉴内容: Draggable + DragTarget 实现跨列拖拽、
//         拖拽时半透明预览、目标列高亮、拖拽完成后更新 Select 字段值

import 'package:flutter/material.dart';
import 'package:devnote/features/database/bloc/database_state.dart';

class KanbanView extends StatelessWidget {
  final DatabaseModel database;
  final List<FilterModel> filters;
  final void Function(String rowId, String fieldId, String newValue)? onCellUpdate;

  const KanbanView({
    super.key,
    required this.database,
    this.filters = const [],
    this.onCellUpdate,
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
            groupFieldId: groupField.id,
            onCellUpdate: onCellUpdate,
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
  final String groupFieldId;
  final void Function(String rowId, String fieldId, String newValue)? onCellUpdate;

  const _KanbanColumn({
    required this.title,
    required this.rows,
    required this.fields,
    required this.groupFieldId,
    this.onCellUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<_KanbanDragData>(
      onWillAcceptWithDetails: (details) {
        // 允许从其他列拖入
        return true;
      },
      onAcceptWithDetails: (details) {
        // 拖拽完成: 更新该行的 Select 字段值为当前列的标题
        final newGroupValue = title == '未分组' ? '' : title;
        onCellUpdate?.call(
          details.data.rowId,
          groupFieldId,
          newGroupValue,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 280,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: isHovering
                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
            borderRadius: BorderRadius.circular(12),
            border: isHovering
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : null,
          ),
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
                ...rows.map((row) => _KanbanCard(
                      row: row,
                      fields: fields,
                      columnTitle: title,
                    )),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 拖拽时传递的数据
class _KanbanDragData {
  final String rowId;
  final String sourceColumn;

  const _KanbanDragData({required this.rowId, required this.sourceColumn});
}

class _KanbanCard extends StatelessWidget {
  final DatabaseRowModel row;
  final List<DatabaseFieldModel> fields;
  final String columnTitle;

  const _KanbanCard({
    required this.row,
    required this.fields,
    required this.columnTitle,
  });

  @override
  Widget build(BuildContext context) {
    final displayFields = fields.where((f) => f.fieldType != 'Select').take(3);
    final dragData = _KanbanDragData(rowId: row.id, sourceColumn: columnTitle);

    return LongPressDraggable<_KanbanDragData>(
      data: dragData,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 256,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _getFirstTextValue() ?? '空行',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: _buildCard(context, displayFields),
      ),
      child: _buildCard(context, displayFields),
    );
  }

  Widget _buildCard(BuildContext context, Iterable<DatabaseFieldModel> displayFields) {
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
