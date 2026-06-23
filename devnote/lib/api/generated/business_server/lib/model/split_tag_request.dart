//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_business_api;

class SplitTagRequest {
  /// Returns a new [SplitTagRequest] instance.
  SplitTagRequest({
    required this.sourceTagId,
    required this.newTagName,
    this.noteIds = const [],
  });

  String sourceTagId;

  String newTagName;

  List<String> noteIds;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SplitTagRequest &&
    other.sourceTagId == sourceTagId &&
    other.newTagName == newTagName &&
    _deepEquality.equals(other.noteIds, noteIds);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (sourceTagId.hashCode) +
    (newTagName.hashCode) +
    (noteIds.hashCode);

  @override
  String toString() => 'SplitTagRequest[sourceTagId=$sourceTagId, newTagName=$newTagName, noteIds=$noteIds]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'source_tag_id'] = this.sourceTagId;
      json[r'new_tag_name'] = this.newTagName;
      json[r'note_ids'] = this.noteIds;
    return json;
  }

  /// Returns a new [SplitTagRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SplitTagRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'source_tag_id'), 'Required key "SplitTagRequest[source_tag_id]" is missing from JSON.');
        assert(json[r'source_tag_id'] != null, 'Required key "SplitTagRequest[source_tag_id]" has a null value in JSON.');
        assert(json.containsKey(r'new_tag_name'), 'Required key "SplitTagRequest[new_tag_name]" is missing from JSON.');
        assert(json[r'new_tag_name'] != null, 'Required key "SplitTagRequest[new_tag_name]" has a null value in JSON.');
        assert(json.containsKey(r'note_ids'), 'Required key "SplitTagRequest[note_ids]" is missing from JSON.');
        assert(json[r'note_ids'] != null, 'Required key "SplitTagRequest[note_ids]" has a null value in JSON.');
        return true;
      }());

      return SplitTagRequest(
        sourceTagId: mapValueOfType<String>(json, r'source_tag_id')!,
        newTagName: mapValueOfType<String>(json, r'new_tag_name')!,
        noteIds: json[r'note_ids'] is Iterable
            ? (json[r'note_ids'] as Iterable).cast<String>().toList(growable: false)
            : const [],
      );
    }
    return null;
  }

  static List<SplitTagRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SplitTagRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SplitTagRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SplitTagRequest> mapFromJson(dynamic json) {
    final map = <String, SplitTagRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SplitTagRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SplitTagRequest-objects as value to a dart map
  static Map<String, List<SplitTagRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SplitTagRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SplitTagRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'source_tag_id',
    'new_tag_name',
    'note_ids',
  };
}

