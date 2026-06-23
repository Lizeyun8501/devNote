//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_business_api;

class KnowledgeRelation {
  /// Returns a new [KnowledgeRelation] instance.
  KnowledgeRelation({
    this.id,
    this.sourceNoteId,
    this.targetNoteId,
    this.weight,
    this.referenceCount,
    this.relationType,
    this.createdAt,
    this.updatedAt,
  });

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? id;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? sourceNoteId;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? targetNoteId;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  double? weight;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? referenceCount;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? relationType;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  DateTime? createdAt;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  DateTime? updatedAt;

  @override
  bool operator ==(Object other) => identical(this, other) || other is KnowledgeRelation &&
    other.id == id &&
    other.sourceNoteId == sourceNoteId &&
    other.targetNoteId == targetNoteId &&
    other.weight == weight &&
    other.referenceCount == referenceCount &&
    other.relationType == relationType &&
    other.createdAt == createdAt &&
    other.updatedAt == updatedAt;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id == null ? 0 : id!.hashCode) +
    (sourceNoteId == null ? 0 : sourceNoteId!.hashCode) +
    (targetNoteId == null ? 0 : targetNoteId!.hashCode) +
    (weight == null ? 0 : weight!.hashCode) +
    (referenceCount == null ? 0 : referenceCount!.hashCode) +
    (relationType == null ? 0 : relationType!.hashCode) +
    (createdAt == null ? 0 : createdAt!.hashCode) +
    (updatedAt == null ? 0 : updatedAt!.hashCode);

  @override
  String toString() => 'KnowledgeRelation[id=$id, sourceNoteId=$sourceNoteId, targetNoteId=$targetNoteId, weight=$weight, referenceCount=$referenceCount, relationType=$relationType, createdAt=$createdAt, updatedAt=$updatedAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.id != null) {
      json[r'id'] = this.id;
    } else {
      json[r'id'] = null;
    }
    if (this.sourceNoteId != null) {
      json[r'source_note_id'] = this.sourceNoteId;
    } else {
      json[r'source_note_id'] = null;
    }
    if (this.targetNoteId != null) {
      json[r'target_note_id'] = this.targetNoteId;
    } else {
      json[r'target_note_id'] = null;
    }
    if (this.weight != null) {
      json[r'weight'] = this.weight;
    } else {
      json[r'weight'] = null;
    }
    if (this.referenceCount != null) {
      json[r'reference_count'] = this.referenceCount;
    } else {
      json[r'reference_count'] = null;
    }
    if (this.relationType != null) {
      json[r'relation_type'] = this.relationType;
    } else {
      json[r'relation_type'] = null;
    }
    if (this.createdAt != null) {
      json[r'created_at'] = this.createdAt!.toUtc().toIso8601String();
    } else {
      json[r'created_at'] = null;
    }
    if (this.updatedAt != null) {
      json[r'updated_at'] = this.updatedAt!.toUtc().toIso8601String();
    } else {
      json[r'updated_at'] = null;
    }
    return json;
  }

  /// Returns a new [KnowledgeRelation] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static KnowledgeRelation? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return KnowledgeRelation(
        id: mapValueOfType<String>(json, r'id'),
        sourceNoteId: mapValueOfType<String>(json, r'source_note_id'),
        targetNoteId: mapValueOfType<String>(json, r'target_note_id'),
        weight: mapValueOfType<double>(json, r'weight'),
        referenceCount: mapValueOfType<int>(json, r'reference_count'),
        relationType: mapValueOfType<String>(json, r'relation_type'),
        createdAt: mapDateTime(json, r'created_at', r''),
        updatedAt: mapDateTime(json, r'updated_at', r''),
      );
    }
    return null;
  }

  static List<KnowledgeRelation> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <KnowledgeRelation>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = KnowledgeRelation.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, KnowledgeRelation> mapFromJson(dynamic json) {
    final map = <String, KnowledgeRelation>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = KnowledgeRelation.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of KnowledgeRelation-objects as value to a dart map
  static Map<String, List<KnowledgeRelation>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<KnowledgeRelation>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = KnowledgeRelation.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

