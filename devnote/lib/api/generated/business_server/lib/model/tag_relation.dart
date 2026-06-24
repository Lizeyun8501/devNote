//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_business_api;

class TagRelation {
  /// Returns a new [TagRelation] instance.
  TagRelation({
    this.id,
    this.tagId,
    this.noteId,
    this.linkedAt,
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
  String? tagId;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? noteId;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  DateTime? linkedAt;

  @override
  bool operator ==(Object other) => identical(this, other) || other is TagRelation &&
    other.id == id &&
    other.tagId == tagId &&
    other.noteId == noteId &&
    other.linkedAt == linkedAt;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id == null ? 0 : id!.hashCode) +
    (tagId == null ? 0 : tagId!.hashCode) +
    (noteId == null ? 0 : noteId!.hashCode) +
    (linkedAt == null ? 0 : linkedAt!.hashCode);

  @override
  String toString() => 'TagRelation[id=$id, tagId=$tagId, noteId=$noteId, linkedAt=$linkedAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.id != null) {
      json[r'id'] = this.id;
    } else {
      json[r'id'] = null;
    }
    if (this.tagId != null) {
      json[r'tag_id'] = this.tagId;
    } else {
      json[r'tag_id'] = null;
    }
    if (this.noteId != null) {
      json[r'note_id'] = this.noteId;
    } else {
      json[r'note_id'] = null;
    }
    if (this.linkedAt != null) {
      json[r'linked_at'] = this.linkedAt!.toUtc().toIso8601String();
    } else {
      json[r'linked_at'] = null;
    }
    return json;
  }

  /// Returns a new [TagRelation] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static TagRelation? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return TagRelation(
        id: mapValueOfType<String>(json, r'id'),
        tagId: mapValueOfType<String>(json, r'tag_id'),
        noteId: mapValueOfType<String>(json, r'note_id'),
        linkedAt: mapDateTime(json, r'linked_at', r''),
      );
    }
    return null;
  }

  static List<TagRelation> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <TagRelation>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = TagRelation.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, TagRelation> mapFromJson(dynamic json) {
    final map = <String, TagRelation>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = TagRelation.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of TagRelation-objects as value to a dart map
  static Map<String, List<TagRelation>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<TagRelation>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = TagRelation.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

