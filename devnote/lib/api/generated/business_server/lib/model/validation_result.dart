//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_business_api;

class ValidationResult {
  /// Returns a new [ValidationResult] instance.
  ValidationResult({
    this.ruleId,
    this.ruleName,
    this.passed,
    this.message,
    this.severity,
  });

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? ruleId;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? ruleName;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  bool? passed;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? message;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? severity;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ValidationResult &&
    other.ruleId == ruleId &&
    other.ruleName == ruleName &&
    other.passed == passed &&
    other.message == message &&
    other.severity == severity;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (ruleId == null ? 0 : ruleId!.hashCode) +
    (ruleName == null ? 0 : ruleName!.hashCode) +
    (passed == null ? 0 : passed!.hashCode) +
    (message == null ? 0 : message!.hashCode) +
    (severity == null ? 0 : severity!.hashCode);

  @override
  String toString() => 'ValidationResult[ruleId=$ruleId, ruleName=$ruleName, passed=$passed, message=$message, severity=$severity]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.ruleId != null) {
      json[r'rule_id'] = this.ruleId;
    } else {
      json[r'rule_id'] = null;
    }
    if (this.ruleName != null) {
      json[r'rule_name'] = this.ruleName;
    } else {
      json[r'rule_name'] = null;
    }
    if (this.passed != null) {
      json[r'passed'] = this.passed;
    } else {
      json[r'passed'] = null;
    }
    if (this.message != null) {
      json[r'message'] = this.message;
    } else {
      json[r'message'] = null;
    }
    if (this.severity != null) {
      json[r'severity'] = this.severity;
    } else {
      json[r'severity'] = null;
    }
    return json;
  }

  /// Returns a new [ValidationResult] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ValidationResult? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return ValidationResult(
        ruleId: mapValueOfType<String>(json, r'rule_id'),
        ruleName: mapValueOfType<String>(json, r'rule_name'),
        passed: mapValueOfType<bool>(json, r'passed'),
        message: mapValueOfType<String>(json, r'message'),
        severity: mapValueOfType<String>(json, r'severity'),
      );
    }
    return null;
  }

  static List<ValidationResult> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ValidationResult>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ValidationResult.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ValidationResult> mapFromJson(dynamic json) {
    final map = <String, ValidationResult>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ValidationResult.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ValidationResult-objects as value to a dart map
  static Map<String, List<ValidationResult>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ValidationResult>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ValidationResult.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

