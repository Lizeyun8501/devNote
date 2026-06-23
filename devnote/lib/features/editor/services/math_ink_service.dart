import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/bridge/ffi_bridge.dart';
import '../../../core/di/injection.dart';
import '../../../src/rust/library.dart' as rust;

/// 手写公式识别结果
///
/// 与 Rust 端 `MathRecognitionResult` 结构体对齐。
class MathInkRecognitionResult {
  /// 主候选 LaTeX 公式（不含 `$`/`$$` 定界符）
  final String latex;

  /// 主候选置信度 (0.0 - 1.0)
  final double confidence;

  /// 备选 LaTeX 公式
  final List<String> alternatives;

  const MathInkRecognitionResult({
    required this.latex,
    required this.confidence,
    required this.alternatives,
  });

  factory MathInkRecognitionResult.empty() => const MathInkRecognitionResult(
        latex: '',
        confidence: 0.0,
        alternatives: [],
      );

  factory MathInkRecognitionResult.fromRust(rust.MathRecognitionResultFfi r) {
    return MathInkRecognitionResult(
      latex: r.latex,
      confidence: r.confidence,
      alternatives: r.alternatives,
    );
  }

  factory MathInkRecognitionResult.fromJson(Map<String, dynamic> json) {
    return MathInkRecognitionResult(
      latex: json['latex'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      alternatives: (json['alternatives'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  /// 所有候选（主候选 + 备选），用于 UI 切换
  List<String> get allCandidates => [
        if (latex.isNotEmpty) latex,
        ...alternatives.where((e) => e.isNotEmpty && e != latex),
      ];
}

/// 手写公式识别服务（P2-9）
///
/// 将手写笔触转换为 LaTeX 公式。识别优先级：
/// 1. **FRB**：通过 flutter_rust_bridge v2 调用 `devnote-math-ink` crate
/// 2. **在线 API**（可选）：用户配置 API URL 后，将笔迹渲染为 PNG 上传识别
/// 3. **降级**：FRB 不可用时返回空结果并提示
///
/// 与 [OcrService] 模式一致：通过 [FFIBridge] 调用 Rust 核心。
class MathInkService {
  final FFIBridge _ffiBridge = getIt<FFIBridge>();

  /// 用户可选配置的在线识别 API URL（如 Mathpix API）
  ///
  /// 为 null 时仅使用本地 FRB 识别。
  String? onlineApiUrl;

  /// 在线 API 的认证 Token（如 `app_id`:`app_key`）
  String? onlineApiToken;

  /// 识别手写笔触为 LaTeX 公式
  ///
  /// [strokes] 笔触列表，每个内层 List 是一笔的轨迹点（Offset 列表）
  Future<MathInkRecognitionResult> recognizeStrokes(
    List<List<Offset>> strokes,
  ) async {
    if (strokes.isEmpty) {
      return MathInkRecognitionResult.empty();
    }

    // 优先尝试 FRB 调用
    if (_ffiBridge.isAvailable) {
      try {
        return await _recognizeViaFrb(strokes);
      } catch (e) {
        // FRB 调用失败，降级到在线 API（若配置）
        if (onlineApiUrl != null) {
          return _recognizeViaOnlineApi(strokes);
        }
        rethrow;
      }
    }

    // FRB 不可用，尝试在线 API
    if (onlineApiUrl != null) {
      return _recognizeViaOnlineApi(strokes);
    }

    // 全部不可用：返回空结果
    return MathInkRecognitionResult.empty();
  }

  /// 从 PNG 字节识别（备选方案：调用在线 API）
  ///
  /// [pngBytes] PNG 编码的图片字节
  Future<MathInkRecognitionResult> recognizeFromPng(Uint8List pngBytes) async {
    if (onlineApiUrl == null) {
      // 未配置在线 API，无法识别图片
      return MathInkRecognitionResult.empty();
    }
    return _recognizePngViaOnlineApi(pngBytes);
  }

  /// 通过 FRB 调用 Rust 端 `math_ink_recognize`
  ///
  /// 替代原 C ABI: 直接通过 DynamicLibrary.lookup 查找 math_ink_recognize 符号。
  /// 现使用 FRB v2 类型安全绑定，消除手写 dart:ffi 代码。
  Future<MathInkRecognitionResult> _recognizeViaFrb(List<List<Offset>> strokes) async {
    // 序列化笔触为 JSON（与 Rust 端 InkStroke 结构对齐）
    final strokesJson = jsonEncode(strokes.map((stroke) {
      return {
        'points': stroke
            .map((p) => [p.dx, p.dy])
            .toList(),
        'pressure': 0.5,
        'timestamp': 0,
      };
    }).toList());

    // FRB v2 调用 —— 类型安全，自动内存管理
    final result = await rust.mathInkRecognize(strokesJson: strokesJson);
    return MathInkRecognitionResult.fromRust(result);
  }

  /// 通过在线 API 识别笔触（用户可选）
  Future<MathInkRecognitionResult> _recognizeViaOnlineApi(
    List<List<Offset>> strokes,
  ) async {
    // 将笔迹渲染为 PNG（这里简化为发送笔迹 JSON 给 API）
    // 实际生产中应渲染为 PNG 后调用 recognizeFromPng
    final payload = jsonEncode({
      'strokes': strokes
          .map((stroke) => stroke
              .map((p) => {'x': p.dx, 'y': p.dy})
              .toList())
          .toList(),
    });

    final response = await http.post(
      Uri.parse(onlineApiUrl!),
      headers: {
        'Content-Type': 'application/json',
        if (onlineApiToken != null) 'Authorization': 'Bearer $onlineApiToken',
      },
      body: payload,
    );

    if (response.statusCode != 200) {
      throw StateError('Online API failed: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return MathInkRecognitionResult.fromJson(decoded);
  }

  /// 通过在线 API 识别 PNG 图片
  Future<MathInkRecognitionResult> _recognizePngViaOnlineApi(
    Uint8List pngBytes,
  ) async {
    final base64Data = base64Encode(pngBytes);
    final payload = jsonEncode({
      'image': base64Data,
    });

    final response = await http.post(
      Uri.parse(onlineApiUrl!),
      headers: {
        'Content-Type': 'application/json',
        if (onlineApiToken != null) 'Authorization': 'Bearer $onlineApiToken',
      },
      body: payload,
    );

    if (response.statusCode != 200) {
      throw StateError('Online API failed: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return MathInkRecognitionResult.fromJson(decoded);
  }
}
