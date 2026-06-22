import '../models/mindmap_node.dart';
import 'mindmap_event.dart';

abstract class MindmapState {}

class MindmapInitial extends MindmapState {}
class MindmapLoading extends MindmapState {}

class MindmapLoaded extends MindmapState {
  final MindmapData data;
  final String? selectedNodeId;
  final MindmapLayoutType layoutType;

  MindmapLoaded({
    required this.data,
    this.selectedNodeId,
    this.layoutType = MindmapLayoutType.tree,
  });

  MindmapLoaded copyWith({
    MindmapData? data,
    String? selectedNodeId,
    bool clearSelection = false,
    MindmapLayoutType? layoutType,
  }) => MindmapLoaded(
    data: data ?? this.data,
    selectedNodeId: clearSelection ? null : (selectedNodeId ?? this.selectedNodeId),
    layoutType: layoutType ?? this.layoutType,
  );
}

class MindmapError extends MindmapState {
  final String message;
  MindmapError(this.message);
}
