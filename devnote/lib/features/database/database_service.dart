import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/features/database/bloc/database_state.dart';

class DatabaseService {
  final _uuid = const Uuid();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // -- Helper methods to map rows to models --

  DatabaseModel _mapDatabase(Map<String, dynamic> row,
      {List<DatabaseFieldModel> fields = const [],
      List<DatabaseRowModel> rows = const [],
      List<DatabaseViewModel> views = const []}) {
    return DatabaseModel(
      id: row['id'] as String,
      name: row['name'] as String,
      fields: fields,
      rows: rows,
      views: views,
    );
  }

  DatabaseFieldModel _mapField(Map<String, dynamic> row) {
    Map<String, dynamic> options = {};
    if (row['options'] != null) {
      try {
        options = Map<String, dynamic>.from(jsonDecode(row['options'] as String));
      } catch (_) {}
    }
    return DatabaseFieldModel(
      id: row['id'] as String,
      name: row['name'] as String,
      fieldType: row['field_type'] as String,
      options: options,
      formula: row['formula'] as String?,
    );
  }

  DatabaseViewModel _mapView(Map<String, dynamic> row) {
    List<FilterModel> filters = [];
    if (row['filters'] != null) {
      try {
        final list = jsonDecode(row['filters'] as String) as List;
        filters = list
            .map((f) => FilterModel(
                  fieldId: f['fieldId'] as String,
                  operator: f['operator'] as String,
                  value: f['value'],
                ))
            .toList();
      } catch (_) {}
    }
    List<SortModel> sorts = [];
    if (row['sorts'] != null) {
      try {
        final list = jsonDecode(row['sorts'] as String) as List;
        sorts = list
            .map((s) => SortModel(
                  fieldId: s['fieldId'] as String,
                  direction: s['direction'] as String,
                ))
            .toList();
      } catch (_) {}
    }
    return DatabaseViewModel(
      id: row['id'] as String,
      name: row['name'] as String,
      viewType: row['view_type'] as String,
      filters: filters,
      sorts: sorts,
    );
  }

