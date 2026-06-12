// 高级数据表格视图 —— 借鉴 pluto_grid 替代 Flutter 内置 DataTable
// pluto_grid 提供列拖拽、排序、过滤、分页、内联编辑等开箱即用功能
// 来源: https://pub.dev/packages/pluto_grid
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:devnote/features/database/bloc/database_state.dart';
import 'package:devnote/features/database/bloc/database_bloc.dart';
import 'package:devnote/features/database/bloc/database_event.dart';

class TableView extends StatefulWidget {
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
  State<TableView> createState() => _TableViewState();
}

class _TableViewState extends State<TableView> {
  /// PlutoGrid 控制器，管理列、行及网格状态
  late PlutoGridStateManager _stateManager;

  /// 将 DatabaseFieldModel 转换为 PlutoColumn
  // 借鉴 pluto_grid 的列类型系统，将自定义字段类型映射到 PlutoColumnType
  List<PlutoColumn> _buildColumns() {
    // 行号列
    final rowNumberColumn = PlutoColumn(
      title: '#',
      field: '_rowNumber',
      type: PlutoColumnType.text(),
      readOnly: true,
      width: 60,
      enableSorting: false,
      enableFilterMenuItem: false,
      enableContextMenu: false,
      enableColumnDrag: false,
      textAlign: PlutoColumnTextAlign.center,
    );

    final fieldColumns = widget.database.fields.map((field) {
      return PlutoColumn(
        title: field.name,
        field: field.id,
        type: _mapFieldType(field),
        readOnly: field.fieldType == 'Checkbox',
        width: _getDefaultWidth(field.fieldType),
        enableSorting: true,
        enableFilterMenuItem: true,
        enableContextMenu: true,
        enableColumnDrag: true,
        textAlign: field.fieldType == 'Number'
            ? PlutoColumnTextAlign.right
            : PlutoColumnTextAlign.left,
      );
    }).toList();

    return [rowNumberColumn, ...fieldColumns];
  }

  /// 将自定义字段类型映射到 PlutoColumnType
  // 借鉴 pluto_grid 的类型系统，支持文本、数字、选择、日期等
  PlutoColumnType _mapFieldType(DatabaseFieldModel field) {
    switch (field.fieldType) {
      case 'Number':
        return PlutoColumnType.number(
          format: '#,###.##',
          allowFirstDot: true,
        );
      case 'Select':
        final options = field.options['options'] as List<dynamic>? ?? [];
        final selectItems = options
            .map((o) => o['label']?.toString() ?? o['value']?.toString() ?? '')
            .toList();
        return PlutoColumnType.select(selectItems);
      case 'MultiSelect':
        final options = field.options['options'] as List<dynamic>? ?? [];
        final selectItems = options
            .map((o) => o['label']?.toString() ?? o['value']?.toString() ?? '')
            .toList();
        return PlutoColumnType.select(selectItems);
      case 'Date':
        return PlutoColumnType.date(
          format: 'yyyy-MM-dd',
        );
      case 'Checkbox':
        return PlutoColumnType.text();
      case 'URL':
        return PlutoColumnType.text();
      case 'Text':
      default:
        return PlutoColumnType.text();
    }
  }

  /// 根据字段类型返回默认列宽
  double _getDefaultWidth(String fieldType) {
    switch (fieldType) {
      case 'Checkbox':
        return 100;
      case 'Number':
        return 150;
      case 'Date':
        return 150;
      case 'URL':
        return 250;
      case 'Select':
      case 'MultiSelect':
        return 180;
      default:
        return 200;
    }
  }

  /// 将 DatabaseRowModel 列表转换为 PlutoRow 列表
  List<PlutoRow> _buildRows() {
    var rows = _applyFilters(widget.database.rows);
    rows = _applySorts(rows);

    return rows.asMap().entries.map((entry) {
      final index = entry.key;
      final row = entry.value;

      // 构建 cells Map：行号 + 各字段值
      final cells = <String, PlutoCell>{
        '_rowNumber': PlutoCell(value: '${index + 1}'),
      };

      for (final field in widget.database.fields) {
        final cell = row.cells
            .where((c) => c.fieldId == field.id)
            .firstOrNull;
        cells[field.id] = PlutoCell(
          value: _formatCellValue(field, cell?.value),
        );
      }

      return PlutoRow(cells: cells);
    }).toList();
  }

  /// 格式化单元格值，确保与 PlutoColumnType 兼容
  dynamic _formatCellValue(DatabaseFieldModel field, dynamic value) {
    if (value == null) return '';

    switch (field.fieldType) {
      case 'Number':
        if (value is num) return value;
        final parsed = num.tryParse(value.toString());
        return parsed ?? '';
      case 'Checkbox':
        return (value == true || value == 1) ? 'true' : 'false';
      case 'Select':
      case 'MultiSelect':
        // 将 value 映射为 label 显示
        final options = field.options['options'] as List<dynamic>? ?? [];
        final match = options.where((o) => o['value'] == value).firstOrNull;
        if (match != null) {
          return match['label']?.toString() ?? value.toString();
        }
        return value.toString();
      case 'Date':
        return value.toString();
      case 'URL':
        return value.toString();
      case 'Text':
      default:
        return value.toString();
    }
  }

