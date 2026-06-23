//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_business_api;

class ShortestPathResponseData {
  /// Returns a new [ShortestPathResponseData] instance.
  ShortestPathResponseData({
    this.path = const [],
    this.distance,
  });

  /// Sequence of note IDs forming the shortest path
  List<String> path;

  /// Number of hops in the shortest path
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? distance;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ShortestPathResponseData &&
    _deepEquality.equals(other.path, path) &&
    other.distance == distance;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (path.hashCode) +
    (distance == null ? 0 : distance!.hashCode);

  @override
  String toString() => 'ShortestPathResponseData[path=$path, distance=$distance]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'path'] = this.path;
    if (this.distance != null) {
      json[r'distance'] = this.distance;
    } else {
      json[r'distance'] = null;
    }
    return json;
  }

  /// Returns a new [ShortestPathResponseData] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ShortestPathResponseData? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return ShortestPathResponseData(
        path: json[r'path'] is Iterable
            ? (json[r'path'] as Iterable).cast<String>().toList(growable: false)
            : const [],
        distance: mapValueOfType<int>(json, r'distance'),
      );
    }
    return null;
  }

  static List<ShortestPathResponseData> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ShortestPathResponseData>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ShortestPathResponseData.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ShortestPathResponseData> mapFromJson(dynamic json) {
    final map = <String, ShortestPathResponseData>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ShortestPathResponseData.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ShortestPathResponseData-objects as value to a dart map
  static Map<String, List<ShortestPathResponseData>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ShortestPathResponseData>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ShortestPathResponseData.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

