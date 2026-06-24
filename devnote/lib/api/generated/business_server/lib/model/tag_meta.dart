//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_business_api;

class TagMeta {
  /// Returns a new [TagMeta] instance.
  TagMeta({
    this.id,
    this.name,
    this.parentId,
    this.color,
    this.description,
    this.createdAt,
    this.useCount,
  });

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? id;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? name;

  String? parentId;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? color;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? description;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  DateTime? createdAt;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? useCount;

  @override
  bool operator ==(Object other) => identical(this, other) || other is TagMeta &&
    other.id == id &&
    other.name == name &&
    other.parentId == parentId &&
    other.color == color &&
    other.description == description &&
    other.createdAt == createdAt &&
    other.useCount == useCount;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id == null ? 0 : id!.hashCode) +
    (name == null ? 0 : name!.hashCode) +
    (parentId == null ? 0 : parentId!.hashCode) +
    (color == null ? 0 : color!.hashCode) +
    (description == null ? 0 : description!.hashCode) +
    (createdAt == null ? 0 : createdAt!.hashCode) +
    (useCount == null ? 0 : useCount!.hashCode);

  @override
  String toString() => 'TagMeta[id=$id, name=$name, parentId=$parentId, color=$color, description=$description, createdAt=$createdAt, useCount=$useCount]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.id != null) {
      json[r'id'] = this.id;
    } else {
      json[r'id'] = null;
    }
    if (this.name != null) {
      json[r'name'] = this.name;
    } else {
      json[r'name'] = null;
    }
    if (this.parentId != null) {
      json[r'parent_id'] = this.parentId;
    } else {
      json[r'parent_id'] = null;
    }
    if (this.color != null) {
      json[r'color'] = this.color;
    } else {
      json[r'color'] = null;
    }
    if (this.description != null) {
      json[r'description'] = this.description;
    } else {
      json[r'description'] = null;
    }
    if (this.createdAt != null) {
      json[r'created_at'] = this.createdAt!.toUtc().toIso8601String();
    } else {
      json[r'created_at'] = null;
    }
    if (this.useCount != null) {
      json[r'use_count'] = this.useCount;
    } else {
      json[r'use_count'] = null;
    }
    return json;
  }

  /// Returns a new [TagMeta] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static TagMeta? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return TagMeta(
        id: mapValueOfType<String>(json, r'id'),
        name: mapValueOfType<String>(json, r'name'),
        parentId: mapValueOfType<String>(json, r'parent_id'),
        color: mapValueOfType<String>(json, r'color'),
        description: mapValueOfType<String>(json, r'description'),
        createdAt: mapDateTime(json, r'created_at', r''),
        useCount: mapValueOfType<int>(json, r'use_count'),
      );
    }
    return null;
  }

  static List<TagMeta> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <TagMeta>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = TagMeta.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, TagMeta> mapFromJson(dynamic json) {
    final map = <String, TagMeta>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = TagMeta.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of TagMeta-objects as value to a dart map
  static Map<String, List<TagMeta>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<TagMeta>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = TagMeta.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

