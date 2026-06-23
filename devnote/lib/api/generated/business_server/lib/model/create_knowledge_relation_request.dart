//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_business_api;

class CreateKnowledgeRelationRequest {
  /// Returns a new [CreateKnowledgeRelationRequest] instance.
  CreateKnowledgeRelationRequest({
    required this.sourceNoteId,
    required this.targetNoteId,
    this.relationType = 'link',
    this.weight = 1.0,
  });

  String sourceNoteId;

  String targetNoteId;

  String relationType;

  double weight;

  @override
  bool operator ==(Object other) => identical(this, other) || other is CreateKnowledgeRelationRequest &&
    other.sourceNoteId == sourceNoteId &&
    other.targetNoteId == targetNoteId &&
    other.relationType == relationType &&
    other.weight == weight;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (sourceNoteId.hashCode) +
    (targetNoteId.hashCode) +
    (relationType.hashCode) +
    (weight.hashCode);

  @override
  String toString() => 'CreateKnowledgeRelationRequest[sourceNoteId=$sourceNoteId, targetNoteId=$targetNoteId, relationType=$relationType, weight=$weight]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'source_note_id'] = this.sourceNoteId;
      json[r'target_note_id'] = this.targetNoteId;
      json[r'relation_type'] = this.relationType;
      json[r'weight'] = this.weight;
    return json;
  }

  /// Returns a new [CreateKnowledgeRelationRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static CreateKnowledgeRelationRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'source_note_id'), 'Required key "CreateKnowledgeRelationRequest[source_note_id]" is missing from JSON.');
        assert(json[r'source_note_id'] != null, 'Required key "CreateKnowledgeRelationRequest[source_note_id]" has a null value in JSON.');
        assert(json.containsKey(r'target_note_id'), 'Required key "CreateKnowledgeRelationRequest[target_note_id]" is missing from JSON.');
        assert(json[r'target_note_id'] != null, 'Required key "CreateKnowledgeRelationRequest[target_note_id]" has a null value in JSON.');
        return true;
      }());

      return CreateKnowledgeRelationRequest(
        sourceNoteId: mapValueOfType<String>(json, r'source_note_id')!,
        targetNoteId: mapValueOfType<String>(json, r'target_note_id')!,
        relationType: mapValueOfType<String>(json, r'relation_type') ?? 'link',
        weight: mapValueOfType<double>(json, r'weight') ?? 1.0,
      );
    }
    return null;
  }

  static List<CreateKnowledgeRelationRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <CreateKnowledgeRelationRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CreateKnowledgeRelationRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CreateKnowledgeRelationRequest> mapFromJson(dynamic json) {
    final map = <String, CreateKnowledgeRelationRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CreateKnowledgeRelationRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of CreateKnowledgeRelationRequest-objects as value to a dart map
  static Map<String, List<CreateKnowledgeRelationRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<CreateKnowledgeRelationRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CreateKnowledgeRelationRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'source_note_id',
    'target_note_id',
  };
}

