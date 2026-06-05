import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/database/bloc/database_event.dart';
import 'package:devnote/features/database/bloc/database_state.dart';
import 'package:devnote/features/database/database_service.dart';

/// 数据库业务逻辑组件 (DatabaseBloc)
/// 管理数据库的 CRUD 操作、字段管理、行管理、视图管理和过滤/排序
/// 所有数据变更操作完成后自动刷新数据库详情，确保 UI 与数据一致
class DatabaseBloc extends Bloc<DatabaseEvent, DatabaseState> {
  final DatabaseService _databaseService;

  DatabaseBloc(this._databaseService) : super(const DatabaseInitial()) {
    on<LoadDatabases>(_onLoadDatabases);
    on<CreateDatabase>(_onCreateDatabase);
    on<DeleteDatabase>(_onDeleteDatabase);
    on<LoadDatabaseDetail>(_onLoadDatabaseDetail);
    on<AddField>(_onAddField);
    on<UpdateField>(_onUpdateField);
    on<DeleteField>(_onDeleteField);
    on<AddRow>(_onAddRow);
    on<UpdateCell>(_onUpdateCell);
    on<DeleteRow>(_onDeleteRow);
    on<AddView>(_onAddView);
    on<DeleteView>(_onDeleteView);
    on<ApplyFilters>(_onApplyFilters);
    on<ApplySorts>(_onApplySorts);
  }

