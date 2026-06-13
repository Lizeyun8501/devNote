import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/knowledge_graph/bloc/graph_event.dart';
import 'package:devnote/features/knowledge_graph/bloc/graph_state.dart';
import 'package:devnote/features/knowledge_graph/graph_service.dart';

class GraphBloc extends Bloc<GraphEvent, GraphState> {
  final GraphService _graphService;

  GraphBloc(this._graphService) : super(const GraphInitial()) {
    on<LoadGraph>(_onLoadGraph);
    on<GetNeighbors>(_onGetNeighbors);
    on<GetBacklinks>(_onGetBacklinks);
    on<GetShortestPath>(_onGetShortestPath);
    on<GetRelatedNodes>(_onGetRelatedNodes);
    on<FilterGraph>(_onFilterGraph);
    on<CalculateCentrality>(_onCalculateCentrality);
    on<DetectClusters>(_onDetectClusters);
    on<SelectGraphNode>(_onSelectGraphNode);
    on<MoveGraphNode>(_onMoveGraphNode);
  }

  Future<void> _onLoadGraph(LoadGraph event, Emitter<GraphState> emit) async {
    emit(const GraphLoading());
    try {
      final data = await _graphService.buildGraph();
      final positions = _calculateForceLayout(data);
      emit(GraphLoaded(data: data, positions: positions));
    } catch (e) {
      emit(GraphError(e.toString()));
    }
  }

  Future<void> _onGetNeighbors(GetNeighbors event, Emitter<GraphState> emit) async {
    try {
      final data = await _graphService.getNeighbors(event.nodeId, event.depth);
      final positions = _calculateForceLayout(data);
      emit(GraphLoaded(data: data, positions: positions, selectedNodeId: event.nodeId));
    } catch (e) {
      emit(GraphError(e.toString()));
    }
  }

  Future<void> _onGetBacklinks(GetBacklinks event, Emitter<GraphState> emit) async {
    final currentState = state;
    if (currentState is! GraphLoaded) return;
    try {
      // 修复：emit 返回的反向链接结果到状态，原代码丢弃了结果
      final backlinks = await _graphService.getBacklinks(event.noteId);
      emit(currentState.copyWith(backlinks: backlinks));
    } catch (e) {
      emit(GraphError(e.toString()));
    }
  }

  Future<void> _onGetShortestPath(GetShortestPath event, Emitter<GraphState> emit) async {
    try {
      // 修复：emit 返回的最短路径结果到状态，原代码丢弃了结果
      final path = await _graphService.getShortestPath(event.fromId, event.toId);
      // emit 最短路径到当前已加载的图状态中
      final currentState = state;
      if (currentState is GraphLoaded) {
        emit(currentState.copyWith(shortestPath: path));
      }
    } catch (e) {
      emit(GraphError(e.toString()));
    }
  }

  Future<void> _onGetRelatedNodes(GetRelatedNodes event, Emitter<GraphState> emit) async {
    try {
      // 修复：emit 返回的相关节点结果到状态，原代码丢弃了结果
      final relatedNodes = await _graphService.getRelatedNodes(event.nodeId, event.limit);
      final currentState = state;
      if (currentState is GraphLoaded) {
        emit(currentState.copyWith(relatedNodes: relatedNodes));
      }
    } catch (e) {
      emit(GraphError(e.toString()));
    }
  }

  Future<void> _onFilterGraph(FilterGraph event, Emitter<GraphState> emit) async {
    emit(const GraphLoading());
    try {
      final data = await _graphService.filterGraph(event.filter);
      final positions = _calculateForceLayout(data);
      emit(GraphLoaded(data: data, positions: positions));
    } catch (e) {
      emit(GraphError(e.toString()));
    }
  }

  Future<void> _onCalculateCentrality(CalculateCentrality event, Emitter<GraphState> emit) async {
    final currentState = state;
    if (currentState is! GraphLoaded) return;
    try {
      final centrality = await _graphService.calculateCentrality();
      emit(currentState.copyWith(centrality: centrality));
    } catch (e) {
      emit(GraphError(e.toString()));
    }
  }

