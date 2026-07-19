import 'package:equatable/equatable.dart';

abstract class DatabaseEvent extends Equatable {
  const DatabaseEvent();

  @override
  List<Object?> get props => [];
}

class LoadDatabases extends DatabaseEvent {
  const LoadDatabases();
}

class CreateDatabase extends DatabaseEvent {
  final String name;

  const CreateDatabase(this.name);

  @override
  List<Object?> get props => [name];
}

class DeleteDatabase extends DatabaseEvent {
  final String databaseId;

  const DeleteDatabase(this.databaseId);

  @override
  List<Object?> get props => [databaseId];
}

class LoadDatabaseDetail extends DatabaseEvent {
  final String databaseId;

  const LoadDatabaseDetail(this.databaseId);

  @override
  List<Object?> get props => [databaseId];
}

class AddField extends DatabaseEvent {
  final String databaseId;
  final String name;
  final String fieldType;
  final Map<String, dynamic> options;
  final String? formula;

  const AddField({
    required this.databaseId,
    required this.name,
    required this.fieldType,
    this.options = const {},
    this.formula,
  });

  @override
  List<Object?> get props => [databaseId, name, fieldType, options, formula];
}

class UpdateField extends DatabaseEvent {
  final String databaseId;
  final String fieldId;
  final String name;
  final Map<String, dynamic> options;

  const UpdateField({
    required this.databaseId,
    required this.fieldId,
    required this.name,
    this.options = const {},
  });

  @override
  List<Object?> get props => [databaseId, fieldId, name, options];
}

class DeleteField extends DatabaseEvent {
  final String databaseId;
  final String fieldId;

  const DeleteField({
    required this.databaseId,
    required this.fieldId,
  });

  @override
  List<Object?> get props => [databaseId, fieldId];
}

class AddRow extends DatabaseEvent {
  final String databaseId;
  final List<Map<String, dynamic>> cells;

  const AddRow({
    required this.databaseId,
    this.cells = const [],
  });

  @override
  List<Object?> get props => [databaseId, cells];
}

class UpdateCell extends DatabaseEvent {
  final String databaseId;
  final String rowId;
  final String fieldId;
  final dynamic value;

  const UpdateCell({
    required this.databaseId,
    required this.rowId,
    required this.fieldId,
    required this.value,
  });

  @override
  List<Object?> get props => [databaseId, rowId, fieldId, value];
}

class DeleteRow extends DatabaseEvent {
  final String databaseId;
  final String rowId;

  const DeleteRow({
    required this.databaseId,
    required this.rowId,
  });

  @override
  List<Object?> get props => [databaseId, rowId];
}

class AddView extends DatabaseEvent {
  final String databaseId;
  final String name;
  final String viewType;

  const AddView({
    required this.databaseId,
    required this.name,
    required this.viewType,
  });

  @override
  List<Object?> get props => [databaseId, name, viewType];
}

class DeleteView extends DatabaseEvent {
  final String databaseId;
  final String viewId;

  const DeleteView({
    required this.databaseId,
    required this.viewId,
  });

  @override
  List<Object?> get props => [databaseId, viewId];
}

class ApplyFilters extends DatabaseEvent {
  final String databaseId;
  final List<Map<String, dynamic>> filters;

  const ApplyFilters({
    required this.databaseId,
    required this.filters,
  });

  @override
  List<Object?> get props => [databaseId, filters];
}

class ApplySorts extends DatabaseEvent {
  final String databaseId;
  final List<Map<String, dynamic>> sorts;

  const ApplySorts({
    required this.databaseId,
    required this.sorts,
  });

  @override
  List<Object?> get props => [databaseId, sorts];
}

class ClearFilters extends DatabaseEvent {
  final String databaseId;

  const ClearFilters({required this.databaseId});

  @override
  List<Object?> get props => [databaseId];
}

class ClearSorts extends DatabaseEvent {
  final String databaseId;

  const ClearSorts({required this.databaseId});

  @override
  List<Object?> get props => [databaseId];
}
