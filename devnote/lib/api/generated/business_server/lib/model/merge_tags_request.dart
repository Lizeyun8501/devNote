//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_business_api;

class MergeTagsRequest {
  /// Returns a new [MergeTagsRequest] instance.
  MergeTagsRequest({
    required this.sourceTagId,
    required this.targetTagId,
  });

  String sourceTagId;

  String targetTagId;

  @override
  bool operator ==(Object other) => identical(this, other) || other is MergeTagsRequest &&
    other.sourceTagId == sourceTagId &&
    other.targetTagId == targetTagId;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (sourceTagId.hashCode) +
    (targetTagId.hashCode);

  @override
  String toString() => 'MergeTagsRequest[sourceTagId=$sourceTagId, targetTagId=$targetTagId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'source_tag_id'] = this.sourceTagId;
      json[r'target_tag_id'] = this.targetTagId;
    return json;
  }

  /// Returns a new [MergeTagsRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static MergeTagsRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'source_tag_id'), 'Required key "MergeTagsRequest[source_tag_id]" is missing from JSON.');
        assert(json[r'source_tag_id'] != null, 'Required key "MergeTagsRequest[source_tag_id]" has a null value in JSON.');
        assert(json.containsKey(r'target_tag_id'), 'Required key "MergeTagsRequest[target_tag_id]" is missing from JSON.');
        assert(json[r'target_tag_id'] != null, 'Required key "MergeTagsRequest[target_tag_id]" has a null value in JSON.');
        return true;
      }());

      return MergeTagsRequest(
        sourceTagId: mapValueOfType<String>(json, r'source_tag_id')!,
        targetTagId: mapValueOfType<String>(json, r'target_tag_id')!,
      );
    }
    return null;
  }

  static List<MergeTagsRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <MergeTagsRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = MergeTagsRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, MergeTagsRequest> mapFromJson(dynamic json) {
    final map = <String, MergeTagsRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = MergeTagsRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of MergeTagsRequest-objects as value to a dart map
  static Map<String, List<MergeTagsRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<MergeTagsRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = MergeTagsRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'source_tag_id',
    'target_tag_id',
  };
}

