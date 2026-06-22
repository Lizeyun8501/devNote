import '../models/ink_stroke.dart';

/// 手写文字识别服务
///
/// 将手写笔触转换为文字。优先适配 iPad + Apple Pencil 和 Surface + Surface Pen。
///
/// 此功能需要集成平台原生手写识别 API：
/// - iOS/macOS: Vision framework 的 VNRecognizeHandwritingRequest
///   来源: https://developer.apple.com/documentation/vision/vnrecognizehandwritingrequest
/// - Android: ML Kit Digital Ink Recognition
///   来源: https://developers.google.com/ml-kit/vision/digital-ink-recognition
///
/// 当前为接口框架，待平台原生集成后实现。
class HandwritingRecognitionService {
  /// 识别手写笔触并返回文字
  ///
  /// [strokes] 手写笔触列表
  /// [lang] 语言代码，例如 "zh-Hans"、"en-US"
  Future<String> recognize(List<InkStroke> strokes, String lang) async {
    // TODO: 通过 MethodChannel 调用平台原生手写识别
    // iOS: 使用 Vision framework 的 VNRecognizeHandwritingRequest
    // Android: 使用 ML Kit Digital Ink Recognition
    return '';
  }
}