  /// 加载数据库列表
  Future<void> _onLoadDatabases(LoadDatabases event, Emitter<DatabaseState> emit) async {
    emit(const DatabaseLoading());
    try {
      final databases = await _databaseService.listDatabases();
      emit(DatabaseListLoaded(databases));
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

  /// 创建数据库
  Future<void> _onCreateDatabase(CreateDatabase event, Emitter<DatabaseState> emit) async {
    try {
      await _databaseService.createDatabase(event.name);
      // 创建成功后刷新列表
      final databases = await _databaseService.listDatabases();
      emit(DatabaseListLoaded(databases));
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

  /// 删除数据库
  Future<void> _onDeleteDatabase(DeleteDatabase event, Emitter<DatabaseState> emit) async {
    try {
      await _databaseService.deleteDatabase(event.databaseId);
      // 删除成功后刷新列表
      final databases = await _databaseService.listDatabases();
      emit(DatabaseListLoaded(databases));
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

  /// 加载数据库详情（含字段、行、视图）
  Future<void> _onLoadDatabaseDetail(LoadDatabaseDetail event, Emitter<DatabaseState> emit) async {
    emit(const DatabaseLoading());
    try {
      final database = await _databaseService.getDatabase(event.databaseId);
      emit(DatabaseDetailLoaded(database: database));
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

  /// 添加字段到数据库
  Future<void> _onAddField(AddField event, Emitter<DatabaseState> emit) async {
    try {
      await _databaseService.addField(
        databaseId: event.databaseId,
        name: event.name,
        fieldType: event.fieldType,
        options: event.options,
        formula: event.formula,
      );
      // 添加字段后刷新数据库详情
      final database = await _databaseService.getDatabase(event.databaseId);
      emit(DatabaseDetailLoaded(database: database));
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

  /// 更新字段属性
  Future<void> _onUpdateField(UpdateField event, Emitter<DatabaseState> emit) async {
    try {
      await _databaseService.updateField(
        databaseId: event.databaseId,
        fieldId: event.fieldId,
        name: event.name,
        options: event.options,
      );
      // 更新字段后刷新数据库详情，保留原有状态
      final database = await _databaseService.getDatabase(event.databaseId);
      final state = this.state;
      if (state is DatabaseDetailLoaded) {
        emit(state.copyWith(database: database));
      } else {
        emit(DatabaseDetailLoaded(database: database));
      }
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

  /// 删除字段
  Future<void> _onDeleteField(DeleteField event, Emitter<DatabaseState> emit) async {
    try {
      await _databaseService.deleteField(
        databaseId: event.databaseId,
        fieldId: event.fieldId,
      );
      // 删除字段后刷新数据库详情
      final database = await _databaseService.getDatabase(event.databaseId);
      final state = this.state;
      if (state is DatabaseDetailLoaded) {
        emit(state.copyWith(database: database));
      } else {
        emit(DatabaseDetailLoaded(database: database));
      }
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

/// 添加新行
  /// 先验证输入参数，添加成功后刷新数据库详情，添加失败正确处理异常
  Future<void> _onAddRow(AddRow event, Emitter<DatabaseState> emit) async {
    try {
      // 输入参数验证
      if (event.databaseId.isEmpty) {
        emit(const DatabaseError('数据库ID不能为空'));
        return;
      }
      if (event.cells == null) {
        emit(const DatabaseError('单元格数据不能为空'));
        return;
      }

      await _databaseService.addRow(
        databaseId: event.databaseId,
        cells: event.cells,
      );
      // 添加成功后刷新数据库详情
      final database = await _databaseService.getDatabase(event.databaseId);
      final state = this.state;
      // 结果验证：确保数据库对象不为空
      if (database == null) {
        emit(const DatabaseError('获取数据库详情失败'));
        return;
      }
      if (state is DatabaseDetailLoaded) {
        emit(state.copyWith(database: database));
      } else {
        emit(DatabaseDetailLoaded(database: database));
      }
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

/// 更新单元格值
  /// 参数验证 + 结果验证，更新成功后刷新数据库详情
  Future<void> _onUpdateCell(UpdateCell event, Emitter<DatabaseState> emit) async {
    try {
      // 输入参数验证
      if (event.databaseId.isEmpty) {
        emit(const DatabaseError('数据库ID不能为空'));
        return;
      }
      if (event.rowId.isEmpty) {
        emit(const DatabaseError('行ID不能为空'));
        return;
      }
      if (event.fieldId.isEmpty) {
        emit(const DatabaseError('字段ID不能为空'));
        return;
      }

      await _databaseService.updateCell(
        databaseId: event.databaseId,
        rowId: event.rowId,
        fieldId: event.fieldId,
        value: event.value,
      );
      final database = await _databaseService.getDatabase(event.databaseId);
      final state = this.state;
      // 结果验证：确保数据库对象不为空
      if (database == null) {
        emit(const DatabaseError('获取数据库详情失败'));
        return;
      }
      if (state is DatabaseDetailLoaded) {
        emit(state.copyWith(database: database));
      } else {
        emit(DatabaseDetailLoaded(database: database));
      }
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

  /// 删除行
  /// 参数验证 + 结果验证，删除成功后刷新数据库详情
  Future<void> _onDeleteRow(DeleteRow event, Emitter<DatabaseState> emit) async {
    try {
      // 输入参数验证
      if (event.databaseId.isEmpty) {
        emit(const DatabaseError('数据库ID不能为空'));
        return;
      }
      if (event.rowId.isEmpty) {
        emit(const DatabaseError('行ID不能为空'));
        return;
      }

      await _databaseService.deleteRow(
        databaseId: event.databaseId,
        rowId: event.rowId,
      );
      final database = await _databaseService.getDatabase(event.databaseId);
      final state = this.state;
      // 结果验证：确保数据库对象不为空
      if (database == null) {
        emit(const DatabaseError('获取数据库详情失败'));
        return;
      }
      if (state is DatabaseDetailLoaded) {
        emit(state.copyWith(database: database));
      } else {
        emit(DatabaseDetailLoaded(database: database));
      }
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

  /// 添加视图
  /// 参数验证 + 结果验证，添加成功后刷新数据库详情
  Future<void> _onAddView(AddView event, Emitter<DatabaseState> emit) async {
    try {
      // 输入参数验证
      if (event.databaseId.isEmpty) {
        emit(const DatabaseError('数据库ID不能为空'));
        return;
      }
      if (event.name.isEmpty) {
        emit(const DatabaseError('视图名称不能为空'));
        return;
      }

      await _databaseService.addView(
        databaseId: event.databaseId,
        name: event.name,
        viewType: event.viewType,
      );
      final database = await _databaseService.getDatabase(event.databaseId);
      final state = this.state;
      // 结果验证：确保数据库对象不为空
      if (database == null) {
        emit(const DatabaseError('获取数据库详情失败'));
        return;
      }
      if (state is DatabaseDetailLoaded) {
        emit(state.copyWith(database: database));
      } else {
        emit(DatabaseDetailLoaded(database: database));
      }
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

  /// 删除视图
  /// 参数验证 + 结果验证，删除成功后刷新数据库详情
  Future<void> _onDeleteView(DeleteView event, Emitter<DatabaseState> emit) async {
    try {
      // 输入参数验证
      if (event.databaseId.isEmpty) {
        emit(const DatabaseError('数据库ID不能为空'));
        return;
      }
      if (event.viewId.isEmpty) {
        emit(const DatabaseError('视图ID不能为空'));
        return;
      }

      await _databaseService.deleteView(
        databaseId: event.databaseId,
        viewId: event.viewId,
      );
      final database = await _databaseService.getDatabase(event.databaseId);
      final state = this.state;
      // 结果验证：确保数据库对象不为空
      if (database == null) {
        emit(const DatabaseError('获取数据库详情失败'));
        return;
      }
      if (state is DatabaseDetailLoaded) {
        emit(state.copyWith(database: database));
      } else {
        emit(DatabaseDetailLoaded(database: database));
      }
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

  /// 应用过滤条件
  /// 验证每个过滤器的必填字段（fieldId, operator, value），再执行过滤和排序
  Future<void> _onApplyFilters(ApplyFilters event, Emitter<DatabaseState> emit) async {
    final state = this.state;
    if (state is DatabaseDetailLoaded) {
      // 过滤器验证：确保每个过滤条件包含必填字段
      final filters = event.filters
          .where((f) => f.containsKey('fieldId') && f.containsKey('operator') && f.containsKey('value'))
          .map((f) => FilterModel(
                fieldId: f['fieldId'] as String,
                operator: f['operator'] as String,
                value: f['value'],
              ))
          .toList();
      final filteredRows = _applyFiltersAndSorts(
        state.database.rows,
        filters,
        state.activeSorts,
      );
      final updatedDatabase = DatabaseModel(
        id: state.database.id,
        name: state.database.name,
        fields: state.database.fields,
        rows: filteredRows,
        views: state.database.views,
      );
      emit(state.copyWith(
        database: updatedDatabase,
        activeFilters: filters,
      ));
    }
  }

  /// 应用排序条件
  /// 验证每个排序规则的必填字段（fieldId, direction），再执行过滤和排序
  Future<void> _onApplySorts(ApplySorts event, Emitter<DatabaseState> emit) async {
    final state = this.state;
    if (state is DatabaseDetailLoaded) {
      // 排序器验证：确保每个排序规则包含必填字段
      final sorts = event.sorts
          .where((s) => s.containsKey('fieldId') && s.containsKey('direction'))
          .map((s) => SortModel(
                fieldId: s['fieldId'] as String,
                direction: s['direction'] as String,
              ))
          .toList();
      final filteredRows = _applyFiltersAndSorts(
        state.database.rows,
        state.activeFilters,
        sorts,
      );
      final updatedDatabase = DatabaseModel(
        id: state.database.id,
        name: state.database.name,
        fields: state.database.fields,
        rows: filteredRows,
        views: state.database.views,
      );
      emit(state.copyWith(
        database: updatedDatabase,
        activeSorts: sorts,
      ));
    }
  }

  /// 过滤和排序核心逻辑
  /// 先按过滤条件筛选行，再按排序规则排序
  /// 包含输入验证：rows/filters/sorts 为空时直接返回
  List<DatabaseRowModel> _applyFiltersAndSorts(
    List<DatabaseRowModel> rows,
    List<FilterModel> filters,
    List<SortModel> sorts,
  ) {
    // 输入验证：空数组直接返回
    if (rows == null || rows.isEmpty) return <DatabaseRowModel>[];
    var result = rows.toList();

    // 过滤阶段：按条件逐行筛选
    if (filters != null && filters.isNotEmpty) {
      for (final filter in filters) {
        result = result.where((row) {
          final cell = row.cells.firstWhere(
            (c) => c.fieldId == filter.fieldId,
            orElse: () => DatabaseCellModel(fieldId: filter.fieldId),
          );
          final cellValue = cell.value;
          switch (filter.operator) {
            case 'equals':
              return cellValue == filter.value;
            case 'not_equals':
              return cellValue != filter.value;
            case 'contains':
              return cellValue
                      ?.toString()
                      .contains(filter.value?.toString() ?? '') ??
                  false;
            case 'not_contains':
              return !(cellValue
                      ?.toString()
                      .contains(filter.value?.toString() ?? '') ??
                  false);
            case 'is_empty':
              return cellValue == null || cellValue.toString().isEmpty;
            case 'is_not_empty':
              return cellValue != null && cellValue.toString().isNotEmpty;
            default:
              return true;
          }
        }).toList();
      }
    }

    // 排序阶段：按排序规则逐字段排序
    if (sorts != null && sorts.isNotEmpty) {
      result.sort((a, b) {
        for (final sort in sorts) {
          final aCell = a.cells.firstWhere(
            (c) => c.fieldId == sort.fieldId,
            orElse: () => DatabaseCellModel(fieldId: sort.fieldId),
          );
          final bCell = b.cells.firstWhere(
            (c) => c.fieldId == sort.fieldId,
            orElse: () => DatabaseCellModel(fieldId: sort.fieldId),
          );
          final aVal = aCell.value;
          final bVal = bCell.value;
          int cmp;
          if (aVal == null && bVal == null) {
            cmp = 0;
          } else if (aVal == null) {
            cmp = -1;
          } else if (bVal == null) {
            cmp = 1;
          } else if (aVal is Comparable && bVal is Comparable) {
            cmp = aVal.compareTo(bVal);
          } else {
            cmp = aVal.toString().compareTo(bVal.toString());
          }
          if (cmp != 0) {
            return sort.direction == 'asc' ? cmp : -cmp;
          }
        }
        return 0;
      });
    }

    return result;
  }
}
