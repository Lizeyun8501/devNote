import 'dart:convert';
import 'dart:typed_data';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/bridge/error.dart';
import 'package:devnote/core/di/injection.dart';

enum NodeType { note, image, file, link, group }

enum LayoutType { grid, force, hierarchical }

enum AlignmentType { left, center, right, top, middle, bottom }

enum DistributeDirection { horizontal, vertical }

enum Side { top, bottom, left, right }

class CanvasNodeModel {
  final String id;
  final NodeType nodeType;
  final double x;
  final double y;
  final double width;
  final double height;
  final String? content;
  final String? color;
  final String? file;

  const CanvasNodeModel({
    required this.id,
    required this.nodeType,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.content,
    this.color,
    this.file,
  });

  CanvasNodeModel copyWith({
    String? id,
    NodeType? nodeType,
    double? x,
    double? y,
    double? width,
    double? height,
    String? content,
    String? color,
    String? file,
  }) {
    return CanvasNodeModel(
      id: id ?? this.id,
      nodeType: nodeType ?? this.nodeType,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      content: content ?? this.content,
      color: color ?? this.color,
      file: file ?? this.file,
    );
  }

  factory CanvasNodeModel.fromJson(Map<String, dynamic> json) {
    return CanvasNodeModel(
      id: json['id'] as String,
      nodeType: NodeType.values.firstWhere(
        (e) => e.name == (json['type'] as String),
        orElse: () => NodeType.note,
      ),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      content: json['content'] as String?,
      color: json['color'] as String?,
      file: json['file'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': nodeType.name,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      if (content != null) 'content': content,
      if (color != null) 'color': color,
      if (file != null) 'file': file,
    };
  }
}

class CanvasEdgeModel {
  final String id;
  final String fromNode;
  final String toNode;
  final String? label;
  final String? color;
  final Side? fromSide;
  final Side? toSide;

  const CanvasEdgeModel({
    required this.id,
    required this.fromNode,
    required this.toNode,
    this.label,
    this.color,
    this.fromSide,
    this.toSide,
  });

  factory CanvasEdgeModel.fromJson(Map<String, dynamic> json) {
    return CanvasEdgeModel(
      id: json['id'] as String,
      fromNode: json['fromNode'] as String,
      toNode: json['toNode'] as String,
      label: json['label'] as String?,
      color: json['color'] as String?,
      fromSide: json['fromSide'] != null
          ? Side.values.firstWhere(
              (e) => e.name == (json['fromSide'] as String),
              orElse: () => Side.right,
            )
          : null,
      toSide: json['toSide'] != null
          ? Side.values.firstWhere(
              (e) => e.name == (json['toSide'] as String),
              orElse: () => Side.left,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fromNode': fromNode,
      'toNode': toNode,
      if (label != null) 'label': label,
      if (color != null) 'color': color,
      if (fromSide != null) 'fromSide': fromSide!.name,
      if (toSide != null) 'toSide': toSide!.name,
    };
  }
}

class CanvasData {
  final List<CanvasNodeModel> nodes;
  final List<CanvasEdgeModel> edges;

  const CanvasData({required this.nodes, required this.edges});

