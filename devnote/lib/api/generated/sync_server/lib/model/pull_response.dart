//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_sync_api;

class PullResponse {
  /// Returns a new [PullResponse] instance.
  PullResponse({
    this.records = const [],
    this.latestVersion,
    this.hasMore,
    this.limit,
  });

  /// List of sync records
  List<SyncRecord> records;

  /// Latest version number on the server
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? latestVersion;

  /// Whether more records are available
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  bool? hasMore;

  /// Number of records returned in this response
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? limit;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PullResponse &&
    _deepEquality.equals(other.records, records) &&
    other.latestVersion == latestVersion &&
    other.hasMore == hasMore &&
    other.limit == limit;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (records.hashCode) +
    (latestVersion == null ? 0 : latestVersion!.hashCode) +
    (hasMore == null ? 0 : hasMore!.hashCode) +
    (limit == null ? 0 : limit!.hashCode);

  @override
  String toString() => 'PullResponse[records=$records, latestVersion=$latestVersion, hasMore=$hasMore, limit=$limit]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'records'] = this.records;
    if (this.latestVersion != null) {
      json[r'latest_version'] = this.latestVersion;
    } else {
      json[r'latest_version'] = null;
    }
    if (this.hasMore != null) {
      json[r'has_more'] = this.hasMore;
    } else {
      json[r'has_more'] = null;
    }
    if (this.limit != null) {
      json[r'limit'] = this.limit;
    } else {
      json[r'limit'] = null;
    }
    return json;
  }

  /// Returns a new [PullResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PullResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return PullResponse(
        records: SyncRecord.listFromJson(json[r'records']),
        latestVersion: mapValueOfType<int>(json, r'latest_version'),
        hasMore: mapValueOfType<bool>(json, r'has_more'),
        limit: mapValueOfType<int>(json, r'limit'),
      );
    }
    return null;
  }

  static List<PullResponse> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PullResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PullResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PullResponse> mapFromJson(dynamic json) {
    final map = <String, PullResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PullResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PullResponse-objects as value to a dart map
  static Map<String, List<PullResponse>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PullResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PullResponse.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

