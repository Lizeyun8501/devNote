//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_business_api;

class NoteMeta {
  /// Returns a new [NoteMeta] instance.
  NoteMeta({
    this.id,
    this.title,
    this.author,
    this.createdAt,
    this.modifiedAt,
    this.wordCount,
    this.charCount,
    this.format,
    this.excerpt,
    this.language,
    this.isEncrypted,
    this.contentHash,
    this.customFields,
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
  String? title;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? author;

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
  int? wordCount;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? charCount;

  /// Note format (e.g., markdown, html)
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? format;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? excerpt;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? language;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  bool? isEncrypted;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? contentHash;

  /// JSON-encoded custom fields
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? customFields;

  @override
  bool operator ==(Object other) => identical(this, other) || other is NoteMeta &&
    other.id == id &&
    other.title == title &&
    other.author == author &&
    other.createdAt == createdAt &&
    other.modifiedAt == modifiedAt &&
    other.wordCount == wordCount &&
    other.charCount == charCount &&
    other.format == format &&
    other.excerpt == excerpt &&
    other.language == language &&
    other.isEncrypted == isEncrypted &&
    other.contentHash == contentHash &&
    other.customFields == customFields;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id == null ? 0 : id!.hashCode) +
    (title == null ? 0 : title!.hashCode) +
    (author == null ? 0 : author!.hashCode) +
    (createdAt == null ? 0 : createdAt!.hashCode) +
    (modifiedAt == null ? 0 : modifiedAt!.hashCode) +
    (wordCount == null ? 0 : wordCount!.hashCode) +
    (charCount == null ? 0 : charCount!.hashCode) +
    (format == null ? 0 : format!.hashCode) +
    (excerpt == null ? 0 : excerpt!.hashCode) +
    (language == null ? 0 : language!.hashCode) +
    (isEncrypted == null ? 0 : isEncrypted!.hashCode) +
    (contentHash == null ? 0 : contentHash!.hashCode) +
    (customFields == null ? 0 : customFields!.hashCode);

  @override
  String toString() => 'NoteMeta[id=$id, title=$title, author=$author, createdAt=$createdAt, modifiedAt=$modifiedAt, wordCount=$wordCount, charCount=$charCount, format=$format, excerpt=$excerpt, language=$language, isEncrypted=$isEncrypted, contentHash=$contentHash, customFields=$customFields]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.id != null) {
      json[r'id'] = this.id;
    } else {
      json[r'id'] = null;
    }
    if (this.title != null) {
      json[r'title'] = this.title;
    } else {
      json[r'title'] = null;
    }
    if (this.author != null) {
      json[r'author'] = this.author;
    } else {
      json[r'author'] = null;
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
    if (this.wordCount != null) {
      json[r'word_count'] = this.wordCount;
    } else {
      json[r'word_count'] = null;
    }
    if (this.charCount != null) {
      json[r'char_count'] = this.charCount;
    } else {
      json[r'char_count'] = null;
    }
    if (this.format != null) {
      json[r'format'] = this.format;
    } else {
      json[r'format'] = null;
    }
    if (this.excerpt != null) {
      json[r'excerpt'] = this.excerpt;
    } else {
      json[r'excerpt'] = null;
    }
    if (this.language != null) {
      json[r'language'] = this.language;
    } else {
      json[r'language'] = null;
    }
    if (this.isEncrypted != null) {
      json[r'is_encrypted'] = this.isEncrypted;
    } else {
      json[r'is_encrypted'] = null;
    }
    if (this.contentHash != null) {
      json[r'content_hash'] = this.contentHash;
    } else {
      json[r'content_hash'] = null;
    }
    if (this.customFields != null) {
      json[r'custom_fields'] = this.customFields;
    } else {
      json[r'custom_fields'] = null;
    }
    return json;
  }

  /// Returns a new [NoteMeta] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static NoteMeta? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return NoteMeta(
        id: mapValueOfType<String>(json, r'id'),
        title: mapValueOfType<String>(json, r'title'),
        author: mapValueOfType<String>(json, r'author'),
        createdAt: mapDateTime(json, r'created_at', r''),
        modifiedAt: mapDateTime(json, r'modified_at', r''),
        wordCount: mapValueOfType<int>(json, r'word_count'),
        charCount: mapValueOfType<int>(json, r'char_count'),
        format: mapValueOfType<String>(json, r'format'),
        excerpt: mapValueOfType<String>(json, r'excerpt'),
        language: mapValueOfType<String>(json, r'language'),
        isEncrypted: mapValueOfType<bool>(json, r'is_encrypted'),
        contentHash: mapValueOfType<String>(json, r'content_hash'),
        customFields: mapValueOfType<String>(json, r'custom_fields'),
      );
    }
    return null;
  }

  static List<NoteMeta> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <NoteMeta>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = NoteMeta.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, NoteMeta> mapFromJson(dynamic json) {
    final map = <String, NoteMeta>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = NoteMeta.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of NoteMeta-objects as value to a dart map
  static Map<String, List<NoteMeta>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<NoteMeta>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = NoteMeta.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