  Future<void> _onDetectClusters(DetectClusters event, Emitter<GraphState> emit) async {
    final currentState = state;
    if (currentState is! GraphLoaded) return;
    try {
      final clusters = await _graphService.detectClusters();
      emit(currentState.copyWith(clusters: clusters));
    } catch (e) {
      emit(GraphError(e.toString()));
    }
  }

  void _onSelectGraphNode(SelectGraphNode event, Emitter<GraphState> emit) {
    final currentState = state;
    if (currentState is! GraphLoaded) return;
    emit(currentState.copyWith(selectedNodeId: event.nodeId));
  }

  void _onMoveGraphNode(MoveGraphNode event, Emitter<GraphState> emit) {
    final currentState = state;
    if (currentState is! GraphLoaded) return;
    final updatedPositions = currentState.positions.map((p) {
      if (p.nodeId == event.nodeId) {
        return p.copyWith(x: event.x, y: event.y);
      }
      return p;
    }).toList();
    emit(currentState.copyWith(positions: updatedPositions));
  }

  List<NodePosition> _calculateForceLayout(GraphDataModel data) {
    if (data.nodes.isEmpty) return [];

    final positions = <String, (double, double)>{};
    final random = Random(42);
    const center = 5000.0;

    for (final node in data.nodes) {
      positions[node.id] = (
        center + (random.nextDouble() - 0.5) * 400,
        center + (random.nextDouble() - 0.5) * 400,
      );
    }

    const iterations = 80;
    const k = 200.0;
    const gravity = 0.01;
    const damping = 0.9;
    final vx = <String, double>{};
    final vy = <String, double>{};

    for (final id in positions.keys) {
      vx[id] = 0.0;
      vy[id] = 0.0;
    }

    for (var i = 0; i < iterations; i++) {
      final ids = positions.keys.toList();
      for (var a = 0; a < ids.length; a++) {
        for (var b = a + 1; b < ids.length; b++) {
          final ax = positions[ids[a]]!.$1;
          final ay = positions[ids[a]]!.$2;
          final bx = positions[ids[b]]!.$1;
          final by = positions[ids[b]]!.$2;
          final dx = bx - ax;
          final dy = by - ay;
          final dist = sqrt(dx * dx + dy * dy).clamp(1.0, double.infinity);
          final force = k * k / dist;
          final fx = dx / dist * force;
          final fy = dy / dist * force;
          vx[ids[a]] = vx[ids[a]]! - fx;
          vy[ids[a]] = vy[ids[a]]! - fy;
          vx[ids[b]] = vx[ids[b]]! + fx;
          vy[ids[b]] = vy[ids[b]]! + fy;
        }
      }

      for (final edge in data.edges) {
        final sx = positions[edge.sourceId]?.$1;
        final sy = positions[edge.sourceId]?.$2;
        final tx = positions[edge.targetId]?.$1;
        final ty = positions[edge.targetId]?.$2;
        if (sx != null && sy != null && tx != null && ty != null) {
          final dx = tx - sx;
          final dy = ty - sy;
          final dist = sqrt(dx * dx + dy * dy).clamp(1.0, double.infinity);
          final force = (dist - k) * 0.05;
          final fx = dx / dist * force;
          final fy = dy / dist * force;
          vx[edge.sourceId] = vx[edge.sourceId]! + fx;
          vy[edge.sourceId] = vy[edge.sourceId]! + fy;
          vx[edge.targetId] = vx[edge.targetId]! - fx;
          vy[edge.targetId] = vy[edge.targetId]! - fy;
        }
      }

      for (final id in ids) {
        final (px, py) = positions[id]!;
        vx[id] = (vx[id]! - px * gravity) * damping;
        vy[id] = (vy[id]! - py * gravity) * damping;
        positions[id] = (px + vx[id]!, py + vy[id]!);
      }
    }

    return positions.entries
        .map((e) => NodePosition(nodeId: e.key, x: e.value.$1, y: e.value.$2))
        .toList();
  }
}
