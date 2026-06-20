import 'dart:convert';
import 'package:flutter/material.dart';
import '../../pdf/widgets/pdf_viewer_widget.dart';
import '../../pdf/models/pdf_annotation.dart';

/// PDF 块 Widget — 在笔记中嵌入 PDF 查看器
class PdfBlockWidget extends StatefulWidget {
  final String content; // JSON: {url, page_count, current_page, annotations}
  final Function(String)? onContentChanged;

  const PdfBlockWidget({
    super.key,
    required this.content,
    this.onContentChanged,
  });

  @override
  State<PdfBlockWidget> createState() => _PdfBlockWidgetState();
}

class _PdfBlockWidgetState extends State<PdfBlockWidget> {
  late Map<String, dynamic> _data;
  List<PdfAnnotation> _annotations = [];

  @override
  void initState() {
    super.initState();
    _parseContent();
  }

  void _parseContent() {
    try {
      _data = jsonDecode(widget.content) as Map<String, dynamic>;
      final annList = _data['annotations'] as List? ?? [];
      _annotations = annList
          .map((a) => PdfAnnotation.fromJson(a as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _data = {'url': '', 'page_count': 0, 'current_page': 1, 'annotations': []};
    }
  }

  void _updateContent() {
    _data['annotations'] = _annotations.map((a) => a.toJson()).toList();
    widget.onContentChanged?.call(jsonEncode(_data));
  }

  @override
  Widget build(BuildContext context) {
    final url = _data['url'] as String? ?? '';
    if (url.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withAlpha(100)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.picture_as_pdf, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text('点击添加 PDF 文件'),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 500,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withAlpha(100)),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: PdfViewerWidget(
        pdfPath: url,
        annotations: _annotations,
        onAnnotationAdded: (annotation) {
          setState(() {
            _annotations.add(annotation);
            _updateContent();
          });
        },
        onAnnotationDeleted: (id) {
          setState(() {
            _annotations.removeWhere((a) => a.id == id);
            _updateContent();
          });
        },
      ),
    );
  }
}
