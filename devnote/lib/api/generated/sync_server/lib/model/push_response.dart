//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_sync_api;

class PushResponse {
  /// Returns a new [PushResponse] instance.
  PushResponse({
    this.processed,
    this.conflicts = const [],
  });

  /// Number of records successfully processed
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? processed;

  /// List of detected conflicts (if any)
  List<Conflict> conflicts;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PushResponse &&
    other.processed == processed &&
    _deepEquality.equals(other.conflicts, conflicts);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (processed == null ? 0 : processed!.hashCode) +
    (conflicts.hashCode);

  @override
  String toString() => 'PushResponse[processed=$processed, conflicts=$conflicts]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.processed != null) {
      json[r'processed'] = this.processed;
    } else {
      json[r'processed'] = null;
    }
      json[r'conflicts'] = this.conflicts;
    return json;
  }

  /// Returns a new [PushResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PushResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return PushResponse(
        processed: mapValueOfType<int>(json, r'processed'),
        conflicts: Conflict.listFromJson(json[r'conflicts']),
      );
    }
    return null;
  }

  static List<PushResponse> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PushResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PushResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PushResponse> mapFromJson(dynamic json) {
    final map = <String, PushResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PushResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PushResponse-objects as value to a dart map
  static Map<String, List<PushResponse>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PushResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PushResponse.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

