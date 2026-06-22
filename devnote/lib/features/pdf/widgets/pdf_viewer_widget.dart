import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import '../models/pdf_annotation.dart';

/// PDF 查看器，支持标注
class PdfViewerWidget extends StatefulWidget {
  final String pdfPath;
  final List<PdfAnnotation> annotations;
  final Function(PdfAnnotation)? onAnnotationAdded;
  final Function(PdfAnnotation)? onAnnotationUpdated;
  final Function(String)? onAnnotationDeleted;

  const PdfViewerWidget({
    super.key,
    required this.pdfPath,
    this.annotations = const [],
    this.onAnnotationAdded,
    this.onAnnotationUpdated,
    this.onAnnotationDeleted,
  });

  @override
  State<PdfViewerWidget> createState() => _PdfViewerWidgetState();
}

class _PdfViewerWidgetState extends State<PdfViewerWidget> {
  late PdfControllerPinch _pdfController;
  int _currentPage = 1;
  int _totalPages = 0;
  PdfAnnotationType _currentTool = PdfAnnotationType.highlight;
  Color _currentColor = const Color(0xFFFFEB3B);
  bool _isAnnotating = false;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfControllerPinch(
      document: PdfDocument.openFile(widget.pdfPath),
    );
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 工具栏
        _buildToolbar(context),
        // PDF 视图
        Expanded(
          child: Stack(
            children: [
              PdfViewPinch(
                controller: _pdfController,
                onPageChanged: (page) {
                  setState(() => _currentPage = page);
                },
                onDocumentLoaded: (doc) {
                  setState(() => _totalPages = doc.pagesCount);
                },
              ),
              // 标注覆盖层
              if (_isAnnotating)
                GestureDetector(
                  onPanStart: _onAnnotateStart,
                  onPanUpdate: _onAnnotateUpdate,
                  onPanEnd: _onAnnotateEnd,
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              // 显示已有标注
              ..._buildAnnotationOverlays(),
            ],
          ),
        ),
        // 页码栏
        _buildPageBar(context),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
              color: Theme.of(context).colorScheme.outline.withAlpha(30)),
        ),
      ),
      child: Row(
        children: [
          // 标注工具
          _buildToolButton(PdfAnnotationType.highlight, Icons.highlight, '高亮'),
          _buildToolButton(
              PdfAnnotationType.underline, Icons.format_underline, '下划线'),
          _buildToolButton(PdfAnnotationType.note, Icons.sticky_note_2, '批注'),
          _buildToolButton(PdfAnnotationType.drawing, Icons.draw, '绘图'),
          const VerticalDivider(width: 16),
          // 颜色选择
          for (final color in [
            const Color(0xFFFFEB3B), // 黄
            const Color(0xFF4CAF50), // 绿
            const Color(0xFF2196F3), // 蓝
            const Color(0xFFF44336), // 红
          ])
            GestureDetector(
              onTap: () => setState(() => _currentColor = color),
              child: Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _currentColor.toARGB32() == color.toARGB32()
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
          const Spacer(),
          // 标注模式开关
          IconButton(
            icon: Icon(_isAnnotating ? Icons.edit_off : Icons.edit),
            isSelected: _isAnnotating,
            onPressed: () => setState(() => _isAnnotating = !_isAnnotating),
            tooltip: '标注模式',
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton(PdfAnnotationType type, IconData icon, String label) {
    return Tooltip(
      message: label,
      child: IconButton(
        icon: Icon(icon),
        isSelected: _currentTool == type,
        onPressed: () {
          setState(() {
            _currentTool = type;
            _isAnnotating = true;
          });
        },
      ),
    );
  }

  Widget _buildPageBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
              color: Theme.of(context).colorScheme.outline.withAlpha(30)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.first_page),
            onPressed: () => _goToPage(1),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _goToPage(_currentPage - 1),
          ),
          Text('$_currentPage / $_totalPages'),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _goToPage(_currentPage + 1),
          ),
          IconButton(
            icon: const Icon(Icons.last_page),
            onPressed: () => _goToPage(_totalPages),
          ),
        ],
      ),
    );
  }

  /// 跳转到指定页（夹取到有效范围）
  void _goToPage(int page) {
    final maxPage = _totalPages > 0 ? _totalPages : 1;
    final target = page.clamp(1, maxPage);
    _pdfController.animateToPage(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.ease,
    );
  }

  List<Widget> _buildAnnotationOverlays() {
    final pageAnnotations = widget.annotations
        .where((a) => a.pageNumber == _currentPage)
        .toList();

    return pageAnnotations.map((annotation) {
      return Positioned(
        left: annotation.rect.left,
        top: annotation.rect.top,
        width: annotation.rect.width,
        height: annotation.rect.height,
        child: GestureDetector(
          onTap: () => _showAnnotationDetail(annotation),
          child: Container(
            decoration: BoxDecoration(
              color: annotation.color.withAlpha(60),
              border: Border.all(
                color: annotation.color,
                width: 1,
              ),
            ),
            child: annotation.text != null
                ? Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      annotation.text!,
                      style: TextStyle(
                        fontSize: 10,
                        color: annotation.color,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      );
    }).toList();
  }

  // 标注手势处理
  Offset? _startPoint;
  Offset? _currentPoint;

  void _onAnnotateStart(DragStartDetails details) {
    _startPoint = details.localPosition;
    _currentPoint = details.localPosition;
  }

  void _onAnnotateUpdate(DragUpdateDetails details) {
    _currentPoint = details.localPosition;
  }

  void _onAnnotateEnd(DragEndDetails details) {
    if (_startPoint == null || _currentPoint == null) return;

    final rect = Rect.fromPoints(_startPoint!, _currentPoint!);
    if (rect.width < 5 && rect.height < 5) {
      // 点击操作，添加批注
      _addNoteAnnotation(rect);
    } else {
      // 拖拽操作，添加高亮/下划线
      _addHighlightAnnotation(rect);
    }

    _startPoint = null;
    _currentPoint = null;
  }

  void _addHighlightAnnotation(Rect rect) {
    final annotation = PdfAnnotation(
      id: 'pdf-ann-${DateTime.now().millisecondsSinceEpoch}',
      pageNumber: _currentPage,
      type: _currentTool,
      rect: rect,
      color: _currentColor,
    );
    widget.onAnnotationAdded?.call(annotation);
  }

  void _addNoteAnnotation(Rect rect) {
    if (_currentTool != PdfAnnotationType.note) return;

    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加批注'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '输入批注内容...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                final annotation = PdfAnnotation(
                  id: 'pdf-ann-${DateTime.now().millisecondsSinceEpoch}',
                  pageNumber: _currentPage,
                  type: PdfAnnotationType.note,
                  rect: rect,
                  text: controller.text,
                  color: _currentColor,
                );
                widget.onAnnotationAdded?.call(annotation);
              }
              Navigator.pop(context);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _showAnnotationDetail(PdfAnnotation annotation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_annotationTypeLabel(annotation.type)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (annotation.text != null) ...[
              const Text('内容：', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(annotation.text!),
              const SizedBox(height: 8),
            ],
            Text('页码：${annotation.pageNumber}'),
            Text('创建时间：${annotation.createdAt}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.onAnnotationDeleted?.call(annotation.id);
              Navigator.pop(context);
            },
            child: Text('删除',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _annotationTypeLabel(PdfAnnotationType type) {
    switch (type) {
      case PdfAnnotationType.highlight:
        return '高亮';
      case PdfAnnotationType.underline:
        return '下划线';
      case PdfAnnotationType.note:
        return '批注';
      case PdfAnnotationType.signature:
        return '签名';
      case PdfAnnotationType.drawing:
        return '绘图';
    }
  }
}
