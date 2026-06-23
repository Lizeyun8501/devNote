//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_sync_api;

class ConflictResolution {
  /// Returns a new [ConflictResolution] instance.
  ConflictResolution({
    required this.noteId,
    required this.chosenData,
    required this.version,
  });

  String noteId;

  /// The data chosen to resolve the conflict
  String chosenData;

  int version;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ConflictResolution &&
    other.noteId == noteId &&
    other.chosenData == chosenData &&
    other.version == version;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (noteId.hashCode) +
    (chosenData.hashCode) +
    (version.hashCode);

  @override
  String toString() => 'ConflictResolution[noteId=$noteId, chosenData=$chosenData, version=$version]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'note_id'] = this.noteId;
      json[r'chosen_data'] = this.chosenData;
      json[r'version'] = this.version;
    return json;
  }

  /// Returns a new [ConflictResolution] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ConflictResolution? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'note_id'), 'Required key "ConflictResolution[note_id]" is missing from JSON.');
        assert(json[r'note_id'] != null, 'Required key "ConflictResolution[note_id]" has a null value in JSON.');
        assert(json.containsKey(r'chosen_data'), 'Required key "ConflictResolution[chosen_data]" is missing from JSON.');
        assert(json[r'chosen_data'] != null, 'Required key "ConflictResolution[chosen_data]" has a null value in JSON.');
        assert(json.containsKey(r'version'), 'Required key "ConflictResolution[version]" is missing from JSON.');
        assert(json[r'version'] != null, 'Required key "ConflictResolution[version]" has a null value in JSON.');
        return true;
      }());

      return ConflictResolution(
        noteId: mapValueOfType<String>(json, r'note_id')!,
        chosenData: mapValueOfType<String>(json, r'chosen_data')!,
        version: mapValueOfType<int>(json, r'version')!,
      );
    }
    return null;
  }

  static List<ConflictResolution> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ConflictResolution>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ConflictResolution.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ConflictResolution> mapFromJson(dynamic json) {
    final map = <String, ConflictResolution>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ConflictResolution.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ConflictResolution-objects as value to a dart map
  static Map<String, List<ConflictResolution>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ConflictResolution>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ConflictResolution.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'note_id',
    'chosen_data',
    'version',
  };
}

