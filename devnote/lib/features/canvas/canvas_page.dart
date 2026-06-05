import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/canvas/bloc/canvas_bloc.dart';
import 'package:devnote/features/canvas/bloc/canvas_event.dart';
import 'package:devnote/features/canvas/bloc/canvas_state.dart';
import 'package:devnote/features/canvas/canvas_service.dart';
import 'package:devnote/features/canvas/widgets/canvas_node_widget.dart';
import 'package:devnote/features/canvas/widgets/canvas_edge_widget.dart';
import 'package:devnote/features/canvas/widgets/canvas_toolbar.dart';

/// Canvas 无限画布组件
/// 
/// 借鉴: Obsidian Canvas (https://github.com/obsidianmd/obsidian-canvas)
/// - 画布数据模型 (nodes + edges JSON)
/// - 自由拖拽与缩放
/// - 节点连接与布局
/// 
/// 借鉴: Excalidraw 视口裁剪 (https://github.com/excalidraw/excalidraw)
/// - 仅渲染视口可见节点
/// - 视口 padding 预加载
class CanvasPage extends StatelessWidget {
  const CanvasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CanvasBloc(CanvasService()),
      child: const _CanvasView(),
    );
  }
}

class _CanvasView extends StatefulWidget {
  const _CanvasView();