  /// 从 PlutoCell 显示值反推出实际存储值
  // Select/MultiSelect 字段在 PlutoGrid 中存储的是 label，需要还原为 value
  dynamic _parseRawValue(DatabaseFieldModel field, dynamic displayValue) {
    if (displayValue == null || displayValue == '') return null;

    switch (field.fieldType) {
      case 'Number':
        final parsed = num.tryParse(displayValue.toString());
        return parsed;
      case 'Checkbox':
        return displayValue.toString() == 'true';
      case 'Select':
      case 'MultiSelect':
        // 从 label 反查 value
        final options = field.options['options'] as List<dynamic>? ?? [];
        final match = options
            .where((o) => o['label'] == displayValue.toString())
            .firstOrNull;
        if (match != null) {
          return match['value'];
        }
        return displayValue;
      case 'Date':
      case 'URL':
      case 'Text':
      default:
        return displayValue;
    }
  }

  /// 应用过滤条件
  List<DatabaseRowModel> _applyFilters(List<DatabaseRowModel> rows) {
    if (widget.filters.isEmpty) return rows;
    return rows.where((row) {
      return widget.filters.every((filter) {
        final cell = row.cells
            .where((c) => c.fieldId == filter.fieldId)
            .firstOrNull;
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

  /// 应用排序条件
  List<DatabaseRowModel> _applySorts(List<DatabaseRowModel> rows) {
    if (widget.sorts.isEmpty) return rows;
    final sorted = List<DatabaseRowModel>.from(rows);
    for (final sort in widget.sorts.reversed) {
      sorted.sort((a, b) {
        final aCell = a.cells
            .where((c) => c.fieldId == sort.fieldId)
            .firstOrNull;
        final bCell = b.cells
            .where((c) => c.fieldId == sort.fieldId)
            .firstOrNull;
        final aVal = aCell?.value?.toString() ?? '';
        final bVal = bCell?.value?.toString() ?? '';
        final cmp = aVal.compareTo(bVal);
        return sort.direction == 'desc' ? -cmp : cmp;
      });
    }
    return sorted;
  }

  /// 派发 UpdateCell 事件到 DatabaseBloc
  void _onCellChanged(PlutoGridOnChangedEvent event) {
    final fieldId = event.column.field;
    // 跳过行号列
    if (fieldId == '_rowNumber') return;

    // 通过行索引找到对应的 DatabaseRowModel
    final filteredRows = _applyFilters(widget.database.rows);
    final sortedRows = _applySorts(filteredRows);
    final rowIndex = event.rowIdx;
    if (rowIndex < 0 || rowIndex >= sortedRows.length) return;

    final row = sortedRows[rowIndex];
    final field = widget.database.fields
        .where((f) => f.id == fieldId)
        .firstOrNull;
    if (field == null) return;

    // 将显示值转换为实际存储值
    final rawValue = _parseRawValue(field, event.value);

    context.read<DatabaseBloc>().add(UpdateCell(
          databaseId: widget.database.id,
          rowId: row.id,
          fieldId: fieldId,
          value: rawValue,
        ));
  }

  /// 解析颜色值
  Color? _parseColor(dynamic colorValue) {
    if (colorValue is String && colorValue.startsWith('#')) {
      final hex = colorValue.replaceFirst('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.database.fields.isEmpty) {
      return const Center(child: Text('暂无字段，请添加字段'));
    }

    final columns = _buildColumns();
    final rows = _buildRows();

    return PlutoGrid(
      columns: columns,
      rows: rows,
      // 借鉴 pluto_grid 的 onChanged 回调，在单元格值变更时派发 UpdateCell 事件
      onChanged: _onCellChanged,
      onLoaded: (PlutoGridOnLoadedEvent event) {
        _stateManager = event.stateManager;
      },
      // 配置：启用列拖拽移动、排序、过滤
      configuration: PlutoGridConfiguration(
        // 启用列移动（拖拽排序）
        enableMoveDownAfterSelecting: false,
        // 列过滤配置
        columnFilter: PlutoGridColumnFilterConfig(
          filters: const [
            ...FilterHelper.defaultFilters,
          ],
          resolveDefaultColumnFilter: (column, resolver) {
            // 根据列类型选择合适的默认过滤器
            if (column.type.isNumber) {
              return resolver<PlutoFilterTypeGreaterThan>()
                  as PlutoFilterType;
            }
            if (column.type.isSelect) {
              return resolver<PlutoFilterTypeContains>()
                  as PlutoFilterType;
            }
            return resolver<PlutoFilterTypeContains>()
                as PlutoFilterType;
          },
        ),
        // 表格样式配置
        style: PlutoGridStyleConfig(
          oddRowColor: Theme.of(context).colorScheme.surfaceContainerLow,
          activatedColor: Theme.of(context).colorScheme.primaryContainer,
          columnTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ) ??
              const TextStyle(fontWeight: FontWeight.bold),
          cellTextStyle: Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
          gridBorderColor: Theme.of(context).dividerColor,
          gridBorderRadius: BorderRadius.circular(8),
          enableCellBorderVertical: true,
          enableCellBorderHorizontal: true,
        ),
        // 快捷键配置
        shortcut: PlutoGridShortcut(
          actions: {
            ...PlutoGridShortcut.defaultActions,
          },
        ),
      ),
      // 行选择模式
      mode: PlutoGridMode.normal,
    );
  }
}
