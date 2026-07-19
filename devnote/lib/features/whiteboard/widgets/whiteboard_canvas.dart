import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:devnote/features/whiteboard/models/whiteboard_element.dart';
import 'package:devnote/features/whiteboard/widgets/whiteboard_toolbar.dart';

/// 白板画布 —— 支持 Excalidraw 风格的绘制、选择、移动、缩放、平移
///
/// 借鉴 Excalidraw 的交互模式：
/// 来源: https://github.com/excalidraw/excalidraw
/// - 工具切换决定手势行为
/// - 选择工具下点击选中、拖拽移动
/// - 图形工具下按下拖拽创建对应图形
/// - 自由绘制工具下连续记录点形成路径
/// - 文本工具下点击弹出输入对话框
/// - 橡皮擦工具下点击删除元素
class WhiteboardCanvas extends StatefulWidget {
  final List<WhiteboardElement> elements;
  final String? selectedElementId;
  final WhiteboardTool currentTool;
  final String strokeColor;
  final double strokeWidth;
  final bool showGrid;
  final void Function(WhiteboardElement) onAddElement;
  final void Function(String id, WhiteboardElement element) onUpdateElement;
  final void Function(String id) onDeleteElement;
  final void Function(String? id) onSelectElement;
  final void Function(WhiteboardElement element) onCommitElement;
  final Future<void> Function(Offset position) onTextRequest;

  const WhiteboardCanvas({
    super.key,
    required this.elements,
    required this.selectedElementId,
    required this.currentTool,
    required this.strokeColor,
    required this.strokeWidth,
    required this.showGrid,
    required this.onAddElement,
    required this.onUpdateElement,
    required this.onDeleteElement,
    required this.onSelectElement,
    required this.onCommitElement,
    required this.onTextRequest,
  });

  @override
  State<WhiteboardCanvas> createState() => _WhiteboardCanvasState();
}

class _WhiteboardCanvasState extends State<WhiteboardCanvas> {
  final TransformationController _controller = TransformationController();
  static const double _canvasSize = 4000;

  // 临时绘制状态
  WhiteboardElement? _draftElement;
  Offset? _dragStart;
  Offset? _dragLast;
  String? _draggingId;
  Offset _dragElementStart = Offset.zero;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 将屏幕坐标转换为画布坐标（考虑 InteractiveViewer 的变换）
  Offset _toCanvas(Offset screen) {
    final transform = _controller.value;
    final scale = transform.getMaxScaleOnAxis();
    final tx = transform.getTranslation().x;
    final ty = transform.getTranslation().y;
    return Offset(
      (screen.dx - tx) / scale,
      (screen.dy - ty) / scale,
    );
  }

  bool _isSelectTool() => widget.currentTool == WhiteboardTool.selection;
  bool _isEraser() => widget.currentTool == WhiteboardTool.eraser;
  bool _isFreedraw() => widget.currentTool == WhiteboardTool.freedraw;
  bool _isText() => widget.currentTool == WhiteboardTool.text;

  /// 命中测试：返回点击位置最上层的元素 id
  String? _hitTest(Offset canvasPoint) {
    for (var i = widget.elements.length - 1; i >= 0; i--) {
      if (_containsPoint(widget.elements[i], canvasPoint)) {
        return widget.elements[i].id;
      }
    }
    return null;
  }

