//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of devnote_business_api;

class GraphMetrics {
  /// Returns a new [GraphMetrics] instance.
  GraphMetrics({
    this.totalNodes,
    this.totalEdges,
    this.density,
    this.orphanCount,
    this.clusterCount,
    this.avgDegree,
    this.degreeCentrality = const {},
    this.pageRank = const {},
    this.betweenness = const {},
    this.clusters = const {},
  });

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? totalNodes;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? totalEdges;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  double? density;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? orphanCount;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  int? clusterCount;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  double? avgDegree;

  Map<String, double> degreeCentrality;

  Map<String, double> pageRank;

  Map<String, double> betweenness;

  Map<String, List<String>> clusters;

  @override
  bool operator ==(Object other) => identical(this, other) || other is GraphMetrics &&
    other.totalNodes == totalNodes &&
    other.totalEdges == totalEdges &&
    other.density == density &&
    other.orphanCount == orphanCount &&
    other.clusterCount == clusterCount &&
    other.avgDegree == avgDegree &&
    _deepEquality.equals(other.degreeCentrality, degreeCentrality) &&
    _deepEquality.equals(other.pageRank, pageRank) &&
    _deepEquality.equals(other.betweenness, betweenness) &&
    _deepEquality.equals(other.clusters, clusters);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (totalNodes == null ? 0 : totalNodes!.hashCode) +
    (totalEdges == null ? 0 : totalEdges!.hashCode) +
    (density == null ? 0 : density!.hashCode) +
    (orphanCount == null ? 0 : orphanCount!.hashCode) +
    (clusterCount == null ? 0 : clusterCount!.hashCode) +
    (avgDegree == null ? 0 : avgDegree!.hashCode) +
    (degreeCentrality.hashCode) +
    (pageRank.hashCode) +
    (betweenness.hashCode) +
    (clusters.hashCode);

  @override
  String toString() => 'GraphMetrics[totalNodes=$totalNodes, totalEdges=$totalEdges, density=$density, orphanCount=$orphanCount, clusterCount=$clusterCount, avgDegree=$avgDegree, degreeCentrality=$degreeCentrality, pageRank=$pageRank, betweenness=$betweenness, clusters=$clusters]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.totalNodes != null) {
      json[r'total_nodes'] = this.totalNodes;
    } else {
      json[r'total_nodes'] = null;
    }
    if (this.totalEdges != null) {
      json[r'total_edges'] = this.totalEdges;
    } else {
      json[r'total_edges'] = null;
    }
    if (this.density != null) {
      json[r'density'] = this.density;
    } else {
      json[r'density'] = null;
    }
    if (this.orphanCount != null) {
      json[r'orphan_count'] = this.orphanCount;
    } else {
      json[r'orphan_count'] = null;
    }
    if (this.clusterCount != null) {
      json[r'cluster_count'] = this.clusterCount;
    } else {
      json[r'cluster_count'] = null;
    }
    if (this.avgDegree != null) {
      json[r'avg_degree'] = this.avgDegree;
    } else {
      json[r'avg_degree'] = null;
    }
      json[r'degree_centrality'] = this.degreeCentrality;
      json[r'page_rank'] = this.pageRank;
      json[r'betweenness'] = this.betweenness;
      json[r'clusters'] = this.clusters;
    return json;
  }

  /// Returns a new [GraphMetrics] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static GraphMetrics? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return GraphMetrics(
        totalNodes: mapValueOfType<int>(json, r'total_nodes'),
        totalEdges: mapValueOfType<int>(json, r'total_edges'),
        density: mapValueOfType<double>(json, r'density'),
        orphanCount: mapValueOfType<int>(json, r'orphan_count'),
        clusterCount: mapValueOfType<int>(json, r'cluster_count'),
        avgDegree: mapValueOfType<double>(json, r'avg_degree'),
        degreeCentrality: mapCastOfType<String, double>(json, r'degree_centrality') ?? const {},
        pageRank: mapCastOfType<String, double>(json, r'page_rank') ?? const {},
        betweenness: mapCastOfType<String, double>(json, r'betweenness') ?? const {},
        clusters: json[r'clusters'] == null
          ? const {}
            : (json[r'clusters'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v == null ? const <String>[] : (v as List).map((value) => value as String).toList(growable: false))),
      );
    }
    return null;
  }

  static List<GraphMetrics> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <GraphMetrics>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = GraphMetrics.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, GraphMetrics> mapFromJson(dynamic json) {
    final map = <String, GraphMetrics>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = GraphMetrics.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of GraphMetrics-objects as value to a dart map
  static Map<String, List<GraphMetrics>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<GraphMetrics>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = GraphMetrics.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
  };
}

