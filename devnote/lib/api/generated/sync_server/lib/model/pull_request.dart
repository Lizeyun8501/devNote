//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_sync_api;

class PullRequest {
  /// Returns a new [PullRequest] instance.
  PullRequest({
    required this.deviceId,
    this.sinceVersion,
  });

  /// Device identifier
  String deviceId;

  /// Pull records with version greater than this value
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? sinceVersion;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PullRequest &&
    other.deviceId == deviceId &&
    other.sinceVersion == sinceVersion;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (deviceId.hashCode) +
    (sinceVersion == null ? 0 : sinceVersion!.hashCode);

  @override
  String toString() => 'PullRequest[deviceId=$deviceId, sinceVersion=$sinceVersion]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'device_id'] = this.deviceId;
    if (this.sinceVersion != null) {
      json[r'since_version'] = this.sinceVersion;
    } else {
      json[r'since_version'] = null;
    }
    return json;
  }

  /// Returns a new [PullRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PullRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'device_id'), 'Required key "PullRequest[device_id]" is missing from JSON.');
        assert(json[r'device_id'] != null, 'Required key "PullRequest[device_id]" has a null value in JSON.');
        return true;
      }());

      return PullRequest(
        deviceId: mapValueOfType<String>(json, r'device_id')!,
        sinceVersion: mapValueOfType<int>(json, r'since_version'),
      );
    }
    return null;
  }

  static List<PullRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PullRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PullRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PullRequest> mapFromJson(dynamic json) {
    final map = <String, PullRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PullRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PullRequest-objects as value to a dart map
  static Map<String, List<PullRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PullRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PullRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'device_id',
  };
}

