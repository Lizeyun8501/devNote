import 'package:uuid/uuid.dart';

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
  final _uuid = const Uuid();
  final Map<String, ObjectTypeModel> _objectTypes = {};
  final Map<String, ObjectModel> _objects = {};
  final List<ObjectRelationEntry> _objectRelations = [];

  Future<ObjectTypeModel> createObjectType(String name, String icon, List<ObjectPropertyModel> properties) async {
    final id = _uuid.v4();
    final ot = ObjectTypeModel(id: id, name: name, icon: icon, properties: properties);
    _objectTypes[id] = ot;
    return ot;
  }

  Future<ObjectTypeModel> updateObjectType(String typeId, String name, String icon) async {
    final ot = _objectTypes[typeId];
    if (ot == null) throw Exception('Object type not found');
    final updated = ot.copyWith(name: name, icon: icon);
    _objectTypes[typeId] = updated;
    return updated;
  }

  Future<void> deleteObjectType(String typeId) async {
    _objectTypes.remove(typeId);
  }

  Future<List<ObjectTypeModel>> listObjectTypes() async {
    return _objectTypes.values.toList();
  }

  Future<ObjectModel> createObject(String typeId, Map<String, dynamic> properties) async {
    if (!_objectTypes.containsKey(typeId)) throw Exception('Object type not found');
    final id = _uuid.v4();
    final now = DateTime.now();
    final obj = ObjectModel(id: id, objectTypeId: typeId, properties: properties, createdAt: now, updatedAt: now);
    _objects[id] = obj;
    return obj;
  }

  Future<ObjectModel> updateObject(String objectId, Map<String, dynamic> properties) async {
    final obj = _objects[objectId];
    if (obj == null) throw Exception('Object not found');
    final updated = obj.copyWith(properties: properties, updatedAt: DateTime.now());
    _objects[objectId] = updated;
    return updated;
  }

  Future<void> deleteObject(String objectId) async {
    _objects.remove(objectId);
    _objectRelations.removeWhere((r) => r.sourceId == objectId || r.targetId == objectId);
  }

  Future<ObjectModel> getObject(String objectId) async {
    final obj = _objects[objectId];
    if (obj == null) throw Exception('Object not found');
    return obj;
  }

  Future<List<ObjectModel>> listObjects({String? typeId}) async {
    if (typeId != null) {
      return _objects.values.where((o) => o.objectTypeId == typeId).toList();
    }
    return _objects.values.toList();
  }

  Future<void> addRelation(String sourceId, String targetId, String relationId) async {
    _objectRelations.add(ObjectRelationEntry(sourceId: sourceId, targetId: targetId, relationId: relationId));
  }

  Future<void> removeRelation(String sourceId, String targetId, String relationId) async {
    _objectRelations.removeWhere(
      (r) => r.sourceId == sourceId && r.targetId == targetId && r.relationId == relationId,
    );
  }

  Future<List<ObjectModel>> getRelatedObjects(String objectId, {String? relationId}) async {
    final targetIds = _objectRelations
        .where((r) => r.sourceId == objectId && (relationId == null || r.relationId == relationId))
        .map((r) => r.targetId)
        .toList();
    return targetIds.map((id) => _objects[id]).whereType<ObjectModel>().toList();
  }

  Future<ObjectModel> promoteBlockToObject(String noteId, String blockId, String objectTypeId) async {
    if (!_objectTypes.containsKey(objectTypeId)) throw Exception('Object type not found');
    final id = _uuid.v4();
    final now = DateTime.now();
    final obj = ObjectModel(
      id: id,
      objectTypeId: objectTypeId,
      properties: {'source_note_id': noteId, 'source_block_id': blockId},
      createdAt: now,
      updatedAt: now,
    );
    _objects[id] = obj;
    return obj;
  }

  List<ObjectRelationEntry> get allRelations => List.unmodifiable(_objectRelations);
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
