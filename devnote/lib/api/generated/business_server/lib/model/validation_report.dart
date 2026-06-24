//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_business_api;

class ValidationReport {
  /// Returns a new [ValidationReport] instance.
  ValidationReport({
    this.targetId,
    this.type,
    this.results = const [],
    this.passed,
  });

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? targetId;

  /// Type of validated entity (note, folder, tag, knowledge)
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? type;

  List<ValidationResult> results;

  /// Overall validation pass status
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  bool? passed;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ValidationReport &&
    other.targetId == targetId &&
    other.type == type &&
    _deepEquality.equals(other.results, results) &&
    other.passed == passed;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (targetId == null ? 0 : targetId!.hashCode) +
    (type == null ? 0 : type!.hashCode) +
    (results.hashCode) +
    (passed == null ? 0 : passed!.hashCode);

  @override
  String toString() => 'ValidationReport[targetId=$targetId, type=$type, results=$results, passed=$passed]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.targetId != null) {
      json[r'target_id'] = this.targetId;
    } else {
      json[r'target_id'] = null;
    }
    if (this.type != null) {
      json[r'type'] = this.type;
    } else {
      json[r'type'] = null;
    }
      json[r'results'] = this.results;
    if (this.passed != null) {
      json[r'passed'] = this.passed;
    } else {
      json[r'passed'] = null;
    }
    return json;
  }

  /// Returns a new [ValidationReport] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ValidationReport? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return ValidationReport(
        targetId: mapValueOfType<String>(json, r'target_id'),
        type: mapValueOfType<String>(json, r'type'),
        results: ValidationResult.listFromJson(json[r'results']),
        passed: mapValueOfType<bool>(json, r'passed'),
      );
    }
    return null;
  }

  static List<ValidationReport> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ValidationReport>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ValidationReport.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ValidationReport> mapFromJson(dynamic json) {
    final map = <String, ValidationReport>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ValidationReport.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ValidationReport-objects as value to a dart map
  static Map<String, List<ValidationReport>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ValidationReport>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ValidationReport.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

