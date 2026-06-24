//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_business_api;

class FolderMeta {
  /// Returns a new [FolderMeta] instance.
  FolderMeta({
    this.id,
    this.name,
    this.parentId,
    this.path,
    this.description,
    this.icon,
    this.color,
    this.sortOrder,
    this.createdAt,
    this.modifiedAt,
    this.noteCount,
    this.childCount,
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
  String? path;

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
  String? icon;

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
  int? sortOrder;

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
  DateTime? modifiedAt;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? noteCount;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? childCount;

  @override
  bool operator ==(Object other) => identical(this, other) || other is FolderMeta &&
    other.id == id &&
    other.name == name &&
    other.parentId == parentId &&
    other.path == path &&
    other.description == description &&
    other.icon == icon &&
    other.color == color &&
    other.sortOrder == sortOrder &&
    other.createdAt == createdAt &&
    other.modifiedAt == modifiedAt &&
    other.noteCount == noteCount &&
    other.childCount == childCount;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id == null ? 0 : id!.hashCode) +
    (name == null ? 0 : name!.hashCode) +
    (parentId == null ? 0 : parentId!.hashCode) +
    (path == null ? 0 : path!.hashCode) +
    (description == null ? 0 : description!.hashCode) +
    (icon == null ? 0 : icon!.hashCode) +
    (color == null ? 0 : color!.hashCode) +
    (sortOrder == null ? 0 : sortOrder!.hashCode) +
    (createdAt == null ? 0 : createdAt!.hashCode) +
    (modifiedAt == null ? 0 : modifiedAt!.hashCode) +
    (noteCount == null ? 0 : noteCount!.hashCode) +
    (childCount == null ? 0 : childCount!.hashCode);

  @override
  String toString() => 'FolderMeta[id=$id, name=$name, parentId=$parentId, path=$path, description=$description, icon=$icon, color=$color, sortOrder=$sortOrder, createdAt=$createdAt, modifiedAt=$modifiedAt, noteCount=$noteCount, childCount=$childCount]';

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
    if (this.path != null) {
      json[r'path'] = this.path;
    } else {
      json[r'path'] = null;
    }
    if (this.description != null) {
      json[r'description'] = this.description;
    } else {
      json[r'description'] = null;
    }
    if (this.icon != null) {
      json[r'icon'] = this.icon;
    } else {
      json[r'icon'] = null;
    }
    if (this.color != null) {
      json[r'color'] = this.color;
    } else {
      json[r'color'] = null;
    }
    if (this.sortOrder != null) {
      json[r'sort_order'] = this.sortOrder;
    } else {
      json[r'sort_order'] = null;
    }
    if (this.createdAt != null) {
      json[r'created_at'] = this.createdAt!.toUtc().toIso8601String();
    } else {
      json[r'created_at'] = null;
    }
    if (this.modifiedAt != null) {
      json[r'modified_at'] = this.modifiedAt!.toUtc().toIso8601String();
    } else {
      json[r'modified_at'] = null;
    }
    if (this.noteCount != null) {
      json[r'note_count'] = this.noteCount;
    } else {
      json[r'note_count'] = null;
    }
    if (this.childCount != null) {
      json[r'child_count'] = this.childCount;
    } else {
      json[r'child_count'] = null;
    }
    return json;
  }

  /// Returns a new [FolderMeta] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static FolderMeta? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return FolderMeta(
        id: mapValueOfType<String>(json, r'id'),
        name: mapValueOfType<String>(json, r'name'),
        parentId: mapValueOfType<String>(json, r'parent_id'),
        path: mapValueOfType<String>(json, r'path'),
        description: mapValueOfType<String>(json, r'description'),
        icon: mapValueOfType<String>(json, r'icon'),
        color: mapValueOfType<String>(json, r'color'),
        sortOrder: mapValueOfType<int>(json, r'sort_order'),
        createdAt: mapDateTime(json, r'created_at', r''),
        modifiedAt: mapDateTime(json, r'modified_at', r''),
        noteCount: mapValueOfType<int>(json, r'note_count'),
        childCount: mapValueOfType<int>(json, r'child_count'),
      );
    }
    return null;
  }

  static List<FolderMeta> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <FolderMeta>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = FolderMeta.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, FolderMeta> mapFromJson(dynamic json) {
    final map = <String, FolderMeta>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = FolderMeta.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of FolderMeta-objects as value to a dart map
  static Map<String, List<FolderMeta>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<FolderMeta>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = FolderMeta.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

