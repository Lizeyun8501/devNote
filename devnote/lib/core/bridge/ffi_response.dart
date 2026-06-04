import 'dart:convert';
import 'dart:typed_data';

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