  bool _containsPoint(WhiteboardElement e, Offset p) {
    if (e is RectangleElement) {
      return Rect.fromLTWH(e.x, e.y, e.width, e.height).contains(p);
    } else if (e is EllipseElement) {
      final cx = e.x + e.width / 2;
      final cy = e.y + e.height / 2;
      final rx = e.width / 2;
      final ry = e.height / 2;
      if (rx == 0 || ry == 0) return false;
      final dx = (p.dx - cx) / rx;
      final dy = (p.dy - cy) / ry;
      return dx * dx + dy * dy <= 1;
    } else if (e is DiamondElement) {
      final cx = e.x + e.width / 2;
      final cy = e.y + e.height / 2;
      final dx = (p.dx - cx).abs() / (e.width / 2);
      final dy = (p.dy - cy).abs() / (e.height / 2);
      return dx + dy <= 1;
    } else if (e is LineElement) {
      return _distanceToSegment(p, Offset(e.x, e.y), Offset(e.x2, e.y2)) <=
          math.max(8, e.strokeWidth + 4);
    } else if (e is ArrowElement) {
      return _distanceToSegment(p, Offset(e.x, e.y), Offset(e.x2, e.y2)) <=
          math.max(8, e.strokeWidth + 4);
    } else if (e is FreedrawElement) {
      if (e.points.isEmpty) return false;
      for (final pt in e.points) {
        if ((p - Offset(e.x + pt.dx, e.y + pt.dy)).distance <=
            math.max(8, e.strokeWidth + 4)) {
          return true;
        }
      }
      return false;
    } else if (e is TextElement) {
      // 简化：以 (x, y) 为左上角，估算宽高
      final approxWidth = e.text.length * e.fontSize * 0.6;
      final approxHeight = e.fontSize * 1.4;
      return Rect.fromLTWH(e.x, e.y, approxWidth, approxHeight).contains(p);
    } else if (e is ImageElement) {
      return Rect.fromLTWH(e.x, e.y, e.width, e.height).contains(p);
    }
    return false;
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return (p - a).distance;
    final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq;
    final tc = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + tc * dx, a.dy + tc * dy);
    return (p - proj).distance;
  }

  void _onPanStart(DragStartDetails details) {
    final canvasPoint = _toCanvas(details.localPosition);
    _dragStart = canvasPoint;
    _dragLast = canvasPoint;

    if (_isSelectTool()) {
      final hitId = _hitTest(canvasPoint);
      if (hitId != null) {
        widget.onSelectElement(hitId);
        _draggingId = hitId;
        final idx = widget.elements.indexWhere((el) => el.id == hitId);
        if (idx >= 0) {
          _dragElementStart = Offset(widget.elements[idx].x, widget.elements[idx].y);
        }
      } else {
        widget.onSelectElement(null);
        _draggingId = null;
      }
      return;
    }

    if (_isEraser()) {
      final hitId = _hitTest(canvasPoint);
      if (hitId != null) {
        widget.onDeleteElement(hitId);
      }
      return;
    }

    if (_isFreedraw()) {
      final id = const Uuid().v4();
      _draftElement = FreedrawElement(
        id: id,
        x: canvasPoint.dx,
        y: canvasPoint.dy,
        points: const [Offset.zero],
        strokeColor: widget.strokeColor,
        strokeWidth: widget.strokeWidth,
      );
      return;
    }

    if (_isText()) {
      // 文本工具不在此处理，由 onTapUp 处理
      return;
    }

    // 图形工具：创建草稿元素
    final id = const Uuid().v4();
    switch (widget.currentTool) {
      case WhiteboardTool.rectangle:
        _draftElement = RectangleElement(
          id: id,
          x: canvasPoint.dx,
          y: canvasPoint.dy,
          width: 0,
          height: 0,
          strokeColor: widget.strokeColor,
          strokeWidth: widget.strokeWidth,
        );
        break;
      case WhiteboardTool.ellipse:
        _draftElement = EllipseElement(
          id: id,
          x: canvasPoint.dx,
          y: canvasPoint.dy,
          width: 0,
          height: 0,
          strokeColor: widget.strokeColor,
          strokeWidth: widget.strokeWidth,
        );
        break;
      case WhiteboardTool.diamond:
        _draftElement = DiamondElement(
          id: id,
          x: canvasPoint.dx,
          y: canvasPoint.dy,
          width: 0,
          height: 0,
          strokeColor: widget.strokeColor,
          strokeWidth: widget.strokeWidth,
        );
        break;
      case WhiteboardTool.line:
        _draftElement = LineElement(
          id: id,
          x: canvasPoint.dx,
          y: canvasPoint.dy,
          x2: canvasPoint.dx,
          y2: canvasPoint.dy,
          strokeColor: widget.strokeColor,
          strokeWidth: widget.strokeWidth,
        );
        break;
      case WhiteboardTool.arrow:
        _draftElement = ArrowElement(
          id: id,
          x: canvasPoint.dx,
          y: canvasPoint.dy,
          x2: canvasPoint.dx,
          y2: canvasPoint.dy,
          strokeColor: widget.strokeColor,
          strokeWidth: widget.strokeWidth,
        );
        break;
      default:
        break;
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final canvasPoint = _toCanvas(details.localPosition);
    _dragLast = canvasPoint;

    if (_isSelectTool() && _draggingId != null) {
      final idx = widget.elements.indexWhere((el) => el.id == _draggingId);
      if (idx < 0) return;
      final e = widget.elements[idx];
      final dx = canvasPoint.dx - _dragStart!.dx;
      final dy = canvasPoint.dy - _dragStart!.dy;
      widget.onUpdateElement(
        e.id,
        e.copyWith(
          x: _dragElementStart.dx + dx,
          y: _dragElementStart.dy + dy,
        ),
      );
      return;
    }

    if (_draftElement == null) return;

    final draft = _draftElement!;
    final start = _dragStart!;

    if (draft is FreedrawElement) {
      final newPoints = [
        ...draft.points,
        Offset(canvasPoint.dx - draft.x, canvasPoint.dy - draft.y),
      ];
      _draftElement = draft.copyWith(points: newPoints);
    } else if (draft is LineElement) {
      _draftElement = draft.copyWith(x2: canvasPoint.dx, y2: canvasPoint.dy);
    } else if (draft is ArrowElement) {
      _draftElement = draft.copyWith(x2: canvasPoint.dx, y2: canvasPoint.dy);
    } else if (draft is RectangleElement) {
      final x = math.min(start.dx, canvasPoint.dx);
      final y = math.min(start.dy, canvasPoint.dy);
      final w = (canvasPoint.dx - start.dx).abs();
      final h = (canvasPoint.dy - start.dy).abs();
      _draftElement = draft.copyWith(x: x, y: y, width: w, height: h);
    } else if (draft is EllipseElement) {
      final x = math.min(start.dx, canvasPoint.dx);
      final y = math.min(start.dy, canvasPoint.dy);
      final w = (canvasPoint.dx - start.dx).abs();
      final h = (canvasPoint.dy - start.dy).abs();
      _draftElement = draft.copyWith(x: x, y: y, width: w, height: h);
    } else if (draft is DiamondElement) {
      final x = math.min(start.dx, canvasPoint.dx);
      final y = math.min(start.dy, canvasPoint.dy);
      final w = (canvasPoint.dx - start.dx).abs();
      final h = (canvasPoint.dy - start.dy).abs();
      _draftElement = draft.copyWith(x: x, y: y, width: w, height: h);
    }

    setState(() {});
  }

  void _onPanEnd(DragEndDetails _) {
    if (_isSelectTool()) {
      // 选中拖拽结束：提交一次历史
      if (_draggingId != null) {
        final idx = widget.elements.indexWhere((el) => el.id == _draggingId);
        if (idx >= 0) {
          widget.onCommitElement(widget.elements[idx]);
        }
      }
      _draggingId = null;
      return;
    }

    final draft = _draftElement;
    if (draft == null) return;

    // 过滤掉太小的图形（避免误触）
    bool shouldAdd = true;
    if (draft is RectangleElement) {
      shouldAdd = draft.width > 3 && draft.height > 3;
    } else if (draft is EllipseElement) {
      shouldAdd = draft.width > 3 && draft.height > 3;
    } else if (draft is DiamondElement) {
      shouldAdd = draft.width > 3 && draft.height > 3;
    } else if (draft is LineElement) {
      shouldAdd =
          (Offset(draft.x2, draft.y2) - Offset(draft.x, draft.y)).distance > 3;
    } else if (draft is ArrowElement) {
      shouldAdd =
          (Offset(draft.x2, draft.y2) - Offset(draft.x, draft.y)).distance > 3;
    } else if (draft is FreedrawElement) {
      shouldAdd = draft.points.length > 1;
    }

    if (shouldAdd) {
      widget.onAddElement(draft);
    }

    setState(() {
      _draftElement = null;
      _dragStart = null;
      _dragLast = null;
    });
  }

  void _onTapUp(TapUpDetails details) {
    final canvasPoint = _toCanvas(details.localPosition);
    if (_isText()) {
      widget.onTextRequest(canvasPoint);
      return;
    }
    if (_isSelectTool()) {
      final hitId = _hitTest(canvasPoint);
      widget.onSelectElement(hitId);
    } else if (_isEraser()) {
      final hitId = _hitTest(canvasPoint);
      if (hitId != null) {
        widget.onDeleteElement(hitId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _controller,
      minScale: 0.2,
      maxScale: 5.0,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      constrained: false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _onTapUp,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: SizedBox(
          width: _canvasSize,
          height: _canvasSize,
          child: CustomPaint(
            painter: _WhiteboardPainter(
              elements: widget.elements,
              draft: _draftElement,
              selectedId: widget.selectedElementId,
              showGrid: widget.showGrid,
            ),
          ),
        ),
      ),
    );
  }
}

/// 白板绘制器 —— 渲染所有元素 + 草稿 + 选择框
class _WhiteboardPainter extends CustomPainter {
  final List<WhiteboardElement> elements;
  final WhiteboardElement? draft;
  final String? selectedId;
  final bool showGrid;

  _WhiteboardPainter({
    required this.elements,
    required this.draft,
    required this.selectedId,
    required this.showGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 网格背景
    if (showGrid) {
      _drawGrid(canvas, size);
    }

    // 已有元素
    for (final e in elements) {
      _drawElement(canvas, e);
    }

    // 草稿元素
    if (draft != null) {
      _drawElement(canvas, draft!);
    }

    // 选中框
    if (selectedId != null) {
      final selected =
          elements.where((e) => e.id == selectedId).firstOrNull;
      if (selected != null) {
        _drawSelectionBox(canvas, selected);
      }
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawElement(Canvas canvas, WhiteboardElement e) {
    final strokePaint = Paint()
      ..color = WhiteboardElement.parseColor(e.strokeColor)
      ..style = PaintingStyle.stroke
      ..strokeWidth = e.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = WhiteboardElement.parseColor(e.fillColor)
      ..style = PaintingStyle.fill;

    final opacity = e.opacity.clamp(0.0, 1.0);
    strokePaint.color = strokePaint.color.withValues(alpha: opacity);
    fillPaint.color = fillPaint.color.withValues(alpha: opacity);

    canvas.save();
    if (e.rotation != 0) {
      final cx = _bounds(e).center.dx;
      final cy = _bounds(e).center.dy;
      canvas.translate(cx, cy);
      canvas.rotate(e.rotation * math.pi / 180);
      canvas.translate(-cx, -cy);
    }

    if (e is RectangleElement) {
      final rect = Rect.fromLTWH(e.x, e.y, e.width, e.height);
      if (e.fillColor != 'transparent') {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(e.borderRadius)),
          fillPaint,
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(e.borderRadius)),
        strokePaint,
      );
    } else if (e is EllipseElement) {
      final rect = Rect.fromLTWH(e.x, e.y, e.width, e.height);
      if (e.fillColor != 'transparent') {
        canvas.drawOval(rect, fillPaint);
      }
      canvas.drawOval(rect, strokePaint);
    } else if (e is DiamondElement) {
      final cx = e.x + e.width / 2;
      final cy = e.y + e.height / 2;
      final path = Path()
        ..moveTo(cx, e.y)
        ..lineTo(e.x + e.width, cy)
        ..lineTo(cx, e.y + e.height)
        ..lineTo(e.x, cy)
        ..close();
      if (e.fillColor != 'transparent') {
        canvas.drawPath(path, fillPaint);
      }
      canvas.drawPath(path, strokePaint);
    } else if (e is LineElement) {
      canvas.drawLine(
        Offset(e.x, e.y),
        Offset(e.x2, e.y2),
        strokePaint,
      );
      if (e.arrowhead == Arrowhead.arrow) {
        _drawArrowhead(canvas, Offset(e.x, e.y), Offset(e.x2, e.y2),
            strokePaint);
      } else if (e.arrowhead == Arrowhead.dot) {
        canvas.drawCircle(Offset(e.x2, e.y2), e.strokeWidth * 1.5, strokePaint);
      }
    } else if (e is ArrowElement) {
      canvas.drawLine(
        Offset(e.x, e.y),
        Offset(e.x2, e.y2),
        strokePaint,
      );
      _drawArrowhead(
          canvas, Offset(e.x, e.y), Offset(e.x2, e.y2), strokePaint);
    } else if (e is FreedrawElement) {
      if (e.points.length < 2) {
        if (e.points.isNotEmpty) {
          canvas.drawPoints(
            PointMode.points,
            [Offset(e.x + e.points[0].dx, e.y + e.points[0].dy)],
            strokePaint,
          );
        }
      } else {
        final path = Path();
        path.moveTo(e.x + e.points[0].dx, e.y + e.points[0].dy);
        for (var i = 1; i < e.points.length; i++) {
          path.lineTo(e.x + e.points[i].dx, e.y + e.points[i].dy);
        }
        canvas.drawPath(path, strokePaint);
      }
    } else if (e is TextElement) {
      final span = TextSpan(
        text: e.text,
        style: TextStyle(
          color: WhiteboardElement.parseColor(e.strokeColor).withValues(alpha: opacity),
          fontSize: e.fontSize,
          fontFamily: e.fontFamily,
        ),
      );
      final painter = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(e.x, e.y));
    } else if (e is ImageElement) {
      // 图片绘制由 Widget 层处理（CustomPainter 无法直接绘制 Image）
      // 此处绘制占位框
      final rect = Rect.fromLTWH(e.x, e.y, e.width, e.height);
      canvas.drawRect(rect, strokePaint);
    }

    canvas.restore();
  }

  void _drawArrowhead(
      Canvas canvas, Offset from, Offset to, Paint paint) {
    final angle = (to - from).direction;
    const arrowLength = 12.0;
    const arrowAngle = math.pi / 7;
    final p1 = Offset(
      to.dx - arrowLength * math.cos(angle - arrowAngle),
      to.dy - arrowLength * math.sin(angle - arrowAngle),
    );
    final p2 = Offset(
      to.dx - arrowLength * math.cos(angle + arrowAngle),
      to.dy - arrowLength * math.sin(angle + arrowAngle),
    );
    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(p1.dx, p1.dy)
      ..moveTo(to.dx, to.dy)
      ..lineTo(p2.dx, p2.dy);
    canvas.drawPath(path, paint);
  }

  Rect _bounds(WhiteboardElement e) {
    if (e is RectangleElement) {
      return Rect.fromLTWH(e.x, e.y, e.width, e.height);
    } else if (e is EllipseElement) {
      return Rect.fromLTWH(e.x, e.y, e.width, e.height);
    } else if (e is DiamondElement) {
      return Rect.fromLTWH(e.x, e.y, e.width, e.height);
    } else if (e is LineElement) {
      final minX = math.min(e.x, e.x2);
      final minY = math.min(e.y, e.y2);
      final maxX = math.max(e.x, e.x2);
      final maxY = math.max(e.y, e.y2);
      return Rect.fromLTWH(minX, minY, maxX - minX, maxY - minY);
    } else if (e is ArrowElement) {
      final minX = math.min(e.x, e.x2);
      final minY = math.min(e.y, e.y2);
      final maxX = math.max(e.x, e.x2);
      final maxY = math.max(e.y, e.y2);
      return Rect.fromLTWH(minX, minY, maxX - minX, maxY - minY);
    } else if (e is FreedrawElement) {
      if (e.points.isEmpty) return Rect.fromLTWH(e.x, e.y, 0, 0);
      double minX = e.points.first.dx;
      double minY = e.points.first.dy;
      double maxX = e.points.first.dx;
      double maxY = e.points.first.dy;
      for (final p in e.points) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
      return Rect.fromLTWH(e.x + minX, e.y + minY, maxX - minX, maxY - minY);
    } else if (e is TextElement) {
      final approxWidth = e.text.length * e.fontSize * 0.6;
      final approxHeight = e.fontSize * 1.4;
      return Rect.fromLTWH(e.x, e.y, approxWidth, approxHeight);
    } else if (e is ImageElement) {
      return Rect.fromLTWH(e.x, e.y, e.width, e.height);
    }
    return Rect.fromLTWH(e.x, e.y, 0, 0);
  }

  void _drawSelectionBox(Canvas canvas, WhiteboardElement e) {
    final bounds = _bounds(e).inflate(6);
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    // 虚线边框
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    double startX = bounds.left;
    while (startX < bounds.right) {
      final end = (startX + dashWidth).clamp(bounds.left, bounds.right);
      canvas.drawLine(Offset(startX, bounds.top), Offset(end, bounds.top), paint);
      canvas.drawLine(
          Offset(startX, bounds.bottom), Offset(end, bounds.bottom), paint);
      startX += dashWidth + dashSpace;
    }
    double startY = bounds.top;
    while (startY < bounds.bottom) {
      final end = (startY + dashWidth).clamp(bounds.top, bounds.bottom);
      canvas.drawLine(Offset(bounds.left, startY), Offset(bounds.left, end), paint);
      canvas.drawLine(
          Offset(bounds.right, startY), Offset(bounds.right, end), paint);
      startY += dashWidth + dashSpace;
    }

    // 8 个调整手柄
    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final handleBorder = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const handleSize = 8.0;
    final handles = <Offset>[
      bounds.topLeft,
      bounds.topCenter,
      bounds.topRight,
      bounds.centerLeft,
      bounds.centerRight,
      bounds.bottomLeft,
      bounds.bottomCenter,
      bounds.bottomRight,
    ];
    for (final h in handles) {
      final rect = Rect.fromCenter(
          center: h, width: handleSize, height: handleSize);
      canvas.drawRect(rect, handlePaint);
      canvas.drawRect(rect, handleBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _WhiteboardPainter oldDelegate) =>
      oldDelegate.elements != elements ||
      oldDelegate.draft != draft ||
      oldDelegate.selectedId != selectedId ||
      oldDelegate.showGrid != showGrid;
}
