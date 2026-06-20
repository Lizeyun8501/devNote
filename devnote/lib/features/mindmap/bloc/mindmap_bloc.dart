import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../models/mindmap_node.dart';
import '../services/mindmap_layout.dart';
import 'mindmap_event.dart';
import 'mindmap_state.dart';

// 导出 event 和 state，方便外部使用时只需导入 mindmap_bloc.dart
export 'mindmap_event.dart';
export 'mindmap_state.dart';

class MindmapBloc extends Bloc<MindmapEvent, MindmapState> {
  final String pageId;

  MindmapBloc({required this.pageId}) : super(MindmapInitial()) {
    on<LoadMindmap>(_onLoad);
    on<AddNode>(_onAddNode);
    on<UpdateNode>(_onUpdateNode);
    on<DeleteNode>(_onDeleteNode);
    on<SelectNode>(_onSelectNode);
    on<ChangeLayout>(_onChangeLayout);
    on<SaveMindmap>(_onSave);
  }

  void _onLoad(LoadMindmap event, Emitter<MindmapState> emit) {
    emit(MindmapLoading());
    // 创建默认的思维导图（含根节点）
    final rootId = const Uuid().v4();
    final root = MindmapNode(
      id: rootId,
      text: '中心主题',
      parentId: '',
      level: 0,
    );
    final data = MindmapData(
      id: event.pageId,
      title: '思维导图',
      rootId: rootId,
      nodes: {rootId: root},
    );
    emit(MindmapLoaded(data: MindmapLayout.layoutTree(data)));
  }

  void _onAddNode(AddNode event, Emitter<MindmapState> emit) {
    final state = this.state;
    if (state is! MindmapLoaded) return;

    final parent = state.data.nodes[event.parentId];
    if (parent == null) return;

    final newChildrenIds = [...parent.childrenIds, event.node.id];
    final updatedParent = parent.copyWith(childrenIds: newChildrenIds);
    final newNodes = Map<String, MindmapNode>.from(state.data.nodes)
      ..[event.parentId] = updatedParent
      ..[event.node.id] = event.node;

    final newData = state.data.copyWith(nodes: newNodes);
    final layoutData = state.layoutType == MindmapLayoutType.tree
        ? MindmapLayout.layoutTree(newData)
        : MindmapLayout.layoutRadial(newData);

    emit(state.copyWith(data: layoutData, selectedNodeId: event.node.id));
  }

  void _onUpdateNode(UpdateNode event, Emitter<MindmapState> emit) {
    final state = this.state;
    if (state is! MindmapLoaded) return;

    final newNodes = Map<String, MindmapNode>.from(state.data.nodes)
      ..[event.node.id] = event.node;
    final newData = state.data.copyWith(nodes: newNodes);
    final layoutData = state.layoutType == MindmapLayoutType.tree
        ? MindmapLayout.layoutTree(newData)
        : MindmapLayout.layoutRadial(newData);

    emit(state.copyWith(data: layoutData));
  }

  void _onDeleteNode(DeleteNode event, Emitter<MindmapState> emit) {
    final state = this.state;
    if (state is! MindmapLoaded) return;
    if (event.nodeId == state.data.rootId) return; // 不能删除根节点

    final node = state.data.nodes[event.nodeId];
    if (node == null) return;

    // 递归删除所有子节点
    final toDelete = <String>[];
    _collectDescendants(event.nodeId, state.data.nodes, toDelete);

    final newNodes = Map<String, MindmapNode>.from(state.data.nodes);
    for (final id in toDelete) {
      newNodes.remove(id);
    }
    // 从父节点的 childrenIds 中移除
    if (node.parentId.isNotEmpty) {
      final parent = newNodes[node.parentId];
      if (parent != null) {
        newNodes[parent.id] = parent.copyWith(
          childrenIds: parent.childrenIds.where((id) => id != event.nodeId).toList(),
        );
      }
    }

    final newData = state.data.copyWith(nodes: newNodes);
    final layoutData = state.layoutType == MindmapLayoutType.tree
        ? MindmapLayout.layoutTree(newData)
        : MindmapLayout.layoutRadial(newData);

    emit(state.copyWith(data: layoutData, clearSelection: true));
  }

  void _collectDescendants(
    String nodeId,
    Map<String, MindmapNode> nodes,
    List<String> result,
  ) {
    result.add(nodeId);
    final node = nodes[nodeId];
    if (node != null) {
      for (final childId in node.childrenIds) {
        _collectDescendants(childId, nodes, result);
      }
    }
  }

  void _onSelectNode(SelectNode event, Emitter<MindmapState> emit) {
    final state = this.state;
    if (state is! MindmapLoaded) return;
    if (event.nodeId.isEmpty) {
      emit(state.copyWith(clearSelection: true));
    } else {
      emit(state.copyWith(selectedNodeId: event.nodeId));
    }
  }

  void _onChangeLayout(ChangeLayout event, Emitter<MindmapState> emit) {
    final state = this.state;
    if (state is! MindmapLoaded) return;

    final layoutData = event.layoutType == MindmapLayoutType.tree
        ? MindmapLayout.layoutTree(state.data)
        : MindmapLayout.layoutRadial(state.data);

    emit(state.copyWith(data: layoutData, layoutType: event.layoutType));
  }

  void _onSave(SaveMindmap event, Emitter<MindmapState> emit) {
    final state = this.state;
    if (state is! MindmapLoaded) return;
    // TODO: 持久化 MindmapData 到笔记 content 字段
  }
}
