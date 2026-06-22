import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/ink_stroke.dart';
import 'ink_stroke_widget.dart';
import 'ink_toolbar.dart';

/// 手写 Ink 绘制层
///
/// 作为 Canvas 顶层覆盖，捕获手势绘制压感笔触。
/// 已完成笔触通过 [strokes] 传入，新笔触通过 [onStrokeAdded] 回调上报。
class InkCanvasLayer extends StatefulWidget {
  final List<InkStroke> strokes;
  final ValueChanged<InkStroke> onStrokeAdded;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;
  final double scale;

  const InkCanvasLayer({
    super.key,
    required this.strokes,
    required this.onStrokeAdded,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    this.scale = 1.0,
  });

  @override
  State<InkCanvasLayer> createState() => _InkCanvasLayerState();
}

class _InkCanvasLayerState extends State<InkCanvasLayer> {
  InkTool _currentTool = InkTool.pen;
  Color _currentColor = const Color(0xFF000000);
  double _currentStrokeWidth = 2.0;
  List<InkPoint> _currentPoints = [];
  String? _currentStrokeId;

  void _onPanStart(DragStartDetails details) {
    _currentStrokeId = const Uuid().v4();
    _currentPoints = [
      InkPoint(
        x: details.localPosition.dx,
        y: details.localPosition.dy,
        pressure: 0.5,
      ),
    ];
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _currentPoints.add(InkPoint(
        x: details.localPosition.dx,
        y: details.localPosition.dy,
        pressure: 0.5, // 实际压感需通过 PointerEvent.pressure 获取
      ));
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentPoints.isNotEmpty && _currentStrokeId != null) {
      final stroke = InkStroke(
        id: _currentStrokeId!,
        points: List.of(_currentPoints),
        strokeWidth: _currentTool == InkTool.marker
            ? _currentStrokeWidth * 2
            : _currentStrokeWidth,
        color: _currentTool == InkTool.eraser
            ? Colors.transparent
            : _currentColor,
        isEraser: _currentTool == InkTool.eraser,
      );
      widget.onStrokeAdded(stroke);
    }
    setState(() {
      _currentPoints = [];
      _currentStrokeId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 已完成的笔触
        ...widget.strokes.map((stroke) => InkStrokeWidget(
              stroke: stroke,
              scale: widget.scale,
            )),
        // 当前正在绘制的笔触
        if (_currentPoints.isNotEmpty && _currentStrokeId != null)
          InkStrokeWidget(
            stroke: InkStroke(
              id: _currentStrokeId!,
              points: _currentPoints,
              strokeWidth: _currentTool == InkTool.marker
                  ? _currentStrokeWidth * 2
                  : _currentStrokeWidth,
              color: _currentTool == InkTool.eraser
                  ? Colors.transparent
                  : _currentColor,
              isEraser: _currentTool == InkTool.eraser,
            ),
            scale: widget.scale,
          ),
        // 手势检测层
        GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          behavior: HitTestBehavior.translucent,
        ),
        // 工具栏
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: InkToolbar(
            currentTool: _currentTool,
            currentColor: _currentColor,
            currentStrokeWidth: _currentStrokeWidth,
            onToolChanged: (tool) => setState(() => _currentTool = tool),
            onColorChanged: (color) => setState(() => _currentColor = color),
            onStrokeWidthChanged: (w) =>
                setState(() => _currentStrokeWidth = w),
            onUndo: widget.onUndo,
            onRedo: widget.onRedo,
            onClear: widget.onClear,
          ),
        ),
      ],
    );
  }
}
