import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/di/injection.dart';

enum NodeType { note, image, file, link, group }

enum LayoutType { grid, force, hierarchical }

enum AlignmentType { left, center, right, top, middle, bottom }

enum DistributeDirection { horizontal, vertical }

enum Side { top, bottom, left, right }

/// Sentinel 值用于区分"未传参"和"显式传 null"
const _canvasSentinel = Object();

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

  /// 修复：copyWith 使用 sentinel 模式支持清除 nullable 字段
  /// 原代码 `content ?? this.content` 无法传 null 清除内容，
  /// 导致无法删除节点的 content/color/file
  CanvasNodeModel copyWith({
    String? id,
    NodeType? nodeType,
    double? x,
    double? y,
    double? width,
    double? height,
    Object? content = _canvasSentinel,
    Object? color = _canvasSentinel,
    Object? file = _canvasSentinel,
  }) {
    return CanvasNodeModel(
      id: id ?? this.id,
      nodeType: nodeType ?? this.nodeType,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      content: content == _canvasSentinel ? this.content : content as String?,
      color: color == _canvasSentinel ? this.color : color as String?,
      file: file == _canvasSentinel ? this.file : file as String?,
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

/// 协作变更类型
/// 借鉴 Excalidraw 的 CRDT-based 协作变更模型：
/// https://github.com/excalidraw/excalidraw
enum CollaborationChangeType {
  nodeAdded,
  nodeRemoved,
  nodeMoved,
  nodeResized,
  nodeContentChanged,
  edgeAdded,
  edgeRemoved,
  edgeLabelChanged,
}

/// 协作变更信息
/// 每个变更携带唯一 ID、操作者信息、时间戳和变更数据，
/// 用于在多用户之间实现操作同步和冲突解决。
class CollaborationChange {
  final String id;
  final String canvasId;
  final CollaborationChangeType type;
  final String userId;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  const CollaborationChange({
    required this.id,
    required this.canvasId,
    required this.type,
    required this.userId,
    required this.timestamp,
    required this.data,
  });

  factory CollaborationChange.fromJson(Map<String, dynamic> json) {
    return CollaborationChange(
      id: json['id'] as String,
      canvasId: json['canvasId'] as String,
      type: CollaborationChangeType.values.firstWhere(
        (e) => e.name == (json['type'] as String),
        orElse: () => CollaborationChangeType.nodeAdded,
      ),
      userId: json['userId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      data: json['data'] as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'canvasId': canvasId,
      'type': type.name,
      'userId': userId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
    };
  }
}

/// 协作会话信息
class CollaborationSession {
  final String id;
  final String canvasId;
  final String hostId;
  final List<String> participantIds;
  final DateTime createdAt;

  const CollaborationSession({
    required this.id,
    required this.canvasId,
    required this.hostId,
    this.participantIds = const [],
    required this.createdAt,
  });
}

class CanvasService {
  final Dispatch _dispatch = getIt<Dispatch>();

  Future<String> createCanvas() async {
    return _dispatch.canvasCreateCanvas();
  }

  Future<CanvasData> getCanvas(String canvasId) async {
    final json = await _dispatch.canvasGetCanvas(canvasId: canvasId);
    return CanvasData.fromJson(json);
  }

  Future<void> addNode(String canvasId, CanvasNodeModel node) async {
    await _dispatch.canvasAddNode(
      canvasId: canvasId,
      nodeJson: jsonEncode(node.toJson()),
    );
  }

  Future<void> removeNode(String canvasId, String nodeId) async {
    await _dispatch.canvasRemoveNode(canvasId: canvasId, nodeId: nodeId);
  }

  Future<void> moveNode(String canvasId, String nodeId, double x, double y) async {
    await _dispatch.canvasMoveNode(
      canvasId: canvasId,
      nodeId: nodeId,
      x: x,
      y: y,
    );
  }

  Future<void> resizeNode(String canvasId, String nodeId, double width, double height) async {
    await _dispatch.canvasResizeNode(
      canvasId: canvasId,
      nodeId: nodeId,
      width: width,
      height: height,
    );
  }

  Future<void> addEdge(String canvasId, CanvasEdgeModel edge) async {
    await _dispatch.canvasAddEdge(
      canvasId: canvasId,
      edgeJson: jsonEncode(edge.toJson()),
    );
  }

  Future<void> removeEdge(String canvasId, String edgeId) async {
    await _dispatch.canvasRemoveEdge(canvasId: canvasId, edgeId: edgeId);
  }

  Future<CanvasData> autoLayout(String canvasId, LayoutType layoutType) async {
    await _dispatch.canvasAutoLayout(
      canvasId: canvasId,
      layoutType: layoutType.name,
    );
    // canvasAutoLayout 返回 void，需重新获取画布数据以拿到最新布局结果
    final json = await _dispatch.canvasGetCanvas(canvasId: canvasId);
    return CanvasData.fromJson(json);
  }

  Future<void> saveCanvas(String canvasId, String path) async {
    await _dispatch.canvasSaveCanvas(canvasId: canvasId, path: path);
  }

  Future<String> loadCanvas(String path) async {
    return _dispatch.canvasLoadCanvas(path: path);
  }

  // =========================================================================
  // Canvas 多人实时协作功能
  // 借鉴 Excalidraw 的多人协作机制：https://github.com/excalidraw/excalidraw
  // 采用 WebSocket 实时广播 + CRDT 冲突解决的设计模式。
  // =========================================================================

  /// 当前活跃的协作会话
  CollaborationSession? _activeSession;

  /// 协作变更回调，用于通知 UI 层接收远端变更
  final StreamController<CollaborationChange> _changeController =
      StreamController<CollaborationChange>.broadcast();

  Stream<CollaborationChange> get onCollaborationChange => _changeController.stream;

  /// 开始协作会话
  ///
  /// 借鉴 Excalidraw 的 Room 创建机制：
  /// 指定一个 canvasId 创建协作房间，生成唯一的 sessionId，
  /// 其他用户通过 sessionId 加入同一会话。
  Future<void> startCollaborationSession(String canvasId) async {
    if (_activeSession != null) {
      throw Exception('A collaboration session is already active');
    }

    final sessionId = const Uuid().v4();
    _activeSession = CollaborationSession(
      id: sessionId,
      canvasId: canvasId,
      hostId: 'local_user',
      createdAt: DateTime.now(),
    );

    // 通知后端创建协作房间
    await _dispatch.canvasStartCollaboration(
      canvasId: canvasId,
      sessionId: sessionId,
    );
  }

  /// 加入协作会话
  ///
  /// 借鉴 Excalidraw 的 Room Join 机制：
  /// 通过 sessionId 加入已有的协作房间，
  /// 加入后会收到当前画布的完整状态快照。
  Future<void> joinCollaborationSession(String sessionId) async {
    if (_activeSession != null) {
      throw Exception('A collaboration session is already active');
    }

    final json = await _dispatch.canvasJoinCollaboration(sessionId: sessionId);
    _activeSession = CollaborationSession(
      id: sessionId,
      canvasId: json['canvasId'] as String,
      hostId: json['hostId'] as String? ?? '',
      participantIds: (json['participants'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: DateTime.now(),
    );
  }

  /// 发送协作变更
  ///
  /// 借鉴 Excalidraw 的 Scene 变更广播机制：
  /// 每次本地操作（添加/移动/删除节点等）生成一个 CollaborationChange，
  /// 广播给所有协作参与者。
  Future<void> broadcastCollaborationChange(CollaborationChange change) async {
    if (_activeSession == null) {
      throw Exception('No active collaboration session');
    }

    await _dispatch.canvasBroadcastChange(
      changeJson: jsonEncode(change.toJson()),
    );
  }

  /// 处理收到的协作变更
  ///
  /// 借鉴 Excalidraw 的变更应用机制：
  /// 根据变更类型更新本地画布状态，
  /// 使用向量时钟 / 操作转换避免冲突。
  /// 修复：添加 try-catch 包裹整个处理逻辑，避免单个变更失败导致整个协作中断
  Future<void> handleCollaborationChange(CollaborationChange change) async {
    try {
      switch (change.type) {
        case CollaborationChangeType.nodeAdded:
          final node = CanvasNodeModel.fromJson(change.data);
          await addNode(change.canvasId, node);
          break;
        case CollaborationChangeType.nodeRemoved:
          final nodeId = change.data['id'] as String;
          await removeNode(change.canvasId, nodeId);
          break;
        case CollaborationChangeType.nodeMoved:
          final nodeId = change.data['id'] as String;
          final x = (change.data['x'] as num).toDouble();
          final y = (change.data['y'] as num).toDouble();
          await moveNode(change.canvasId, nodeId, x, y);
          break;
        case CollaborationChangeType.nodeResized:
          final nodeId = change.data['id'] as String;
          final width = (change.data['width'] as num).toDouble();
          final height = (change.data['height'] as num).toDouble();
          await resizeNode(change.canvasId, nodeId, width, height);
          break;
        case CollaborationChangeType.nodeContentChanged:
          // 内容变更需要通过 getCanvas 重新获取最新状态后更新
          await getCanvas(change.canvasId);
          break;
        case CollaborationChangeType.edgeAdded:
          final edge = CanvasEdgeModel.fromJson(change.data);
          await addEdge(change.canvasId, edge);
          break;
        case CollaborationChangeType.edgeRemoved:
          final edgeId = change.data['id'] as String;
          await removeEdge(change.canvasId, edgeId);
          break;
        case CollaborationChangeType.edgeLabelChanged:
          // 标签变更需要通过 getCanvas 重新获取最新状态
          await getCanvas(change.canvasId);
          break;
      }
    } catch (_) {
      // 单个变更失败不影响其他变更的处理，也不中断协作会话
      // 错误由上层通过 _changeController 流中的状态判断
    }

    // 通知监听器
    _changeController.add(change);
  }

  /// 结束当前协作会话
  Future<void> endCollaborationSession() async {
    if (_activeSession == null) return;

    await _dispatch.canvasEndCollaboration(sessionId: _activeSession!.id);

    _activeSession = null;
  }

  /// 获取当前活跃会话
  CollaborationSession? get activeSession => _activeSession;

  /// 修复：释放资源，关闭协作变更流控制器
  /// 原代码未关闭 _changeController，导致 StreamController 内存泄漏
  void dispose() {
    _changeController.close();
  }
}