  factory CanvasData.fromJson(Map<String, dynamic> json) {
    return CanvasData(
      nodes: (json['nodes'] as List<dynamic>)
          .map((e) => CanvasNodeModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      edges: (json['edges'] as List<dynamic>)
          .map((e) => CanvasEdgeModel.fromJson(e as Map<String, dynamic>))
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

CanvasData _parseCanvasData(FlowyResult<Uint8List, FlowyInternalError> result) {
  if (result is Success<Uint8List, FlowyInternalError>) {
    final json = jsonDecode(utf8.decode(result.value));
    if (json is Map<String, dynamic>) {
      return CanvasData.fromJson(json);
    }
    return const CanvasData(nodes: [], edges: []);
  }
  if (result is Failure<Uint8List, FlowyInternalError>) {
    throw Exception(result.error.message);
  }
  throw Exception('Unknown result type');
}

class CanvasService {
  final Dispatch _dispatch = getIt<Dispatch>();

  Future<String> createCanvas() async {
    final result = await _dispatch.asyncRequest(
      'CanvasEvent.CreateCanvas',
      payload: Uint8List(0),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      return utf8.decode(result.value);
    }
    if (result is Failure<Uint8List, FlowyInternalError>) {
      throw Exception(result.error.message);
    }
    throw Exception('Unknown result type');
  }

  Future<CanvasData> getCanvas(String canvasId) async {
    final payload = jsonEncode({'canvas_id': canvasId});
    final result = await _dispatch.asyncRequest(
      'CanvasEvent.GetCanvas',
      payload: utf8.encode(payload),
    );
    return _parseCanvasData(result);
  }

  Future<void> addNode(String canvasId, CanvasNodeModel node) async {
    final payload = jsonEncode({
      'canvas_id': canvasId,
      'node': node.toJson(),
    });
    await _dispatch.asyncRequest(
      'CanvasEvent.AddNode',
      payload: utf8.encode(payload),
    );
  }

  Future<void> removeNode(String canvasId, String nodeId) async {
    final payload = jsonEncode({
      'canvas_id': canvasId,
      'node_id': nodeId,
    });
    await _dispatch.asyncRequest(
      'CanvasEvent.RemoveNode',
      payload: utf8.encode(payload),
    );
  }

  Future<void> moveNode(String canvasId, String nodeId, double x, double y) async {
    final payload = jsonEncode({
      'canvas_id': canvasId,
      'node_id': nodeId,
      'x': x,
      'y': y,
    });
    await _dispatch.asyncRequest(
      'CanvasEvent.MoveNode',
      payload: utf8.encode(payload),
    );
  }

  Future<void> resizeNode(String canvasId, String nodeId, double width, double height) async {
    final payload = jsonEncode({
      'canvas_id': canvasId,
      'node_id': nodeId,
      'width': width,
      'height': height,
    });
    await _dispatch.asyncRequest(
      'CanvasEvent.ResizeNode',
      payload: utf8.encode(payload),
    );
  }

  Future<void> addEdge(String canvasId, CanvasEdgeModel edge) async {
    final payload = jsonEncode({
      'canvas_id': canvasId,
      'edge': edge.toJson(),
    });
    await _dispatch.asyncRequest(
      'CanvasEvent.AddEdge',
      payload: utf8.encode(payload),
    );
  }

  Future<void> removeEdge(String canvasId, String edgeId) async {
    final payload = jsonEncode({
      'canvas_id': canvasId,
      'edge_id': edgeId,
    });
    await _dispatch.asyncRequest(
      'CanvasEvent.RemoveEdge',
      payload: utf8.encode(payload),
    );
  }

  Future<CanvasData> autoLayout(String canvasId, LayoutType layoutType) async {
    final payload = jsonEncode({
      'canvas_id': canvasId,
      'layout_type': layoutType.name,
    });
    final result = await _dispatch.asyncRequest(
      'CanvasEvent.AutoLayout',
      payload: utf8.encode(payload),
    );
    return _parseCanvasData(result);
  }

  Future<void> saveCanvas(String canvasId, String path) async {
    final payload = jsonEncode({
      'canvas_id': canvasId,
      'path': path,
    });
    await _dispatch.asyncRequest(
      'CanvasEvent.SaveCanvas',
      payload: utf8.encode(payload),
    );
  }

  Future<String> loadCanvas(String path) async {
    final payload = jsonEncode({'path': path});
    final result = await _dispatch.asyncRequest(
      'CanvasEvent.LoadCanvas',
      payload: utf8.encode(payload),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      return utf8.decode(result.value);
    }
    if (result is Failure<Uint8List, FlowyInternalError>) {
      throw Exception(result.error.message);
    }
    throw Exception('Unknown result type');
  }
}
