//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_sync_api;

class SyncRecord {
  /// Returns a new [SyncRecord] instance.
  SyncRecord({
    this.id,
    this.userId,
    this.deviceId,
    this.noteId,
    this.action,
    this.version,
    this.timestamp,
    this.payload,
    this.createdAt,
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
  String? userId;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? deviceId;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? noteId;

  SyncRecordActionEnum? action;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? version;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  DateTime? timestamp;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? payload;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  DateTime? createdAt;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SyncRecord &&
    other.id == id &&
    other.userId == userId &&
    other.deviceId == deviceId &&
    other.noteId == noteId &&
    other.action == action &&
    other.version == version &&
    other.timestamp == timestamp &&
    other.payload == payload &&
    other.createdAt == createdAt;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (id == null ? 0 : id!.hashCode) +
    (userId == null ? 0 : userId!.hashCode) +
    (deviceId == null ? 0 : deviceId!.hashCode) +
    (noteId == null ? 0 : noteId!.hashCode) +
    (action == null ? 0 : action!.hashCode) +
    (version == null ? 0 : version!.hashCode) +
    (timestamp == null ? 0 : timestamp!.hashCode) +
    (payload == null ? 0 : payload!.hashCode) +
    (createdAt == null ? 0 : createdAt!.hashCode);

  @override
  String toString() => 'SyncRecord[id=$id, userId=$userId, deviceId=$deviceId, noteId=$noteId, action=$action, version=$version, timestamp=$timestamp, payload=$payload, createdAt=$createdAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.id != null) {
      json[r'id'] = this.id;
    } else {
      json[r'id'] = null;
    }
    if (this.userId != null) {
      json[r'user_id'] = this.userId;
    } else {
      json[r'user_id'] = null;
    }
    if (this.deviceId != null) {
      json[r'device_id'] = this.deviceId;
    } else {
      json[r'device_id'] = null;
    }
    if (this.noteId != null) {
      json[r'note_id'] = this.noteId;
    } else {
      json[r'note_id'] = null;
    }
    if (this.action != null) {
      json[r'action'] = this.action;
    } else {
      json[r'action'] = null;
    }
    if (this.version != null) {
      json[r'version'] = this.version;
    } else {
      json[r'version'] = null;
    }
    if (this.timestamp != null) {
      json[r'timestamp'] = this.timestamp!.toUtc().toIso8601String();
    } else {
      json[r'timestamp'] = null;
    }
    if (this.payload != null) {
      json[r'payload'] = this.payload;
    } else {
      json[r'payload'] = null;
    }
    if (this.createdAt != null) {
      json[r'created_at'] = this.createdAt!.toUtc().toIso8601String();
    } else {
      json[r'created_at'] = null;
    }
    return json;
  }

  /// Returns a new [SyncRecord] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SyncRecord? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return SyncRecord(
        id: mapValueOfType<String>(json, r'id'),
        userId: mapValueOfType<String>(json, r'user_id'),
        deviceId: mapValueOfType<String>(json, r'device_id'),
        noteId: mapValueOfType<String>(json, r'note_id'),
        action: SyncRecordActionEnum.fromJson(json[r'action']),
        version: mapValueOfType<int>(json, r'version'),
        timestamp: mapDateTime(json, r'timestamp', r''),
        payload: mapValueOfType<String>(json, r'payload'),
        createdAt: mapDateTime(json, r'created_at', r''),
      );
    }
    return null;
  }

  static List<SyncRecord> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SyncRecord>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SyncRecord.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SyncRecord> mapFromJson(dynamic json) {
    final map = <String, SyncRecord>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SyncRecord.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SyncRecord-objects as value to a dart map
  static Map<String, List<SyncRecord>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SyncRecord>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SyncRecord.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}


class SyncRecordActionEnum {
  /// Instantiate a new enum with the provided [value].
  const SyncRecordActionEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const create = SyncRecordActionEnum._(r'create');
  static const update = SyncRecordActionEnum._(r'update');
  static const delete = SyncRecordActionEnum._(r'delete');

  /// List of all possible values in this [enum][SyncRecordActionEnum].
  static const values = <SyncRecordActionEnum>[
    create,
    update,
    delete,
  ];

  static SyncRecordActionEnum? fromJson(dynamic value) => SyncRecordActionEnumTypeTransformer().decode(value);

  static List<SyncRecordActionEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SyncRecordActionEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SyncRecordActionEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [SyncRecordActionEnum] to String,
/// and [decode] dynamic data back to [SyncRecordActionEnum].
class SyncRecordActionEnumTypeTransformer {
  factory SyncRecordActionEnumTypeTransformer() => _instance ??= const SyncRecordActionEnumTypeTransformer._();

  const SyncRecordActionEnumTypeTransformer._();

  String encode(SyncRecordActionEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a SyncRecordActionEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  SyncRecordActionEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'create': return SyncRecordActionEnum.create;
        case r'update': return SyncRecordActionEnum.update;
        case r'delete': return SyncRecordActionEnum.delete;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [SyncRecordActionEnumTypeTransformer] instance.
  static SyncRecordActionEnumTypeTransformer? _instance;
}


