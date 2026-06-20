import 'dart:convert';
import 'dart:io';

import 'package:devnote/core/di/injection.dart';

import '../../../core/bridge/ffi_bridge.dart';

/// OCR 服务 —— 调用 Rust OCR 引擎识别图片文字，并将结果纳入全文搜索索引
///
/// P0-2: OCR 文字识别 + 图片搜索
/// - [recognizeImageFile] / [recognizeImageBytes]: 单次识别图片文字
/// - [indexImageForSearch]: 识别后将文本写入 FTS5 索引，使图片内容可被全文检索
class OcrService {
  final FFIBridge _ffiBridge = getIt<FFIBridge>();

  /// 识别图片文件中的文字
  Future<String> recognizeImageFile(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final base64 = base64Encode(bytes);
    return _ffiBridge.ocrRecognizeImage(imageBase64: base64);
  }

  /// 识别图片字节中的文字
  Future<String> recognizeImageBytes(List<int> bytes) async {
    final base64 = base64Encode(bytes);
    return _ffiBridge.ocrRecognizeImage(imageBase64: base64);
  }

  /// 识别图片并将结果存入搜索索引
  Future<void> indexImageForSearch({
    required String noteId,
    required String imageBase64,
  }) async {
    final text = await _ffiBridge.ocrRecognizeImage(imageBase64: imageBase64);
    if (text.isNotEmpty) {
      // 将 OCR 结果存入 FTS5 索引
      await _ffiBridge.indexOcrText(noteId: noteId, ocrText: text);
    }
  }
}
