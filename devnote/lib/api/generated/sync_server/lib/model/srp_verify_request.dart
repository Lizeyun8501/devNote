//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_sync_api;

class SRPVerifyRequest {
  /// Returns a new [SRPVerifyRequest] instance.
  SRPVerifyRequest({
    required this.username,
    required this.A,
    required this.M1,
  });

  String username;

  /// Base64-encoded client public ephemeral value
  String A;

  /// Base64-encoded client proof
  String M1;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SRPVerifyRequest &&
    other.username == username &&
    other.A == A &&
    other.M1 == M1;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (username.hashCode) +
    (A.hashCode) +
    (M1.hashCode);

  @override
  String toString() => 'SRPVerifyRequest[username=$username, A=$A, M1=$M1]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'username'] = this.username;
      json[r'A'] = this.A;
      json[r'M1'] = this.M1;
    return json;
  }

  /// Returns a new [SRPVerifyRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SRPVerifyRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'username'), 'Required key "SRPVerifyRequest[username]" is missing from JSON.');
        assert(json[r'username'] != null, 'Required key "SRPVerifyRequest[username]" has a null value in JSON.');
        assert(json.containsKey(r'A'), 'Required key "SRPVerifyRequest[A]" is missing from JSON.');
        assert(json[r'A'] != null, 'Required key "SRPVerifyRequest[A]" has a null value in JSON.');
        assert(json.containsKey(r'M1'), 'Required key "SRPVerifyRequest[M1]" is missing from JSON.');
        assert(json[r'M1'] != null, 'Required key "SRPVerifyRequest[M1]" has a null value in JSON.');
        return true;
      }());

      return SRPVerifyRequest(
        username: mapValueOfType<String>(json, r'username')!,
        A: mapValueOfType<String>(json, r'A')!,
        M1: mapValueOfType<String>(json, r'M1')!,
      );
    }
    return null;
  }

  static List<SRPVerifyRequest> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SRPVerifyRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SRPVerifyRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SRPVerifyRequest> mapFromJson(dynamic json) {
    final map = <String, SRPVerifyRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SRPVerifyRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SRPVerifyRequest-objects as value to a dart map
  static Map<String, List<SRPVerifyRequest>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SRPVerifyRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SRPVerifyRequest.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'username',
    'A',
    'M1',
  };
}

