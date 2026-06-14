import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/persistence/database_helper.dart';

class ObjectTypeModel {
  final String id;
  final String name;
  final String icon;
  final List<ObjectPropertyModel> properties;
  final List<ObjectRelationModel> relations;

  const ObjectTypeModel({
    required this.id,
    required this.name,
    this.icon = '',
    this.properties = const [],
    this.relations = const [],
  });

  ObjectTypeModel copyWith({
    String? id,
    String? name,
    String? icon,
    List<ObjectPropertyModel>? properties,
    List<ObjectRelationModel>? relations,
  }) {
    return ObjectTypeModel(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      properties: properties ?? this.properties,
      relations: relations ?? this.relations,
    );
  }
}

class ObjectPropertyModel {
  final String id;
  final String name;
  final String propertyType;
  final Map<String, dynamic> format;

  const ObjectPropertyModel({
    required this.id,
    required this.name,
    required this.propertyType,
    this.format = const {},
  });
}

class ObjectRelationModel {
  final String id;
  final String name;
  final String relationType;
  final String sourceType;
  final String targetType;

  const ObjectRelationModel({
    required this.id,
    required this.name,
    required this.relationType,
    required this.sourceType,
    required this.targetType,
  });
}

class ObjectModel {
  final String id;
  final String objectTypeId;
  final Map<String, dynamic> properties;
  final List<String> relations;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ObjectModel({
    required this.id,
    required this.objectTypeId,
    this.properties = const {},
    this.relations = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  ObjectModel copyWith({
    String? id,
    String? objectTypeId,
    Map<String, dynamic>? properties,
    List<String>? relations,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ObjectModel(
      id: id ?? this.id,
      objectTypeId: objectTypeId ?? this.objectTypeId,
      properties: properties ?? this.properties,
      relations: relations ?? this.relations,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ObjectService {
  final DatabaseHelper _dbHelper;
  final _uuid = const Uuid();

  /// 修复：默认使用 DI 容器中的 DatabaseHelper 单例，避免创建多个数据库连接实例
  ObjectService([DatabaseHelper? dbHelper]) : _dbHelper = dbHelper ?? getIt<DatabaseHelper>();

  Future<ObjectTypeModel> createObjectType(String name, String icon, List<ObjectPropertyModel> properties) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert('object_types', {
        'id': id,
        'name': name,
        'icon': icon,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      for (var i = 0; i < properties.length; i++) {
        final p = properties[i];
        await txn.insert('object_properties', {
          'id': p.id.isEmpty ? _uuid.v4() : p.id,
          'type_id': id,
          'name': p.name,
          'property_type': p.propertyType,
          'format': jsonEncode(p.format),
          'position': i,
        });
      }
    });
    return ObjectTypeModel(
      id: id,
      name: name,
      icon: icon,
      properties: properties,
    );
  }

  Future<ObjectTypeModel> updateObjectType(String typeId, String name, String icon) async {
    final db = await _dbHelper.database;
    final results = await db.query('object_types', where: 'id = ?', whereArgs: [typeId]);
    if (results.isEmpty) throw Exception('Object type not found');
    final now = DateTime.now();
    await db.update(
      'object_types',
      {
        'name': name,
        'icon': icon,
        'updated_at': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [typeId],
    );
    return _loadObjectType(typeId);
  }

  Future<void> deleteObjectType(String typeId) async {
    final db = await _dbHelper.database;
    // 修复：级联删除对象类型及其所有关联数据
    // 虽然 schema 定义了 ON DELETE CASCADE，但需要确保删除顺序正确且在事务中执行
    // 1. 先删除引用 objects 的 object_relations（source_id/target_id）
    // 2. 再删除该类型下的所有 objects（CASCADE 会删 object_properties, object_relations_definitions）
    // 3. 最后删除 object_types（CASCADE 会删 object_properties, object_relations_definitions）
    await db.transaction((txn) async {
      // 获取该类型下所有对象 ID
      final objectRows = await txn.query(
        'objects',
        columns: ['id'],
        where: 'type_id = ?',
        whereArgs: [typeId],
      );
      final objectIds = objectRows.map((r) => r['id'] as String).toList();
      // 删除引用这些对象的关系记录
      if (objectIds.isNotEmpty) {
        final placeholders = List.filled(objectIds.length, '?').join(',');
        await txn.delete(
          'object_relations',
          where: 'source_id IN ($placeholders) OR target_id IN ($placeholders)',
          whereArgs: [...objectIds, ...objectIds],
        );
      }
      // 删除该类型下的所有对象
      await txn.delete('objects', where: 'type_id = ?', whereArgs: [typeId]);
      // 删除关系定义
      await txn.delete('object_relations_definitions', where: 'type_id = ?', whereArgs: [typeId]);
      // 删除属性
      await txn.delete('object_properties', where: 'type_id = ?', whereArgs: [typeId]);
      // 最后删除类型本身
      await txn.delete('object_types', where: 'id = ?', whereArgs: [typeId]);
    });
  }

  Future<List<ObjectTypeModel>> listObjectTypes() async {
    final db = await _dbHelper.database;
    final results = await db.query('object_types', orderBy: 'name');
    final types = <ObjectTypeModel>[];
    for (final row in results) {
      types.add(await _hydrateObjectType(row));
    }
    return types;
  }

  Future<ObjectModel> createObject(String typeId, Map<String, dynamic> properties) async {
    final db = await _dbHelper.database;
    final typeRows = await db.query('object_types', where: 'id = ?', whereArgs: [typeId], limit: 1);
    if (typeRows.isEmpty) throw Exception('Object type not found');
    final id = _uuid.v4();
    final now = DateTime.now();
    await db.insert('objects', {
      'id': id,
      'type_id': typeId,
      'properties': jsonEncode(properties),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    return ObjectModel(
      id: id,
      objectTypeId: typeId,
      properties: properties,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<ObjectModel?> updateObject(String objectId, Map<String, dynamic> properties) async {
    final db = await _dbHelper.database;
    final rows = await db.query('objects', where: 'id = ?', whereArgs: [objectId], limit: 1);
    if (rows.isEmpty) throw Exception('Object not found');
    final now = DateTime.now();
    await db.update(
      'objects',
      {
        'properties': jsonEncode(properties),
        'updated_at': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [objectId],
    );
    return _loadObject(objectId);
  }

  Future<void> deleteObject(String objectId) async {
    final db = await _dbHelper.database;
    // 修复：级联删除对象及其关联的关系记录
    // object_relations 引用了 objects.id，需要先删除关系再删除对象
    await db.transaction((txn) async {
      await txn.delete(
        'object_relations',
        where: 'source_id = ? OR target_id = ?',
        whereArgs: [objectId, objectId],
      );
      await txn.delete('objects', where: 'id = ?', whereArgs: [objectId]);
    });
  }

  Future<ObjectModel> getObject(String objectId) async {
    final obj = await _loadObject(objectId);
    if (obj == null) throw Exception('Object not found');
    return obj;
  }

  Future<List<ObjectModel>> listObjects({String? typeId}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'objects',
      where: typeId != null ? 'type_id = ?' : null,
      whereArgs: typeId != null ? [typeId] : null,
      orderBy: 'created_at',
    );
    final result = <ObjectModel>[];
    for (final row in rows) {
      result.add(_hydrateObject(row));
    }
    return result;
  }

  Future<void> addRelation(String sourceId, String targetId, String relationId) async {
    final db = await _dbHelper.database;
    await db.insert('object_relations', {
      'id': _uuid.v4(),
      'source_id': sourceId,
      'target_id': targetId,
      'relation_id': relationId,
    });
  }

  Future<void> removeRelation(String sourceId, String targetId, String relationId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'object_relations',
      where: 'source_id = ? AND target_id = ? AND relation_id = ?',
      whereArgs: [sourceId, targetId, relationId],
    );
  }

  Future<List<ObjectModel>> getRelatedObjects(String objectId, {String? relationId}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'object_relations',
      columns: ['target_id'],
      where: relationId != null
          ? 'source_id = ? AND relation_id = ?'
          : 'source_id = ?',
      whereArgs: relationId != null ? [objectId, relationId] : [objectId],
    );
    final targetIds = rows.map((r) => r['target_id'] as String).toList();
    if (targetIds.isEmpty) return [];
    final objRows = await db.query('objects', where: 'id IN (${List.filled(targetIds.length, '?').join(',')})', whereArgs: targetIds);
    return objRows.map(_hydrateObject).toList();
  }

  Future<ObjectModel> promoteBlockToObject(String noteId, String blockId, String objectTypeId) async {
    final db = await _dbHelper.database;
    final typeRows = await db.query('object_types', where: 'id = ?', whereArgs: [objectTypeId], limit: 1);
    if (typeRows.isEmpty) throw Exception('Object type not found');
    final id = _uuid.v4();
    final now = DateTime.now();
    await db.insert('objects', {
      'id': id,
      'type_id': objectTypeId,
      'properties': jsonEncode({
        'source_note_id': noteId,
        'source_block_id': blockId,
      }),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    return ObjectModel(
      id: id,
      objectTypeId: objectTypeId,
      properties: {'source_note_id': noteId, 'source_block_id': blockId},
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<List<ObjectRelationEntry>> allRelations() async {
    final db = await _dbHelper.database;
    final rows = await db.query('object_relations');
    return rows
        .map((r) => ObjectRelationEntry(
              sourceId: r['source_id'] as String,
              targetId: r['target_id'] as String,
              relationId: r['relation_id'] as String,
            ))
        .toList();
  }

  Future<ObjectTypeModel> _loadObjectType(String typeId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('object_types', where: 'id = ?', whereArgs: [typeId], limit: 1);
    if (rows.isEmpty) throw Exception('Object type not found');
    return _hydrateObjectType(rows.first);
  }

  Future<ObjectTypeModel> _hydrateObjectType(Map<String, Object?> row) async {
    final db = await _dbHelper.database;
    final typeId = row['id'] as String;
    final propRows = await db.query(
      'object_properties',
      where: 'type_id = ?',
      whereArgs: [typeId],
      orderBy: 'position',
    );
    final relRows = await db.query(
      'object_relations_definitions',
      where: 'type_id = ?',
      whereArgs: [typeId],
    );
    return ObjectTypeModel(
      id: typeId,
      name: row['name'] as String,
      icon: (row['icon'] as String?) ?? '',
      properties: propRows.map(_hydrateProperty).toList(),
      relations: relRows.map(_hydrateRelation).toList(),
    );
  }

  ObjectPropertyModel _hydrateProperty(Map<String, Object?> row) {
    final formatRaw = row['format'] as String? ?? '{}';
    final decoded = jsonDecode(formatRaw);
    final format = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    return ObjectPropertyModel(
      id: row['id'] as String,
      name: row['name'] as String,
      propertyType: row['property_type'] as String,
      format: format,
    );
  }

  ObjectRelationModel _hydrateRelation(Map<String, Object?> row) {
    return ObjectRelationModel(
      id: row['id'] as String,
      name: row['name'] as String,
      relationType: row['relation_type'] as String,
      sourceType: row['source_type'] as String,
      targetType: row['target_type'] as String,
    );
  }

  Future<ObjectModel?> _loadObject(String objectId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('objects', where: 'id = ?', whereArgs: [objectId], limit: 1);
    if (rows.isEmpty) return null;
    return _hydrateObject(rows.first);
  }

  ObjectModel _hydrateObject(Map<String, Object?> row) {
    final propertiesRaw = row['properties'] as String? ?? '{}';
    final decoded = jsonDecode(propertiesRaw);
    final properties = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    return ObjectModel(
      id: row['id'] as String,
      objectTypeId: row['type_id'] as String,
      properties: properties,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}

class ObjectRelationEntry {
  final String sourceId;
  final String targetId;
  final String relationId;

  const ObjectRelationEntry({
    required this.sourceId,
    required this.targetId,
    required this.relationId,
  });
}
