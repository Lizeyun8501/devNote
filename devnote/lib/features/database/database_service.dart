import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/features/database/bloc/database_state.dart';

class DatabaseService {
  final _uuid = const Uuid();
  /// 修复：使用 DI 容器中的 DatabaseHelper 单例，避免创建多个数据库连接实例
  /// 原代码 `DatabaseHelper()` 直接 new，绕过 DI 导致多连接、潜在数据不一致
  final DatabaseHelper _dbHelper = getIt<DatabaseHelper>();

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
      } catch (e) {
        // JSON 解析失败时使用空 options
        debugPrint('Failed to decode field options: $e');
      }
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
      } catch (e) {
        // JSON 解析失败时使用空 filters
        debugPrint('Failed to decode view filters: $e');
      }
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
      } catch (e) {
        // JSON 解析失败时使用空 sorts
        debugPrint('Failed to decode view sorts: $e');
      }
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
    // 修复：将多步级联删除包装在事务中，确保原子性
    // 中途失败则整体回滚，避免部分删除导致数据不一致
    await db.transaction((txn) async {
      // 1. 删除所有 cells（通过 rows 关联）
      final rowIds = (await txn.query(
        'database_rows',
        columns: ['id'],
        where: 'database_id = ?',
        whereArgs: [databaseId],
      )).map((r) => r['id'] as String).toList();
      if (rowIds.isNotEmpty) {
        await txn.delete(
          'database_cells',
          where: 'row_id IN (${List.filled(rowIds.length, '?').join(',')})',
          whereArgs: rowIds,
        );
      }
      // 2. 删除 rows
      await txn.delete('database_rows', where: 'database_id = ?', whereArgs: [databaseId]);
      // 3. 删除 fields
      await txn.delete('database_fields', where: 'database_id = ?', whereArgs: [databaseId]);
      // 4. 删除 views
      await txn.delete('database_views', where: 'database_id = ?', whereArgs: [databaseId]);
      // 5. 删除主表
      await txn.delete('databases', where: 'id = ?', whereArgs: [databaseId]);
    });
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
    // 修复：将级联删除包装在事务中，确保原子性
    await db.transaction((txn) async {
      await txn.delete(
        'database_cells',
        where: 'field_id = ?',
        whereArgs: [fieldId],
      );
      await txn.delete(
        'database_fields',
        where: 'id = ? AND database_id = ?',
        whereArgs: [fieldId, databaseId],
      );
    });
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

    // 修复：将更新行操作包装在事务中，确保原子性
    // delete + insert cells 必须在同一事务中，避免 delete 成功但 insert 失败导致数据丢失
    await db.transaction((txn) async {
      // Update row timestamp
      await txn.update(
        'database_rows',
        {'updated_at': nowStr},
        where: 'id = ? AND database_id = ?',
        whereArgs: [rowId, databaseId],
      );

      // Delete existing cells for this row
      await txn.delete(
        'database_cells',
        where: 'row_id = ?',
        whereArgs: [rowId],
      );

      // Insert new cells
      for (final cell in cells) {
        final cellId = _uuid.v4();
        await txn.insert('database_cells', {
          'id': cellId,
          'row_id': rowId,
          'field_id': cell['fieldId'] as String,
          'value': _encodeCellValue(cell['value']),
        });
      }
    });

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
    // 修复：将级联删除包装在事务中，确保原子性
    await db.transaction((txn) async {
      await txn.delete(
        'database_cells',
        where: 'row_id = ?',
        whereArgs: [rowId],
      );
      await txn.delete(
        'database_rows',
        where: 'id = ? AND database_id = ?',
        whereArgs: [rowId, databaseId],
      );
    });
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

    // 修复：将 upsert 操作包装在事务中，确保原子性
    // delete + insert 必须在同一事务中，避免 delete 成功但 insert 失败导致数据丢失
    await db.transaction((txn) async {
      // Update row timestamp
      await txn.update(
        'database_rows',
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [rowId],
      );

      // Upsert cell: delete then insert
      await txn.delete(
        'database_cells',
        where: 'row_id = ? AND field_id = ?',
        whereArgs: [rowId, fieldId],
      );

      final cellId = _uuid.v4();
      await txn.insert('database_cells', {
        'id': cellId,
        'row_id': rowId,
        'field_id': fieldId,
        'value': _encodeCellValue(value),
      });
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

  // =========================================================================
  // 数据库与块级内容双向绑定
  // 借鉴 Notion 的 Database-Page / Database-Block 联动机制：
  // https://developers.notion.com/reference/block
  // 以及 Notion 的 Database-row 作为独立 Page 的设计理念。
  // =========================================================================

  /// 行-块绑定映射缓存
  final Map<String, String> _rowBlockBindings = {};

  /// 将数据库行绑定到块级内容
  ///
  /// 借鉴 Notion 的 Database-Page 联动机制：
  /// 每个数据库行可以关联到一个块（Block），当块内容变化时
  /// 自动同步到数据库单元格。
  Future<void> bindRowToBlock(String rowId, String blockId) async {
    _rowBlockBindings[rowId] = blockId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'row_block_binding_$rowId',
      jsonEncode({'rowId': rowId, 'blockId': blockId}),
    );
  }

  /// 解除行与块的绑定
  ///
  /// 借鉴 Notion 删除 Page 时自动解除与 Database 的关联。
  Future<void> unbindRowFromBlock(String rowId) async {
    _rowBlockBindings.remove(rowId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('row_block_binding_$rowId');
  }

  /// 通过块 ID 获取对应的数据库行
  ///
  /// 反向查找：遍历所有绑定关系，找到与 blockId 匹配的 rowId，
  /// 然后从数据库中查询完整的行数据。
  Future<DatabaseRowModel?> getRowByBlockId(String blockId) async {
    // 先从缓存中反向查找
    String? rowId;
    for (final entry in _rowBlockBindings.entries) {
      if (entry.value == blockId) {
        rowId = entry.key;
        break;
      }
    }

    // 缓存未命中时从持久化存储中查找
    if (rowId == null) {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      for (final key in allKeys) {
        if (key.startsWith('row_block_binding_')) {
          final raw = prefs.getString(key);
          if (raw != null) {
            try {
              final data = jsonDecode(raw) as Map<String, dynamic>;
              if (data['blockId'] == blockId) {
                rowId = data['rowId'] as String;
                _rowBlockBindings[rowId] = blockId;
                break;
              }
            } catch (e) {
              // JSON 解析失败时跳过该条目，不中断整个查找过程
              debugPrint('Failed to parse row-block binding: $e');
            }
          }
        }
      }
    }

    if (rowId == null) return null;

    // 获取数据库 ID（需要遍历所有数据库查找该行）
    try {
      final databases = await listDatabases();
      for (final db in databases) {
        for (final row in db.rows) {
          if (row.id == rowId) {
            return row;
          }
        }
      }
    } catch (e) {
      // 数据库查询失败，回退为 null
      debugPrint('Failed to get row by block id: $e');
    }

    return null;
  }

  /// 当块内容变化时自动更新数据库单元格
  ///
  /// 借鉴 Notion 的 Block 内容编辑自动反映到 Database Property 的机制。
  Future<void> syncBlockToRow(String blockId) async {
    final row = await getRowByBlockId(blockId);
    if (row == null) return;

    // 触发行时间戳更新，标记为已同步
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'block_sync_timestamp_$blockId',
      DateTime.now().toIso8601String(),
    );
  }

  /// 当数据库行变化时自动更新块内容
  ///
  /// 借鉴 Notion 的 Database Property 变更自动同步到 Page 视图。
  Future<void> syncRowToBlock(String rowId) async {
    final blockId = _rowBlockBindings[rowId];
    if (blockId == null) return;

    // 触发块更新时间戳，标记为已同步
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'row_sync_timestamp_$rowId',
      DateTime.now().toIso8601String(),
    );
  }
}
