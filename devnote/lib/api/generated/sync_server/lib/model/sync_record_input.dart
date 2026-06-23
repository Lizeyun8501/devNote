//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_sync_api;

class SyncRecordInput {
  /// Returns a new [SyncRecordInput] instance.
  SyncRecordInput({
    required this.noteId,
    required this.action,
    this.version,
    this.payload,
  });

  /// Note identifier
  String noteId;

  /// Action type for this record
  SyncRecordInputActionEnum action;

  /// Client-side version number
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? version;

  /// Note content payload (CRDT or plain text)
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? payload;

  @override
  bool operator ==(Object other) => identical(this, other) || other is SyncRecordInput &&
    other.noteId == noteId &&
    other.action == action &&
    other.version == version &&
    other.payload == payload;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (noteId.hashCode) +
    (action.hashCode) +
    (version == null ? 0 : version!.hashCode) +
    (payload == null ? 0 : payload!.hashCode);

  @override
  String toString() => 'SyncRecordInput[noteId=$noteId, action=$action, version=$version, payload=$payload]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'note_id'] = this.noteId;
      json[r'action'] = this.action;
    if (this.version != null) {
      json[r'version'] = this.version;
    } else {
      json[r'version'] = null;
    }
    if (this.payload != null) {
      json[r'payload'] = this.payload;
    } else {
      json[r'payload'] = null;
    }
    return json;
  }

  /// Returns a new [SyncRecordInput] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SyncRecordInput? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'note_id'), 'Required key "SyncRecordInput[note_id]" is missing from JSON.');
        assert(json[r'note_id'] != null, 'Required key "SyncRecordInput[note_id]" has a null value in JSON.');
        assert(json.containsKey(r'action'), 'Required key "SyncRecordInput[action]" is missing from JSON.');
        assert(json[r'action'] != null, 'Required key "SyncRecordInput[action]" has a null value in JSON.');
        return true;
      }());

      return SyncRecordInput(
        noteId: mapValueOfType<String>(json, r'note_id')!,
        action: SyncRecordInputActionEnum.fromJson(json[r'action'])!,
        version: mapValueOfType<int>(json, r'version'),
        payload: mapValueOfType<String>(json, r'payload'),
      );
    }
    return null;
  }

  static List<SyncRecordInput> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SyncRecordInput>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SyncRecordInput.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SyncRecordInput> mapFromJson(dynamic json) {
    final map = <String, SyncRecordInput>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SyncRecordInput.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SyncRecordInput-objects as value to a dart map
  static Map<String, List<SyncRecordInput>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<SyncRecordInput>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SyncRecordInput.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'note_id',
    'action',
  };
}

/// Action type for this record
class SyncRecordInputActionEnum {
  /// Instantiate a new enum with the provided [value].
  const SyncRecordInputActionEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const create = SyncRecordInputActionEnum._(r'create');
  static const update = SyncRecordInputActionEnum._(r'update');
  static const delete = SyncRecordInputActionEnum._(r'delete');

  /// List of all possible values in this [enum][SyncRecordInputActionEnum].
  static const values = <SyncRecordInputActionEnum>[
    create,
    update,
    delete,
  ];

  static SyncRecordInputActionEnum? fromJson(dynamic value) => SyncRecordInputActionEnumTypeTransformer().decode(value);

  static List<SyncRecordInputActionEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <SyncRecordInputActionEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SyncRecordInputActionEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [SyncRecordInputActionEnum] to String,
/// and [decode] dynamic data back to [SyncRecordInputActionEnum].
class SyncRecordInputActionEnumTypeTransformer {
  factory SyncRecordInputActionEnumTypeTransformer() => _instance ??= const SyncRecordInputActionEnumTypeTransformer._();

  const SyncRecordInputActionEnumTypeTransformer._();

  String encode(SyncRecordInputActionEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a SyncRecordInputActionEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  SyncRecordInputActionEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'create': return SyncRecordInputActionEnum.create;
        case r'update': return SyncRecordInputActionEnum.update;
        case r'delete': return SyncRecordInputActionEnum.delete;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [SyncRecordInputActionEnumTypeTransformer] instance.
  static SyncRecordInputActionEnumTypeTransformer? _instance;
}


