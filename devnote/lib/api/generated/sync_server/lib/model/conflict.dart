//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_sync_api;

class Conflict {
  /// Returns a new [Conflict] instance.
  Conflict({
    this.recordId,
    this.noteId,
    this.localVersion,
    this.serverVersion,
    this.localData,
    this.serverData,
    this.strategy,
  });

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? recordId;

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
  int? localVersion;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? serverVersion;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? localData;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? serverData;

  ConflictStrategyEnum? strategy;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Conflict &&
    other.recordId == recordId &&
    other.noteId == noteId &&
    other.localVersion == localVersion &&
    other.serverVersion == serverVersion &&
    other.localData == localData &&
    other.serverData == serverData &&
    other.strategy == strategy;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (recordId == null ? 0 : recordId!.hashCode) +
    (noteId == null ? 0 : noteId!.hashCode) +
    (localVersion == null ? 0 : localVersion!.hashCode) +
    (serverVersion == null ? 0 : serverVersion!.hashCode) +
    (localData == null ? 0 : localData!.hashCode) +
    (serverData == null ? 0 : serverData!.hashCode) +
    (strategy == null ? 0 : strategy!.hashCode);

  @override
  String toString() => 'Conflict[recordId=$recordId, noteId=$noteId, localVersion=$localVersion, serverVersion=$serverVersion, localData=$localData, serverData=$serverData, strategy=$strategy]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.recordId != null) {
      json[r'record_id'] = this.recordId;
    } else {
      json[r'record_id'] = null;
    }
    if (this.noteId != null) {
      json[r'note_id'] = this.noteId;
    } else {
      json[r'note_id'] = null;
    }
    if (this.localVersion != null) {
      json[r'local_version'] = this.localVersion;
    } else {
      json[r'local_version'] = null;
    }
    if (this.serverVersion != null) {
      json[r'server_version'] = this.serverVersion;
    } else {
      json[r'server_version'] = null;
    }
    if (this.localData != null) {
      json[r'local_data'] = this.localData;
    } else {
      json[r'local_data'] = null;
    }
    if (this.serverData != null) {
      json[r'server_data'] = this.serverData;
    } else {
      json[r'server_data'] = null;
    }
    if (this.strategy != null) {
      json[r'strategy'] = this.strategy;
    } else {
      json[r'strategy'] = null;
    }
    return json;
  }

  /// Returns a new [Conflict] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Conflict? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return Conflict(
        recordId: mapValueOfType<String>(json, r'record_id'),
        noteId: mapValueOfType<String>(json, r'note_id'),
        localVersion: mapValueOfType<int>(json, r'local_version'),
        serverVersion: mapValueOfType<int>(json, r'server_version'),
        localData: mapValueOfType<String>(json, r'local_data'),
        serverData: mapValueOfType<String>(json, r'server_data'),
        strategy: ConflictStrategyEnum.fromJson(json[r'strategy']),
      );
    }
    return null;
  }

  static List<Conflict> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Conflict>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Conflict.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Conflict> mapFromJson(dynamic json) {
    final map = <String, Conflict>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Conflict.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Conflict-objects as value to a dart map
  static Map<String, List<Conflict>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Conflict>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Conflict.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}


class ConflictStrategyEnum {
  /// Instantiate a new enum with the provided [value].
  const ConflictStrategyEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const lastWriteWins = ConflictStrategyEnum._(r'last_write_wins');
  static const manual = ConflictStrategyEnum._(r'manual');

  /// List of all possible values in this [enum][ConflictStrategyEnum].
  static const values = <ConflictStrategyEnum>[
    lastWriteWins,
    manual,
  ];

  static ConflictStrategyEnum? fromJson(dynamic value) => ConflictStrategyEnumTypeTransformer().decode(value);

  static List<ConflictStrategyEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ConflictStrategyEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ConflictStrategyEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ConflictStrategyEnum] to String,
/// and [decode] dynamic data back to [ConflictStrategyEnum].
class ConflictStrategyEnumTypeTransformer {
  factory ConflictStrategyEnumTypeTransformer() => _instance ??= const ConflictStrategyEnumTypeTransformer._();

  const ConflictStrategyEnumTypeTransformer._();

  String encode(ConflictStrategyEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a ConflictStrategyEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ConflictStrategyEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'last_write_wins': return ConflictStrategyEnum.lastWriteWins;
        case r'manual': return ConflictStrategyEnum.manual;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [ConflictStrategyEnumTypeTransformer] instance.
  static ConflictStrategyEnumTypeTransformer? _instance;
}


