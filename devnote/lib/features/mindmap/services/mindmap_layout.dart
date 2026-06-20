import 'dart:math';
import 'dart:ui';
import '../models/mindmap_node.dart';

/// 思维导图布局算法
/// 支持两种布局：树状水平布局（左右展开）和放射布局（圆形展开）
class MindmapLayout {
  static const double _nodeWidth = 140;
  static const double _nodeHeight = 44;
  static const double _horizontalSpacing = 80; // 父子水平间距
  static const double _verticalSpacing = 16;   // 兄弟节点垂直间距

  /// 树状水平布局（根节点居中，子节点左右展开）
  static MindmapData layoutTree(MindmapData data) {
    final nodes = Map<String, MindmapNode>.from(data.nodes);
    final root = nodes[data.rootId];
    if (root == null) return data;

    // 计算每个子树的宽度（叶子节点数）
    final subtreeWidths = <String, double>{};
    _calculateSubtreeWidth(data.rootId, nodes, subtreeWidths);

    // 布局根节点
    final totalWidth = subtreeWidths[data.rootId] ?? _nodeWidth;
    nodes[data.rootId] = root.copyWith(
      position: Offset(totalWidth / 2 - _nodeWidth / 2, 0),
      size: const Size(_nodeWidth, _nodeHeight),
      color: MindmapNodeColor.blue,
    );

    // 递归布局子节点
    _layoutChildren(
      data.rootId,
      nodes,
      subtreeWidths,
      Offset(totalWidth / 2 - _nodeWidth / 2, 0),
      1,
    );

    return data.copyWith(nodes: nodes);
  }

  /// 计算子树宽度
  static double _calculateSubtreeWidth(
    String nodeId,
    Map<String, MindmapNode> nodes,
    Map<String, double> widths,
  ) {
    final node = nodes[nodeId];
    if (node == null || node.childrenIds.isEmpty) {
      widths[nodeId] = _nodeWidth;
      return _nodeWidth;
    }

    double totalWidth = 0;
    for (final childId in node.childrenIds) {
      totalWidth += _calculateSubtreeWidth(childId, nodes, widths);
      totalWidth += _verticalSpacing;
    }
    totalWidth -= _verticalSpacing; // 移除最后一个多余的间距

    // 子树宽度取子节点总宽度和自身宽度的最大值
    final width = max(totalWidth, _nodeWidth);
    widths[nodeId] = width;
    return width;
  }

  /// 递归布局子节点
  static void _layoutChildren(
    String parentId,
    Map<String, MindmapNode> nodes,
    Map<String, double> widths,
    Offset parentPosition,
    int level,
  ) {
    final parent = nodes[parentId];
    if (parent == null) return;

    final children = parent.childrenIds;
    if (children.isEmpty) return;

    // 计算子节点总宽度
    double childrenTotalWidth = 0;
    for (final childId in children) {
      childrenTotalWidth += widths[childId] ?? _nodeWidth;
      childrenTotalWidth += _verticalSpacing;
    }
    childrenTotalWidth -= _verticalSpacing;

    // 子节点起始 Y 坐标（居中对齐父节点）
    double startY = parentPosition.dy +
        _nodeHeight / 2 -
        childrenTotalWidth / 2;

    // 子节点 X 坐标（在父节点右侧）
    final childX = parentPosition.dx + _nodeWidth + _horizontalSpacing;

    // 根据层级确定颜色
    final childColor = _getColorForLevel(level);

    for (final childId in children) {
      final childWidth = widths[childId] ?? _nodeWidth;
      final childY = startY + childWidth / 2 - _nodeHeight / 2;

      final child = nodes[childId];
      if (child != null) {
        nodes[childId] = child.copyWith(
          position: Offset(childX, childY),
          size: const Size(_nodeWidth, _nodeHeight),
          color: childColor,
        );

        // 递归布局孙子节点
        _layoutChildren(
          childId,
          nodes,
          widths,
          Offset(childX, childY),
          level + 1,
        );
      }

      startY += childWidth + _verticalSpacing;
    }
  }

  /// 放射布局（根节点居中，子节点圆形展开）
  static MindmapData layoutRadial(MindmapData data) {
    final nodes = Map<String, MindmapNode>.from(data.nodes);
    final root = nodes[data.rootId];
    if (root == null) return data;

    // 根节点居中
    nodes[data.rootId] = root.copyWith(
      position: const Offset(0, 0),
      size: const Size(_nodeWidth, _nodeHeight),
      color: MindmapNodeColor.blue,
    );

    // 递归布局
    _layoutRadialChildren(
      data.rootId,
      nodes,
      0,
      2 * pi,
      1,
      180, // 第一层半径
    );

    return data.copyWith(nodes: nodes);
  }

  static void _layoutRadialChildren(
    String parentId,
    Map<String, MindmapNode> nodes,
    double startAngle,
    double endAngle,
    int level,
    double radius,
  ) {
    final parent = nodes[parentId];
    if (parent == null) return;

    final children = parent.childrenIds;
    if (children.isEmpty) return;

    final angleStep = (endAngle - startAngle) / children.length;
    final childColor = _getColorForLevel(level);

    for (var i = 0; i < children.length; i++) {
      final childId = children[i];
      final angle = startAngle + angleStep * (i + 0.5);

      final x = parent.position.dx + radius * cos(angle);
      final y = parent.position.dy + radius * sin(angle);

      final child = nodes[childId];
      if (child != null) {
        nodes[childId] = child.copyWith(
          position: Offset(x - _nodeWidth / 2, y - _nodeHeight / 2),
          size: const Size(_nodeWidth, _nodeHeight),
          color: childColor,
        );

        // 递归布局，半径递增
        final childAngleSpan = angleStep * 0.8; // 子节点角度范围缩小
        _layoutRadialChildren(
          childId,
          nodes,
          angle - childAngleSpan / 2,
          angle + childAngleSpan / 2,
          level + 1,
          radius * 0.8, // 每层半径缩小
        );
      }
    }
  }

  static MindmapNodeColor _getColorForLevel(int level) {
    switch (level) {
      case 0: return MindmapNodeColor.blue;
      case 1: return MindmapNodeColor.green;
      case 2: return MindmapNodeColor.orange;
      case 3: return MindmapNodeColor.purple;
      default: return MindmapNodeColor.grey;
    }
  }
}
