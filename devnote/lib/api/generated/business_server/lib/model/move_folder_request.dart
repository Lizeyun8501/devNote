//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_business_api;

class MoveFolderRequest {
  /// Returns a new [MoveFolderRequest] instance.
  MoveFolderRequest({
    required this.newParentId,
  });

  String newParentId;

  @override
  bool operator ==(Object other) => identical(this, other) || other is MoveFolderRequest &&
    other.newParentId == newParentId;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (newParentId.hashCode);

  @override
  String toString() => 'MoveFolderRequest[newParentId=$newParentId]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'new_parent_id'] = this.newParentId;
    return json;
  }

  /// Returns a new [MoveFolderRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static MoveFolderRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'new_parent_id'), 'Required key "MoveFolderRequest[new_parent_id]" is missing from JSON.');
        assert(json[r'new_parent_id'] != null, 'Required key "MoveFolderRequest[new_parent_id]" has a null value in JSON.');
        return true;
      }());

      return MoveFolderRequest(
        newParentId: mapValueOfType<String>(json, r'new_parent_id')!,
      );
    }
    return null;
  }

  static List<MoveFolderRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <MoveFolderRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = MoveFolderRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, MoveFolderRequest> mapFromJson(dynamic json) {
    final map = <String, MoveFolderRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = MoveFolderRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of MoveFolderRequest-objects as value to a dart map
  static Map<String, List<MoveFolderRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<MoveFolderRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = MoveFolderRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'new_parent_id',
  };
}

