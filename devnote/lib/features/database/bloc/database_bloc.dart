import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/database/bloc/database_event.dart';
import 'package:devnote/features/database/bloc/database_state.dart';
import 'package:devnote/features/database/database_service.dart';

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

  Future<void> _onLoadDatabases(LoadDatabases event, Emitter<DatabaseState> emit) async {
    emit(const DatabaseLoading());
    try {
      final databases = await _databaseService.listDatabases();
      emit(DatabaseListLoaded(databases));
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

  Future<void> _onCreateDatabase(CreateDatabase event, Emitter<DatabaseState> emit) async {
    try {
      await _databaseService.createDatabase(event.name);
      final databases = await _databaseService.listDatabases();
      emit(DatabaseListLoaded(databases));
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

  Future<void> _onDeleteDatabase(DeleteDatabase event, Emitter<DatabaseState> emit) async {
    try {
      await _databaseService.deleteDatabase(event.databaseId);
      final databases = await _databaseService.listDatabases();
      emit(DatabaseListLoaded(databases));
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

  Future<void> _onLoadDatabaseDetail(LoadDatabaseDetail event, Emitter<DatabaseState> emit) async {
    emit(const DatabaseLoading());
    try {
      final database = await _databaseService.getDatabase(event.databaseId);
      emit(DatabaseDetailLoaded(database: database));
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

  Future<void> _onAddField(AddField event, Emitter<DatabaseState> emit) async {
    try {
      await _databaseService.addField(
        databaseId: event.databaseId,
        name: event.name,
        fieldType: event.fieldType,
        options: event.options,
        formula: event.formula,
      );
      final database = await _databaseService.getDatabase(event.databaseId);
      emit(DatabaseDetailLoaded(database: database));
    } catch (e) {
      emit(DatabaseError(e.toString()));
    }
  }

  Future<void> _onUpdateField(UpdateField event, Emitter<DatabaseState> emit) async {
    try {
      await _databaseService.updateField(
        databaseId: event.databaseId,
        fieldId: event.fieldId,
        name: event.name,
        options: event.options,
      );
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

  Future<void> _onDeleteField(DeleteField event, Emitter<DatabaseState> emit) async {
    try {
      await _databaseService.deleteField(
        databaseId: event.databaseId,
        fieldId: event.fieldId,
      );
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

  Future<void> _onAddRow(AddRow event, Emitter<DatabaseState> emit) async {
    try {
      await _databaseService.addRow(
        databaseId: event.databaseId,
        cells: event.cells,
      );
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

  Future<void> _onUpdateCell(UpdateCell event, Emitter<DatabaseState> emit) async {
    try {
      await _databaseService.updateCell(
        databaseId: event.databaseId,
        rowId: event.rowId,
        fieldId: event.fieldId,
        value: event.value,
      );
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

  Future<void> _onDeleteRow(DeleteRow event, Emitter<DatabaseState> emit) async {
    try {
      await _databaseService.deleteRow(
        databaseId: event.databaseId,
        rowId: event.rowId,
      );
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

  Future<void> _onAddView(AddView event, Emitter<DatabaseState> emit) async {
    try {
      await _databaseService.addView(
        databaseId: event.databaseId,
        name: event.name,
        viewType: event.viewType,
      );
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

  Future<void> _onDeleteView(DeleteView event, Emitter<DatabaseState> emit) async {
    try {
      await _databaseService.deleteView(
        databaseId: event.databaseId,
        viewId: event.viewId,
      );
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

  Future<void> _onApplyFilters(ApplyFilters event, Emitter<DatabaseState> emit) async {
    final state = this.state;
    if (state is DatabaseDetailLoaded) {
      final filters = event.filters
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

  Future<void> _onApplySorts(ApplySorts event, Emitter<DatabaseState> emit) async {
    final state = this.state;
    if (state is DatabaseDetailLoaded) {
      final sorts = event.sorts
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

  List<DatabaseRowModel> _applyFiltersAndSorts(
    List<DatabaseRowModel> rows,
    List<FilterModel> filters,
    List<SortModel> sorts,
  ) {
    var result = rows.toList();

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

    if (sorts.isNotEmpty) {
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