  Future<List<DatabaseFieldModel>> _getFields(String databaseId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'database_fields',
      where: 'database_id = ?',
      whereArgs: [databaseId],
      orderBy: 'position ASC',
    );
    return rows.map(_mapField).toList();
  }

  Future<List<DatabaseRowModel>> _getRows(String databaseId) async {
    final db = await _dbHelper.database;
    final rowRecords = await db.query(
      'database_rows',
      where: 'database_id = ?',
      whereArgs: [databaseId],
      orderBy: 'created_at ASC',
    );
    final rowIds = rowRecords.map((r) => r['id'] as String).toList();
    if (rowIds.isEmpty) return [];

    final cellRecords = await db.query(
      'database_cells',
      where: 'row_id IN (${List.filled(rowIds.length, '?').join(',')})',
      whereArgs: rowIds,
    );
    final cellsByRow = <String, List<DatabaseCellModel>>{};
    for (final cell in cellRecords) {
      final rowId = cell['row_id'] as String;
      cellsByRow.putIfAbsent(rowId, () => []);
      cellsByRow[rowId]!.add(DatabaseCellModel(
        fieldId: cell['field_id'] as String,
        value: _decodeCellValue(cell['value'] as String?),
      ));
    }
    return rowRecords.map((r) {
      final id = r['id'] as String;
      return DatabaseRowModel(
        id: id,
        cells: cellsByRow[id] ?? [],
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
      );
    }).toList();
  }

  Future<List<DatabaseViewModel>> _getViews(String databaseId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'database_views',
      where: 'database_id = ?',
      whereArgs: [databaseId],
      orderBy: 'created_at ASC',
    );
    return rows.map(_mapView).toList();
  }

  Future<DatabaseModel> _getFullDatabase(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final fields = await _getFields(id);
    final rows = await _getRows(id);
    final views = await _getViews(id);
    return _mapDatabase(row, fields: fields, rows: rows, views: views);
  }

  static dynamic _decodeCellValue(String? raw) {
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  static String _encodeCellValue(dynamic value) {
    if (value == null) return jsonEncode(null);
    return jsonEncode(value);
  }

  // -- Public API --

  Future<DatabaseModel> createDatabase(String name) async {
    final id = _uuid.v4();
    final viewId = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final db = await _dbHelper.database;

    await db.insert('databases', {
      'id': id,
      'name': name,
      'created_at': now,
      'updated_at': now,
    });

    await db.insert('database_views', {
      'id': viewId,
      'database_id': id,
      'name': 'Table View',
      'view_type': 'Table',
      'created_at': now,
    });

    return _mapDatabase({
      'id': id,
      'name': name,
      'created_at': now,
      'updated_at': now,
    }, views: [
      DatabaseViewModel(
        id: viewId,
        name: 'Table View',
        viewType: 'Table',
      ),
    ]);
  }

  Future<void> deleteDatabase(String databaseId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'databases',
      where: 'id = ?',
      whereArgs: [databaseId],
    );
  }

  Future<DatabaseModel> getDatabase(String databaseId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'databases',
      where: 'id = ?',
      whereArgs: [databaseId],
    );
    if (rows.isEmpty) throw Exception('Database not found');
    return _getFullDatabase(rows.first);
  }

  Future<List<DatabaseModel>> listDatabases() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'databases',
      orderBy: 'created_at DESC',
    );
    return Future.wait(rows.map(_getFullDatabase));
  }

  Future<DatabaseFieldModel> addField({
    required String databaseId,
    required String name,
    required String fieldType,
    Map<String, dynamic> options = const {},
    String? formula,
  }) async {
    // Verify database exists
    await getDatabase(databaseId);

    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final db = await _dbHelper.database;

    // Get max position
    final existing = await db.query(
      'database_fields',
      columns: ['MAX(position) as max_pos'],
      where: 'database_id = ?',
      whereArgs: [databaseId],
    );
    final maxPos = (existing.first['max_pos'] as int?) ?? -1;

    await db.insert('database_fields', {
      'id': id,
      'database_id': databaseId,
      'name': name,
      'field_type': fieldType,
      'options': jsonEncode(options),
      'formula': formula,
      'position': maxPos + 1,
      'created_at': now,
    });

    return DatabaseFieldModel(
      id: id,
      name: name,
      fieldType: fieldType,
      options: options,
      formula: formula,
    );
  }

  Future<DatabaseFieldModel> updateField({
    required String databaseId,
    required String fieldId,
    required String name,
    Map<String, dynamic> options = const {},
  }) async {
    // Verify database exists
    await getDatabase(databaseId);

    final db = await _dbHelper.database;
    await db.update(
      'database_fields',
      {
        'name': name,
        'options': jsonEncode(options),
      },
      where: 'id = ? AND database_id = ?',
      whereArgs: [fieldId, databaseId],
    );

    // Re-read from DB to get accurate fieldType
    final rows = await db.query(
      'database_fields',
      where: 'id = ?',
      whereArgs: [fieldId],
    );
    if (rows.isEmpty) throw Exception('Field not found');
    return _mapField(rows.first);
  }

  Future<void> deleteField({
    required String databaseId,
    required String fieldId,
  }) async {
    // Verify database exists
    await getDatabase(databaseId);

    final db = await _dbHelper.database;
    await db.delete(
      'database_fields',
      where: 'id = ? AND database_id = ?',
      whereArgs: [fieldId, databaseId],
    );
  }

  Future<DatabaseRowModel> addRow({
    required String databaseId,
    List<Map<String, dynamic>> cells = const [],
  }) async {
    // Verify database exists
    await getDatabase(databaseId);

    final id = _uuid.v4();
    final now = DateTime.now();
    final nowStr = now.toIso8601String();
    final db = await _dbHelper.database;

    await db.insert('database_rows', {
      'id': id,
      'database_id': databaseId,
      'created_at': nowStr,
      'updated_at': nowStr,
    });

    for (final cell in cells) {
      final cellId = _uuid.v4();
      await db.insert('database_cells', {
        'id': cellId,
        'row_id': id,
        'field_id': cell['fieldId'] as String,
        'value': _encodeCellValue(cell['value']),
      });
    }

    final cellModels = cells
        .map((c) => DatabaseCellModel(
              fieldId: c['fieldId'] as String,
              value: c['value'],
            ))
        .toList();

    return DatabaseRowModel(
      id: id,
      cells: cellModels,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<DatabaseRowModel> updateRow({
    required String databaseId,
    required String rowId,
    required List<Map<String, dynamic>> cells,
  }) async {
    // Verify database exists
    await getDatabase(databaseId);

    final now = DateTime.now();
    final nowStr = now.toIso8601String();
    final db = await _dbHelper.database;

    // Update row timestamp
    await db.update(
      'database_rows',
      {'updated_at': nowStr},
      where: 'id = ? AND database_id = ?',
      whereArgs: [rowId, databaseId],
    );

    // Delete existing cells for this row
    await db.delete(
      'database_cells',
      where: 'row_id = ?',
      whereArgs: [rowId],
    );

    // Insert new cells
    for (final cell in cells) {
      final cellId = _uuid.v4();
      await db.insert('database_cells', {
        'id': cellId,
        'row_id': rowId,
        'field_id': cell['fieldId'] as String,
        'value': _encodeCellValue(cell['value']),
      });
    }

    final cellModels = cells
        .map((c) => DatabaseCellModel(
              fieldId: c['fieldId'] as String,
              value: c['value'],
            ))
        .toList();

    // Get original created_at
    final rowRecords = await db.query(
      'database_rows',
      where: 'id = ?',
      whereArgs: [rowId],
    );
    final createdAt = rowRecords.isNotEmpty
        ? DateTime.parse(rowRecords.first['created_at'] as String)
        : now;

    return DatabaseRowModel(
      id: rowId,
      cells: cellModels,
      createdAt: createdAt,
      updatedAt: now,
    );
  }

  Future<void> deleteRow({
    required String databaseId,
    required String rowId,
  }) async {
    // Verify database exists
    await getDatabase(databaseId);

    final db = await _dbHelper.database;
    await db.delete(
      'database_rows',
      where: 'id = ? AND database_id = ?',
      whereArgs: [rowId, databaseId],
    );
  }

  Future<DatabaseCellModel> updateCell({
    required String databaseId,
    required String rowId,
    required String fieldId,
    required dynamic value,
  }) async {
    // Verify database exists
    await getDatabase(databaseId);

    final now = DateTime.now().toIso8601String();
    final db = await _dbHelper.database;

    // Update row timestamp
    await db.update(
      'database_rows',
      {'updated_at': now},
      where: 'id = ?',
      whereArgs: [rowId],
    );

    // Upsert cell: delete then insert
    await db.delete(
      'database_cells',
      where: 'row_id = ? AND field_id = ?',
      whereArgs: [rowId, fieldId],
    );

    final cellId = _uuid.v4();
    await db.insert('database_cells', {
      'id': cellId,
      'row_id': rowId,
      'field_id': fieldId,
      'value': _encodeCellValue(value),
    });

    return DatabaseCellModel(fieldId: fieldId, value: value);
  }

  Future<DatabaseViewModel> addView({
    required String databaseId,
    required String name,
    required String viewType,
  }) async {
    // Verify database exists
    await getDatabase(databaseId);

    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final db = await _dbHelper.database;

    await db.insert('database_views', {
      'id': id,
      'database_id': databaseId,
      'name': name,
      'view_type': viewType,
      'created_at': now,
    });

    return DatabaseViewModel(
      id: id,
      name: name,
      viewType: viewType,
    );
  }

  Future<void> deleteView({
    required String databaseId,
    required String viewId,
  }) async {
    // Verify database exists
    await getDatabase(databaseId);

    final db = await _dbHelper.database;
    await db.delete(
      'database_views',
      where: 'id = ? AND database_id = ?',
      whereArgs: [viewId, databaseId],
    );
  }
}
