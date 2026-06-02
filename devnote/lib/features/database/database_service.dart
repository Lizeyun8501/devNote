import 'package:uuid/uuid.dart';
import 'package:devnote/features/database/bloc/database_state.dart';

class DatabaseService {
  final _uuid = const Uuid();
  final Map<String, _DatabaseStorage> _databases = {};

  Future<DatabaseModel> createDatabase(String name) async {
    final id = _uuid.v4();
    final viewId = _uuid.v4();
    final db = DatabaseModel(
      id: id,
      name: name,
      views: [
        DatabaseViewModel(
          id: viewId,
          name: 'Table View',
          viewType: 'Table',
        ),
      ],
    );
    _databases[id] = _DatabaseStorage(db: db);
    return db;
  }

  Future<void> deleteDatabase(String databaseId) async {
    _databases.remove(databaseId);
  }

  Future<DatabaseModel> getDatabase(String databaseId) async {
    final storage = _databases[databaseId];
    if (storage == null) throw Exception('Database not found');
    return storage.db;
  }

  Future<List<DatabaseModel>> listDatabases() async {
    return _databases.values.map((s) => s.db).toList();
  }

  Future<DatabaseFieldModel> addField({
    required String databaseId,
    required String name,
    required String fieldType,
    Map<String, dynamic> options = const {},
    String? formula,
  }) async {
    final storage = _databases[databaseId];
    if (storage == null) throw Exception('Database not found');
    final field = DatabaseFieldModel(
      id: _uuid.v4(),
      name: name,
      fieldType: fieldType,
      options: options,
      formula: formula,
    );
    storage.db = DatabaseModel(
      id: storage.db.id,
      name: storage.db.name,
      fields: [...storage.db.fields, field],
      rows: storage.db.rows,
      views: storage.db.views,
    );
    return field;
  }

  Future<DatabaseFieldModel> updateField({
    required String databaseId,
    required String fieldId,
    required String name,
    Map<String, dynamic> options = const {},
  }) async {
    final storage = _databases[databaseId];
    if (storage == null) throw Exception('Database not found');
    final fields = storage.db.fields.map((f) {
      if (f.id == fieldId) {
        return DatabaseFieldModel(
          id: f.id,
          name: name,
          fieldType: f.fieldType,
          options: options,
          formula: f.formula,
        );
      }
      return f;
    }).toList();
    storage.db = DatabaseModel(
      id: storage.db.id,
      name: storage.db.name,
      fields: fields,
      rows: storage.db.rows,
      views: storage.db.views,
    );
    return fields.firstWhere((f) => f.id == fieldId);
  }

  Future<void> deleteField({
    required String databaseId,
    required String fieldId,
  }) async {
    final storage = _databases[databaseId];
    if (storage == null) throw Exception('Database not found');
    storage.db = DatabaseModel(
      id: storage.db.id,
      name: storage.db.name,
      fields: storage.db.fields.where((f) => f.id != fieldId).toList(),
      rows: storage.db.rows,
      views: storage.db.views,
    );
  }

  Future<DatabaseRowModel> addRow({
    required String databaseId,
    List<Map<String, dynamic>> cells = const [],
  }) async {
    final storage = _databases[databaseId];
    if (storage == null) throw Exception('Database not found');
    final now = DateTime.now();
    final row = DatabaseRowModel(
      id: _uuid.v4(),
      cells: cells
          .map((c) => DatabaseCellModel(
                fieldId: c['fieldId'] as String,
                value: c['value'],
              ))
          .toList(),
      createdAt: now,
      updatedAt: now,
    );
    storage.db = DatabaseModel(
      id: storage.db.id,
      name: storage.db.name,
      fields: storage.db.fields,
      rows: [...storage.db.rows, row],
      views: storage.db.views,
    );
    return row;
  }

  Future<DatabaseRowModel> updateRow({
    required String databaseId,
    required String rowId,
    required List<Map<String, dynamic>> cells,
  }) async {
    final storage = _databases[databaseId];
    if (storage == null) throw Exception('Database not found');
    final now = DateTime.now();
    final rows = storage.db.rows.map((r) {
      if (r.id == rowId) {
        return DatabaseRowModel(
          id: r.id,
          cells: cells
              .map((c) => DatabaseCellModel(
                    fieldId: c['fieldId'] as String,
                    value: c['value'],
                  ))
              .toList(),
          createdAt: r.createdAt,
          updatedAt: now,
        );
      }
      return r;
    }).toList();
    storage.db = DatabaseModel(
      id: storage.db.id,
      name: storage.db.name,
      fields: storage.db.fields,
      rows: rows,
      views: storage.db.views,
    );
    return rows.firstWhere((r) => r.id == rowId);
  }

  Future<void> deleteRow({
    required String databaseId,
    required String rowId,
  }) async {
    final storage = _databases[databaseId];
    if (storage == null) throw Exception('Database not found');
    storage.db = DatabaseModel(
      id: storage.db.id,
      name: storage.db.name,
      fields: storage.db.fields,
      rows: storage.db.rows.where((r) => r.id != rowId).toList(),
      views: storage.db.views,
    );
  }

  Future<DatabaseCellModel> updateCell({
    required String databaseId,
    required String rowId,
    required String fieldId,
    required dynamic value,
  }) async {
    final storage = _databases[databaseId];
    if (storage == null) throw Exception('Database not found');
    final now = DateTime.now();
    final rows = storage.db.rows.map((r) {
      if (r.id == rowId) {
        final cells = r.cells.where((c) => c.fieldId != fieldId).toList();
        cells.add(DatabaseCellModel(fieldId: fieldId, value: value));
        return DatabaseRowModel(
          id: r.id,
          cells: cells,
          createdAt: r.createdAt,
          updatedAt: now,
        );
      }
      return r;
    }).toList();
    storage.db = DatabaseModel(
      id: storage.db.id,
      name: storage.db.name,
      fields: storage.db.fields,
      rows: rows,
      views: storage.db.views,
    );
    return DatabaseCellModel(fieldId: fieldId, value: value);
  }

  Future<DatabaseViewModel> addView({
    required String databaseId,
    required String name,
    required String viewType,
  }) async {
    final storage = _databases[databaseId];
    if (storage == null) throw Exception('Database not found');
    final view = DatabaseViewModel(
      id: _uuid.v4(),
      name: name,
      viewType: viewType,
    );
    storage.db = DatabaseModel(
      id: storage.db.id,
      name: storage.db.name,
      fields: storage.db.fields,
      rows: storage.db.rows,
      views: [...storage.db.views, view],
    );
    return view;
  }

  Future<void> deleteView({
    required String databaseId,
    required String viewId,
  }) async {
    final storage = _databases[databaseId];
    if (storage == null) throw Exception('Database not found');
    storage.db = DatabaseModel(
      id: storage.db.id,
      name: storage.db.name,
      fields: storage.db.fields,
      rows: storage.db.rows,
      views: storage.db.views.where((v) => v.id != viewId).toList(),
    );
  }
}

class _DatabaseStorage {
  DatabaseModel db;

  _DatabaseStorage({required this.db});
}