  @override
  State<_CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<_CanvasView> {
  final TransformationController _transformationController = TransformationController();
  Offset _dragOffset = Offset.zero;
  String? _draggingNodeId;
  String? _resizingNodeId;
  Offset _resizeStartOffset = Offset.zero;
  double _resizeStartWidth = 0;
  double _resizeStartHeight = 0;

  // ============================================================
  // 画布虚拟化 —— 借鉴 Excalidraw 的视口裁剪渲染
  // 来源: https://github.com/excalidraw/excalidraw
  // 借鉴内容: 只渲染视口内可见的节点，跳过视口外的节点，
  // 避免大量节点时全量渲染导致性能下降
  // ============================================================
  Rect _viewportRect = Rect.zero;
  static const double _viewportPadding = 200; // 视口外额外渲染的距离

  void _updateViewport() {
    final transform = _transformationController.value;
    final scale = transform.getMaxScaleOnAxis();
    // 获取当前视口在画布坐标系中的范围
    final size = MediaQuery.of(context).size;
    final offsetX = transform.getTranslation().x / scale;
    final offsetY = transform.getTranslation().y / scale;
    final width = size.width / scale;
    final height = size.height / scale;
    setState(() {
      _viewportRect = Rect.fromLTWH(
        -offsetX - _viewportPadding,
        -offsetY - _viewportPadding,
        width + _viewportPadding * 2,
        height + _viewportPadding * 2,
      );
    });
  }

  /// 判断节点是否在视口内（含边距）
  /// 借鉴 Excalidraw 的 isVisibleElement 逻辑
  bool _isNodeVisible(CanvasNodeModel node) {
    final nodeRect = Rect.fromLTWH(node.x, node.y, node.width, node.height);
    return _viewportRect.overlaps(nodeRect);
  }

  @override
  void initState() {
    super.initState();
    _initCanvas();
  }

  Future<void> _initCanvas() async {
    try {
      final service = CanvasService();
      final canvasId = await service.createCanvas();
      if (mounted) {
        context.read<CanvasBloc>().add(LoadCanvas(canvasId));
      }
    } catch (e) {
      // 创建画布失败，记录错误但不展示给用户（页面会显示 Bloc 错误状态）
      debugPrint('Canvas initialization failed: $e');
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('画布'),
        actions: [
          CanvasToolbar(
            onAddNote: () => _addNode(NodeType.note),
            onAddImage: () => _addNode(NodeType.image),
            onAddFile: () => _addNode(NodeType.file),
            onAddLink: () => _addNode(NodeType.link),
            onAddGroup: () => _addNode(NodeType.group),
            onAutoLayout: (type) {
              context.read<CanvasBloc>().add(AutoLayout(type));
            },
            onZoomIn: _zoomIn,
            onZoomOut: _zoomOut,
            onZoomReset: _zoomReset,
            onSave: () {
              context.read<CanvasBloc>().add(const SaveCanvas('canvas.canvas'));
            },
          ),
        ],
      ),
      body: BlocBuilder<CanvasBloc, CanvasState>(
        builder: (context, state) {
          if (state is CanvasError) {
            return Center(child: Text('Error: ${state.message}'));
          }
          if (state is CanvasLoaded) {
            return InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.1,
              maxScale: 5.0,
              onInteractionUpdate: (_) => _updateViewport(),
              child: GestureDetector(
                onTapUp: (details) {
                  context.read<CanvasBloc>().add(const SelectNode(null));
                },
                child: Container(
                  width: 10000,
                  height: 10000,
                  color: Theme.of(context).colorScheme.surface,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: const Size(10000, 10000),
                        painter: _GridPainter(
                          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      ...state.edges.map((edge) {
                        final fromNode = state.nodes.where((n) => n.id == edge.fromNode);
                        final toNode = state.nodes.where((n) => n.id == edge.toNode);
                        if (fromNode.isEmpty || toNode.isEmpty) return const SizedBox.shrink();
                        return CanvasEdgeWidget(
                          edge: edge,
                          fromNode: fromNode.first,
                          toNode: toNode.first,
                        );
                      }),
                      ...state.nodes.where(_isNodeVisible).map((node) {
                        final isSelected = state.selectedNodeId == node.id;
                        return CanvasNodeWidget(
                          node: node,
                          isSelected: isSelected,
                          onTap: () {
                            context.read<CanvasBloc>().add(SelectNode(node.id));
                          },
                          onDragStart: (offset) {
                            setState(() {
                              _draggingNodeId = node.id;
                              _dragOffset = offset;
                            });
                          },
                          onDragUpdate: (globalPosition) {
                            if (_draggingNodeId == node.id) {
                              final transform = _transformationController.value;
                              final inverse = Matrix4.inverted(transform);
                              final local = MatrixUtils.transformPoint(inverse, globalPosition);
                              final dx = local.dx - _dragOffset.dx;
                              final dy = local.dy - _dragOffset.dy;
                              context.read<CanvasBloc>().add(MoveNode(
                                    nodeId: node.id,
                                    x: dx,
                                    y: dy,
                                  ));
                            }
                          },
                          onDragEnd: () {
                            setState(() {
                              _draggingNodeId = null;
                            });
                          },
                          onResizeStart: (globalPosition) {
                            setState(() {
                              _resizingNodeId = node.id;
                              _resizeStartOffset = globalPosition;
                              _resizeStartWidth = node.width;
                              _resizeStartHeight = node.height;
                            });
                          },
                          onResizeUpdate: (globalPosition) {
                            if (_resizingNodeId == node.id) {
                              final transform = _transformationController.value;
                              final scale = transform.getMaxScaleOnAxis();
                              final dx = (globalPosition.dx - _resizeStartOffset.dx) / scale;
                              final dy = (globalPosition.dy - _resizeStartOffset.dy) / scale;
                              context.read<CanvasBloc>().add(ResizeNode(
                                    nodeId: node.id,
                                    width: (_resizeStartWidth + dx).clamp(100, 2000),
                                    height: (_resizeStartHeight + dy).clamp(60, 2000),
                                  ));
                            }
                          },
                          onResizeEnd: () {
                            setState(() {
                              _resizingNodeId = null;
                            });
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  void _addNode(NodeType type) {
    final state = context.read<CanvasBloc>().state;
    if (state is! CanvasLoaded) return;
    final id = context.read<CanvasBloc>().generateId();
    final node = CanvasNodeModel(
      id: id,
      nodeType: type,
      x: 5000 + (state.nodes.length * 20 % 300),
      y: 5000 + (state.nodes.length * 20 % 200),
      width: type == NodeType.group ? 400 : 200,
      height: type == NodeType.group ? 300 : 100,
      content: type == NodeType.note ? '新笔记' : null,
    );
    context.read<CanvasBloc>().add(AddNode(node));
  }

  void _zoomIn() {
    final transform = _transformationController.value;
    final newScale = (transform.getMaxScaleOnAxis() * 1.2).clamp(0.1, 5.0);
    _transformationController.value = Matrix4.identity()..scale(newScale);
  }

  void _zoomOut() {
    final transform = _transformationController.value;
    final newScale = (transform.getMaxScaleOnAxis() / 1.2).clamp(0.1, 5.0);
    _transformationController.value = Matrix4.identity()..scale(newScale);
  }

  void _zoomReset() {
    _transformationController.value = Matrix4.identity();
  }
}

class _GridPainter extends CustomPainter {
  final Color color;

  const _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    const step = 50.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
