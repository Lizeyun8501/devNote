import 'package:equatable/equatable.dart';

class DatabaseModel extends Equatable {
  final String id;
  final String name;
  final List<DatabaseFieldModel> fields;
  final List<DatabaseRowModel> rows;
  final List<DatabaseViewModel> views;

  const DatabaseModel({
    required this.id,
    required this.name,
    this.fields = const [],
    this.rows = const [],
    this.views = const [],
  });

  @override
  List<Object?> get props => [id, name, fields, rows, views];
}

class DatabaseFieldModel extends Equatable {
  final String id;
  final String name;
  final String fieldType;
  final Map<String, dynamic> options;
  final String? formula;

  const DatabaseFieldModel({
    required this.id,
    required this.name,
    required this.fieldType,
    this.options = const {},
    this.formula,
  });

  @override
  List<Object?> get props => [id, name, fieldType, options, formula];
}

class DatabaseRowModel extends Equatable {
  final String id;
  final List<DatabaseCellModel> cells;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DatabaseRowModel({
    required this.id,
    this.cells = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [id, cells, createdAt, updatedAt];
}

class DatabaseCellModel extends Equatable {
  final String fieldId;
  final dynamic value;

  const DatabaseCellModel({
    required this.fieldId,
    this.value,
  });

  @override
  List<Object?> get props => [fieldId, value];
}

class DatabaseViewModel extends Equatable {
  final String id;
  final String name;
  final String viewType;
  final List<FilterModel> filters;
  final List<SortModel> sorts;
  final String? groupBy;
  final List<FieldOrderModel> fieldOrders;

  const DatabaseViewModel({
    required this.id,
    required this.name,
    required this.viewType,
    this.filters = const [],
    this.sorts = const [],
    this.groupBy,
    this.fieldOrders = const [],
  });

  @override
  List<Object?> get props => [id, name, viewType, filters, sorts, groupBy, fieldOrders];
}

class FilterModel extends Equatable {
  final String fieldId;
  final String operator;
  final dynamic value;

  const FilterModel({
    required this.fieldId,
    required this.operator,
    this.value,
  });

  @override
  List<Object?> get props => [fieldId, operator, value];
}

class SortModel extends Equatable {
  final String fieldId;
  final String direction;

  const SortModel({
    required this.fieldId,
    required this.direction,
  });

  @override
  List<Object?> get props => [fieldId, direction];
}

class FieldOrderModel extends Equatable {
  final String fieldId;
  final int position;

  const FieldOrderModel({
    required this.fieldId,
    required this.position,
  });

  @override
  List<Object?> get props => [fieldId, position];
}

sealed class DatabaseState {
  const DatabaseState();
}

final class DatabaseInitial extends DatabaseState {
  const DatabaseInitial();
}

final class DatabaseLoading extends DatabaseState {
  const DatabaseLoading();
}

final class DatabaseListLoaded extends DatabaseState {
  final List<DatabaseModel> databases;

  const DatabaseListLoaded(this.databases);
}

final class DatabaseDetailLoaded extends DatabaseState {
  final DatabaseModel database;
  final List<DatabaseRowModel> originalRows;
  final List<FilterModel> activeFilters;
  final List<SortModel> activeSorts;

  const DatabaseDetailLoaded({
    required this.database,
    this.originalRows = const [],
    this.activeFilters = const [],
    this.activeSorts = const [],
  });

  DatabaseDetailLoaded copyWith({
    DatabaseModel? database,
    List<DatabaseRowModel>? originalRows,
    List<FilterModel>? activeFilters,
    List<SortModel>? activeSorts,
  }) {
    return DatabaseDetailLoaded(
      database: database ?? this.database,
      originalRows: originalRows ?? this.originalRows,
      activeFilters: activeFilters ?? this.activeFilters,
      activeSorts: activeSorts ?? this.activeSorts,
    );
  }
}

final class DatabaseError extends DatabaseState {
  final String message;

  const DatabaseError(this.message);
}
