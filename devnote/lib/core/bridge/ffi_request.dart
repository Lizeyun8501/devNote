import 'dart:convert';
import 'dart:typed_data';

class FFIRequest {
  final String event;
  final Uint8List? payload;

  const FFIRequest({
    required this.event,
    this.payload,
  });

  Uint8List toBuffer() {
    final map = <String, dynamic>{
      'event': event,
    };
    if (payload != null) {
      map['payload'] = base64Encode(payload!);
    }
    return utf8.encode(jsonEncode(map));
  }
}
