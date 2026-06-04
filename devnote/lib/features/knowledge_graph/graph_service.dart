/// GraphService - 知识图谱关系计算与渲染服务
///
/// ## 已替换的开源模块
/// - **graphview** ([pub.dev](https://pub.dev/packages/graphview)):
///   已替代自研 CustomPaint 渲染方案，使用 FruchtermanReingoldAlgorithm 力导向布局。
///   graphview 提供更成熟的图可视化能力，支持节点拖拽、缩放、布局算法切换等。
///
/// ## 仍保留的自研部分
/// - 关系计算逻辑（邻居查询、路径查找、中心度分析、聚类检测）
/// - 图谱数据模型（GraphNodeData、GraphEdgeData、GraphData）
///
/// ## 当前实现
/// 自研图遍历算法，借鉴 Neo4j 的关系计算和 d3-force 的力导向布局。
///
/// ## 推荐的开源替代方案
/// - **force_graph** ([pub.dev](https://pub.dev/packages/force_graph)):
///   基于 d3-force 的力导向图可视化，支持动态节点和交互。
///
/// 该服务为 DevNote 提供知识图谱的构建、查询与分析能力，包括节点/边遍历、
/// 邻居发现、最短路径、相关节点推荐、子图过滤、中心性计算与社区聚类等。
///
/// ## 借鉴的开源项目
/// - **Neo4j** ([官网](https://neo4j.com/)): 借鉴其属性图模型（节点 / 关系 / 标签 / 属性）以及
///   Cypher 风格的图遍历语义（如 `MATCH ... DEPTH n` 邻居查询、最短路径函数等）。
/// - **d3-force** ([GitHub](https://github.com/d3/d3-force)): 借鉴力导向（force-directed）布局的
///   视觉表达思路，用于在 UI 层呈现知识图谱的节点位置与引力/斥力效果。
/// - **Gephi** ([官网](https://gephi.org/)): 借鉴其中心性算法（如度中心性、介数中心性、
///   接近中心性等）用于发现知识图谱中的"枢纽节点"；同时借鉴其模块度聚类（Modularity）思路。
/// - **cytoscape.js** ([官网](https://js.cytoscape.org/)): 借鉴其最短路径算法
///   （BFS / Dijkstra / A*）用于知识节点之间的关联路径发现。
///
/// ## 实现说明
/// - 后端算法实现在 Rust 端（`devnote-graph` crate），本服务通过 `Dispatch` 跨语言桥接。
/// - 所有方法均返回 `Future`，使用 FFI（外部函数接口）异步调用，避免阻塞 UI 主线程。
/// - 图数据模型 `GraphDataModel` 同时提供 `fromJson` / `toJson` 用于跨语言序列化。
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/bridge/error.dart';
import 'package:devnote/core/di/injection.dart';

/// 知识图谱中的节点类型枚举
///
/// 借鉴 Neo4j 的"标签（Label）"概念：每个节点可拥有 0..N 个类型标签，
/// 用于在过滤与可视化中区分不同实体。
enum GraphNodeType { note, tag, folder, canvas }

/// 知识图谱中的关系（边）类型枚举
///
/// 借鉴 Neo4j 的"关系类型（Relationship Type）"概念。
enum GraphEdgeType { reference, tag, parent, related }

/// 知识图谱节点模型
///
/// 借鉴 Neo4j 中节点的"属性（Property）"模型，将节点元数据扁平化存储。
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

  /// 从 JSON 反序列化（来自 Rust 端 `devnote-graph` 的 FFI 返回结果）
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

  /// 序列化为 JSON（用于跨语言桥接或持久化）
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

/// 知识图谱边模型
///
/// 借鉴 Neo4j 的"关系（Relationship）"结构：包含源节点、目标节点、关系类型与权重。
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

  /// 从 JSON 反序列化
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

  /// 序列化为 JSON
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

/// 图数据集模型
///
/// 借鉴 Neo4j 中"子图（Subgraph）"的概念：一组节点与边构成的可视化/分析单元。
class GraphDataModel {
  final List<KnowledgeNodeModel> nodes;
  final List<KnowledgeEdgeModel> edges;

  const GraphDataModel({required this.nodes, required this.edges});

  /// 从 JSON 反序列化
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

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'nodes': nodes.map((e) => e.toJson()).toList(),
      'edges': edges.map((e) => e.toJson()).toList(),
    };
  }
}

/// 图过滤条件模型
///
/// 借鉴 Neo4j Cypher 中 `WHERE` 子句的可视化建模：节点类型 / 标签 / 时间区间 / 关键字。
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

  /// 序列化为 JSON（用于跨语言桥接）
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

/// 中心性计算结果
///
/// 借鉴 Gephi 的中心性指标（Centrality）模型：表示某节点在图中的"重要性"。
class CentralityResult {
  final String nodeId;
  final double centrality;

  const CentralityResult({required this.nodeId, required this.centrality});

  /// 从 JSON 反序列化
  factory CentralityResult.fromJson(Map<String, dynamic> json) {
    return CentralityResult(
      nodeId: json['node_id'] as String,
      centrality: (json['centrality'] as num).toDouble(),
    );
  }
}

