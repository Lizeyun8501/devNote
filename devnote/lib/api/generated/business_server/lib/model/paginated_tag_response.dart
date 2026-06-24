//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_business_api;

class PaginatedTagResponse {
  /// Returns a new [PaginatedTagResponse] instance.
  PaginatedTagResponse({
    this.data = const [],
    this.total,
    this.page,
    this.pageSize,
    this.totalPages,
  });

  List<TagMeta> data;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? total;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? page;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? pageSize;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? totalPages;

  @override
  bool operator ==(Object other) => identical(this, other) || other is PaginatedTagResponse &&
    _deepEquality.equals(other.data, data) &&
    other.total == total &&
    other.page == page &&
    other.pageSize == pageSize &&
    other.totalPages == totalPages;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (data.hashCode) +
    (total == null ? 0 : total!.hashCode) +
    (page == null ? 0 : page!.hashCode) +
    (pageSize == null ? 0 : pageSize!.hashCode) +
    (totalPages == null ? 0 : totalPages!.hashCode);

  @override
  String toString() => 'PaginatedTagResponse[data=$data, total=$total, page=$page, pageSize=$pageSize, totalPages=$totalPages]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'data'] = this.data;
    if (this.total != null) {
      json[r'total'] = this.total;
    } else {
      json[r'total'] = null;
    }
    if (this.page != null) {
      json[r'page'] = this.page;
    } else {
      json[r'page'] = null;
    }
    if (this.pageSize != null) {
      json[r'page_size'] = this.pageSize;
    } else {
      json[r'page_size'] = null;
    }
    if (this.totalPages != null) {
      json[r'total_pages'] = this.totalPages;
    } else {
      json[r'total_pages'] = null;
    }
    return json;
  }

  /// Returns a new [PaginatedTagResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static PaginatedTagResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return PaginatedTagResponse(
        data: TagMeta.listFromJson(json[r'data']),
        total: mapValueOfType<int>(json, r'total'),
        page: mapValueOfType<int>(json, r'page'),
        pageSize: mapValueOfType<int>(json, r'page_size'),
        totalPages: mapValueOfType<int>(json, r'total_pages'),
      );
    }
    return null;
  }

  static List<PaginatedTagResponse> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <PaginatedTagResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = PaginatedTagResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, PaginatedTagResponse> mapFromJson(dynamic json) {
    final map = <String, PaginatedTagResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = PaginatedTagResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of PaginatedTagResponse-objects as value to a dart map
  static Map<String, List<PaginatedTagResponse>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<PaginatedTagResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = PaginatedTagResponse.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

