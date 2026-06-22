import 'package:devnote/core/di/injection.dart';
import 'package:flutter/material.dart';

import '../../notes/services/ocr_service.dart';

/// OCR 识别结果对话框
///
/// P0-2: 在图片块上长按/工具栏触发"识别文字"后弹出，
/// 展示 OCR 识别结果，并支持将文本插入到当前笔记。
class OcrResultDialog extends StatefulWidget {
  final String imagePath;
  final Function(String) onInsertText;

  const OcrResultDialog({
    super.key,
    required this.imagePath,
    required this.onInsertText,
  });

  @override
  State<OcrResultDialog> createState() => _OcrResultDialogState();
}

class _OcrResultDialogState extends State<OcrResultDialog> {
  String _result = '';
  bool _loading = true;
  String? _error;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _performOcr();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _performOcr() async {
    try {
      final ocrService = getIt<OcrService>();
      final text = await ocrService.recognizeImageFile(widget.imagePath);
      _controller.text = text;
      setState(() {
        _result = text;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('OCR 识别结果'),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Text('识别失败: $_error')
                : TextField(
                    maxLines: 10,
                    controller: _controller,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '识别结果',
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (!_loading && _error == null && _result.isNotEmpty)
          FilledButton(
            onPressed: () {
              widget.onInsertText(_controller.text);
              Navigator.pop(context);
            },
            child: const Text('插入到笔记'),
          ),
      ],
    );
  }
}
