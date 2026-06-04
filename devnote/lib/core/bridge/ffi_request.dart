import 'dart:convert';
import 'dart:typed_data';

class FFIRequest {
  final String event;
  final Uint8List? payload;
  final int? requestId;

  const FFIRequest({
    required this.event,
    this.payload,
    this.requestId,
  });

  Uint8List toBuffer() {
    final map = <String, dynamic>{
      'event': event,
    };
    if (payload != null) {
      map['payload'] = base64Encode(payload!);
    }
    if (requestId != null) {
      map['request_id'] = requestId;
    }
    return utf8.encode(jsonEncode(map));
  }
}
