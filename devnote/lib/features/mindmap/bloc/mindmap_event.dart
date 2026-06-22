import '../models/mindmap_node.dart';

abstract class MindmapEvent {}

class LoadMindmap extends MindmapEvent {
  final String pageId;
  LoadMindmap(this.pageId);
}

class AddNode extends MindmapEvent {
  final MindmapNode node;
  final String parentId;
  AddNode(this.node, this.parentId);
}

class UpdateNode extends MindmapEvent {
  final MindmapNode node;
  UpdateNode(this.node);
}

class DeleteNode extends MindmapEvent {
  final String nodeId;
  DeleteNode(this.nodeId);
}

class SelectNode extends MindmapEvent {
  final String nodeId;
  SelectNode(this.nodeId);
}

class ChangeLayout extends MindmapEvent {
  final MindmapLayoutType layoutType;
  ChangeLayout(this.layoutType);
}

class SaveMindmap extends MindmapEvent {}

enum MindmapLayoutType { tree, radial }
