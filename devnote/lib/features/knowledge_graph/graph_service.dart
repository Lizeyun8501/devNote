import 'dart:convert';
import 'dart:typed_data';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/bridge/error.dart';

enum GraphNodeType { note, tag, folder, canvas }

enum GraphEdgeType { reference, tag, parent, related }

class KnowledgeNodeModel {
  final String id;
  final String title;
  final GraphNodeType nodeType;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  const KnowledgeNodeModel({
    required this.id,
    required this.title,
    required this.nodeType,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
  });

  factory KnowledgeNodeModel.fromJson(Map<String, dynamic> json) {
    return KnowledgeNodeModel(
      id: json['id'] as String,
      title: json['title'] as String,
      nodeType: GraphNodeType.values.firstWhere(
        (e) => e.name == (json['node_type'] as String),
        orElse: () => GraphNodeType.note,
      ),
      tags: (json['tags'] as List<dynamic>).map((e) => e as String).toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'node_type': nodeType.name,
      'tags': tags,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class KnowledgeEdgeModel {
  final String id;
  final String sourceId;
  final String targetId;
  final GraphEdgeType edgeType;
  final double weight;
  final DateTime createdAt;

  const KnowledgeEdgeModel({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.edgeType,
    required this.weight,
    required this.createdAt,
  });

  factory KnowledgeEdgeModel.fromJson(Map<String, dynamic> json) {
    return KnowledgeEdgeModel(
      id: json['id'] as String,
      sourceId: json['source_id'] as String,
      targetId: json['target_id'] as String,
      edgeType: GraphEdgeType.values.firstWhere(
        (e) => e.name == (json['edge_type'] as String),
        orElse: () => GraphEdgeType.reference,
      ),
      weight: (json['weight'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source_id': sourceId,
      'target_id': targetId,
      'edge_type': edgeType.name,
      'weight': weight,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class GraphDataModel {
  final List<KnowledgeNodeModel> nodes;
  final List<KnowledgeEdgeModel> edges;

  const GraphDataModel({required this.nodes, required this.edges});

  factory GraphDataModel.fromJson(Map<String, dynamic> json) {
    return GraphDataModel(
      nodes: (json['nodes'] as List<dynamic>)
          .map((e) => KnowledgeNodeModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      edges: (json['edges'] as List<dynamic>)
          .map((e) => KnowledgeEdgeModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nodes': nodes.map((e) => e.toJson()).toList(),
      'edges': edges.map((e) => e.toJson()).toList(),
    };
  }
}

class GraphFilterModel {
  final List<GraphNodeType>? nodeTypes;
  final List<String>? tags;
  final (DateTime, DateTime)? dateRange;
  final String? searchQuery;

  const GraphFilterModel({
    this.nodeTypes,
    this.tags,
    this.dateRange,
    this.searchQuery,
  });

  Map<String, dynamic> toJson() {
    return {
      if (nodeTypes != null)
        'node_types': nodeTypes!.map((e) => e.name).toList(),
      if (tags != null) 'tags': tags,
      if (dateRange != null)
        'date_range': [
          dateRange!.$1.toIso8601String(),
          dateRange!.$2.toIso8601String(),
        ],
      if (searchQuery != null) 'search_query': searchQuery,
    };
  }
}

class CentralityResult {
  final String nodeId;
  final double centrality;

  const CentralityResult({required this.nodeId, required this.centrality});

  factory CentralityResult.fromJson(Map<String, dynamic> json) {
    return CentralityResult(
      nodeId: json['node_id'] as String,
      centrality: (json['centrality'] as num).toDouble(),
    );
  }
}

class ClusterModel {
  final String id;
  final List<String> nodeIds;
  final String? label;

  const ClusterModel({required this.id, required this.nodeIds, this.label});

  factory ClusterModel.fromJson(Map<String, dynamic> json) {
    return ClusterModel(
      id: json['id'] as String,
      nodeIds: (json['node_ids'] as List<dynamic>).map((e) => e as String).toList(),
      label: json['label'] as String?,
    );
  }
}

GraphDataModel _parseGraphData(FlowyResult<Uint8List, FlowyInternalError> result) {
  if (result is Success<Uint8List, FlowyInternalError>) {
    final json = jsonDecode(utf8.decode(result.value));
    if (json is Map<String, dynamic>) {
      return GraphDataModel.fromJson(json);
    }
    return const GraphDataModel(nodes: [], edges: []);
  }
  if (result is Failure<Uint8List, FlowyInternalError>) {
    throw Exception(result.error.message);
  }
  throw Exception('Unknown result type');
}

class GraphService {
  final Dispatch _dispatch = Dispatch.instance;

  Future<GraphDataModel> buildGraph() async {
    final result = await _dispatch.asyncRequest(
      'GraphEvent.BuildGraph',
      payload: Uint8List(0),
    );
    return _parseGraphData(result);
  }

  Future<KnowledgeNodeModel?> getNode(String nodeId) async {
    final payload = jsonEncode({'node_id': nodeId});
    final result = await _dispatch.asyncRequest(
      'GraphEvent.GetNode',
      payload: utf8.encode(payload),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is Map<String, dynamic>) {
        return KnowledgeNodeModel.fromJson(json);
      }
    }
    return null;
  }

  Future<GraphDataModel> getNeighbors(String nodeId, int depth) async {
    final payload = jsonEncode({'node_id': nodeId, 'depth': depth});
    final result = await _dispatch.asyncRequest(
      'GraphEvent.GetNeighbors',
      payload: utf8.encode(payload),
    );
    return _parseGraphData(result);
  }

  Future<List<KnowledgeEdgeModel>> getBacklinks(String noteId) async {
    final payload = jsonEncode({'note_id': noteId});
    final result = await _dispatch.asyncRequest(
      'GraphEvent.GetBacklinks',
      payload: utf8.encode(payload),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is List) {
        return json
            .map((e) => KnowledgeEdgeModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

  Future<List<String>> getShortestPath(String fromId, String toId) async {
    final payload = jsonEncode({'from_id': fromId, 'to_id': toId});
    final result = await _dispatch.asyncRequest(
      'GraphEvent.GetShortestPath',
      payload: utf8.encode(payload),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is List) {
        return json.map((e) => e as String).toList();
      }
    }
    return [];
  }

  Future<List<KnowledgeNodeModel>> getRelatedNodes(String nodeId, int limit) async {
    final payload = jsonEncode({'node_id': nodeId, 'limit': limit});
    final result = await _dispatch.asyncRequest(
      'GraphEvent.GetRelatedNodes',
      payload: utf8.encode(payload),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is List) {
        return json
            .map((e) => KnowledgeNodeModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

  Future<GraphDataModel> filterGraph(GraphFilterModel filter) async {
    final payload = jsonEncode(filter.toJson());
    final result = await _dispatch.asyncRequest(
      'GraphEvent.FilterGraph',
      payload: utf8.encode(payload),
    );
    return _parseGraphData(result);
  }

  Future<List<CentralityResult>> calculateCentrality() async {
    final result = await _dispatch.asyncRequest(
      'GraphEvent.CalculateCentrality',
      payload: Uint8List(0),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is List) {
        return json
            .map((e) => CentralityResult.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

  Future<List<ClusterModel>> detectClusters() async {
    final result = await _dispatch.asyncRequest(
      'GraphEvent.DetectClusters',
      payload: Uint8List(0),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is List) {
        return json
            .map((e) => ClusterModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }
}
