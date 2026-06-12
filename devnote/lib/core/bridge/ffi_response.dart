import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

/// FFI C 结构体 —— 用于 native 库返回的响应
///
/// 修复: 旧 grpc_bridge.dart / websocket_bridge.dart 引用了 FFIResponseC,
/// 但实际从未定义,导致编译失败。添加最小的 C struct 兼容层,
/// 仅用于满足 typedef 引用,不参与实际数据传输。
base class FFIResponseC extends Struct {
  external Pointer<Uint8> data;
  @Size()
  external int data_len;
  @Int32()
  external int code;
  // 兼容层: 旧代码通过 .ref.message (Pointer<Uint8>) 访问响应内容
  external Pointer<Uint8> message;
}

class FFIResponse {
  final int code;
  final String message;
  final Uint8List? data;

  const FFIResponse({
    required this.code,
    required this.message,
    this.data,
  });

  factory FFIResponse.fromBuffer(Uint8List buffer) {
    final json = jsonDecode(utf8.decode(buffer)) as Map<String, dynamic>;
    final dataRaw = json['data'];
    Uint8List? data;
    if (dataRaw != null && dataRaw is List) {
      data = Uint8List.fromList(dataRaw.cast<int>());
    }
    return FFIResponse(
      code: json['code'] as int,
      message: json['message'] as String? ?? '',
      data: data,
    );
  }

  bool get isOk => code == 0;

  @override
  String toString() => 'FFIResponse(code: $code, message: $message, hasData: ${data != null})';
}
