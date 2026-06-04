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
      emit(state.copyWith(activeFilters: filters));
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
      emit(state.copyWith(activeSorts: sorts));
    }
  }
}