/// 社区聚类结果
///
/// 借鉴 Gephi 的模块度（Modularity）聚类算法：用于自动识别知识图谱中的主题社区。
class ClusterModel {
  final String id;
  final List<String> nodeIds;
  final String? label;

  const ClusterModel({required this.id, required this.nodeIds, this.label});

  /// 从 JSON 反序列化
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

/// 知识图谱业务服务
///
/// 作为 Flutter 侧的知识图谱 API 入口，封装了对 Rust 核心（`devnote-graph`）的
/// FFI 异步调用，对上层 UI（`KnowledgeGraphPage` / `GraphBloc`）屏蔽跨语言细节。
///
/// ## 借鉴的开源项目
/// - **Neo4j** ([官网](https://neo4j.com/)): 图遍历与子图查询语义。
/// - **d3-force** ([GitHub](https://github.com/d3/d3-force)): 力导向布局视觉表达。
/// - **Gephi** ([官网](https://gephi.org/)): 中心性算法与社区聚类（Modularity）。
/// - **cytoscape.js** ([官网](https://js.cytoscape.org/)): 最短路径算法（BFS / Dijkstra）。
class GraphService {
  final Dispatch _dispatch = getIt<Dispatch>();

  /// 构建完整的知识图谱
  ///
  /// 借鉴 Neo4j 中"全图快照"的语义：将所有笔记 / 标签 / 文件夹 / 画布节点及它们
  /// 之间的关系构建为一个完整的子图，用于全局面板渲染。
  /// **算法来源**: Neo4j 图遍历算法 ([neo4j.com](https://neo4j.com/))
  Future<GraphDataModel> buildGraph() async {
    final result = await _dispatch.asyncRequest(
      'GraphEvent.BuildGraph',
      payload: Uint8List(0),
    );
    return _parseGraphData(result);
  }

  /// 通过节点 ID 获取单个节点
  ///
  /// **算法来源**: Neo4j `MATCH (n) WHERE id(n) = $id RETURN n` 查询。
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

  /// 获取指定节点 N 度（depth）内的邻居子图
  ///
  /// 借鉴 Neo4j `MATCH (n)-[*1..depth]-(m) RETURN n, m` 的可变跳数遍历语义，
  /// 可用于"相关笔记推荐"等场景。
  /// **算法来源**: Neo4j 图遍历算法 ([neo4j.com](https://neo4j.com/))
  Future<GraphDataModel> getNeighbors(String nodeId, int depth) async {
    final payload = jsonEncode({'node_id': nodeId, 'depth': depth});
    final result = await _dispatch.asyncRequest(
      'GraphEvent.GetNeighbors',
      payload: utf8.encode(payload),
    );
    return _parseGraphData(result);
  }

  /// 获取指向指定笔记的反向链接（backlinks）
  ///
  /// 借鉴 Obsidian / Roam Research 的"反向链接"概念。
  /// **算法来源**: Neo4j 反向边查询 ([neo4j.com](https://neo4j.com/))
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

  /// 计算两个节点之间的最短路径
  ///
  /// 借鉴 cytoscape.js 的最短路径算法（基于 BFS / Dijkstra，加权图为 Dijkstra），
  /// 用于在 UI 上展示两篇笔记之间的"知识连接路径"。
  /// **算法来源**: cytoscape.js 最短路径算法 ([js.cytoscape.org](https://js.cytoscape.org/))
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

  /// 获取与指定节点相关的节点列表（Top-N 相关）
  ///
  /// 借鉴 Neo4j GDS（Graph Data Science）库中"节点相似度（Node Similarity）"算法，
  /// 借鉴 d3-force 中基于共享邻居（common neighbors）的相似度度量思想。
  /// **算法来源**:
  /// - Neo4j 图遍历算法 ([neo4j.com](https://neo4j.com/))
  /// - d3-force 共享邻居相似度 ([GitHub](https://github.com/d3/d3-force))
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

  /// 按条件过滤知识图谱，得到子图
  ///
  /// **算法来源**: Neo4j Cypher `MATCH ... WHERE ... RETURN` ([neo4j.com](https://neo4j.com/))
  Future<GraphDataModel> filterGraph(GraphFilterModel filter) async {
    final payload = jsonEncode(filter.toJson());
    final result = await _dispatch.asyncRequest(
      'GraphEvent.FilterGraph',
      payload: utf8.encode(payload),
    );
    return _parseGraphData(result);
  }

  /// 计算所有节点的中心性（识别"枢纽"节点）
  ///
  /// 借鉴 Gephi 的中心性算法：
  /// - **度中心性（Degree Centrality）**: 节点连接数 / (N-1)
  /// - **介数中心性（Betweenness Centrality）**: 通过节点的最短路径条数
  /// - **接近中心性（Closeness Centrality）**: 到其他节点平均距离的倒数
  /// **算法来源**: Gephi 中心性算法 ([gephi.org](https://gephi.org/))
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

  /// 社区聚类（自动发现知识图谱中的主题集群）
  ///
  /// 借鉴 Gephi 的 **Louvain 模块度优化算法**，将图划分为多个内部连接紧密、
  /// 外部连接稀疏的社区。Louvain 算法时间复杂度接近线性，适合大规模图。
  /// **算法来源**: Gephi Louvain 模块度聚类 ([gephi.org](https://gephi.org/))
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
