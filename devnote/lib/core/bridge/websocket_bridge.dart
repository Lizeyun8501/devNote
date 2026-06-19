import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'ffi_response.dart';
import 'native_bridge.dart';

typedef DevnoteWsConnectNative = Pointer<FFIResponseC> Function(Pointer<Utf8>);
typedef DevnoteWsConnectDart = Pointer<FFIResponseC> Function(Pointer<Utf8>);

typedef DevnoteWsDisconnectNative = Pointer<FFIResponseC> Function();
typedef DevnoteWsDisconnectDart = Pointer<FFIResponseC> Function();

typedef DevnoteWsSendNative = Pointer<FFIResponseC> Function(Pointer<Utf8>);
typedef DevnoteWsSendDart = Pointer<FFIResponseC> Function(Pointer<Utf8>);

/// WebSocket bridge that wraps the Rust FFI WebSocket client
/// 修复(P1): 继承 NativeBridge，消除与 GrpcBridge 重复的 _loadDynamicLibrary /
/// _readResponse / devnoteDestroy lookup / init / dispose 代码。
class WebSocketBridge extends NativeBridge {
  WebSocketBridge();

  late final DevnoteWsConnectDart devnoteWsConnect;
  late final DevnoteWsDisconnectDart devnoteWsDisconnect;
  late final DevnoteWsSendDart devnoteWsSend;

  @override
  void lookupFunctions(DynamicLibrary dylib) {
    devnoteWsConnect =
        dylib.lookupFunction<DevnoteWsConnectNative, DevnoteWsConnectDart>(
      'devnote_ws_connect',
    );
    devnoteWsDisconnect =
        dylib.lookupFunction<DevnoteWsDisconnectNative, DevnoteWsDisconnectDart>(
      'devnote_ws_disconnect',
    );
    devnoteWsSend =
        dylib.lookupFunction<DevnoteWsSendNative, DevnoteWsSendDart>(
      'devnote_ws_send',
    );
  }

  /// Connect to a WebSocket server
  FFIResponse connect(String url) {
    final urlPtr = url.toNativeUtf8();
    try {
      final responsePtr = devnoteWsConnect(urlPtr);
      final response = readResponse(responsePtr);
      devnoteDestroy(responsePtr);
      return response;
    } finally {
      malloc.free(urlPtr);
    }
  }

  /// Disconnect from the WebSocket server
  FFIResponse disconnect() {
    final responsePtr = devnoteWsDisconnect();
    final response = readResponse(responsePtr);
    devnoteDestroy(responsePtr);
    return response;
  }

  /// Send a message via WebSocket
  FFIResponse send(String message) {
    final msgPtr = message.toNativeUtf8();
    try {
      final responsePtr = devnoteWsSend(msgPtr);
      final response = readResponse(responsePtr);
      devnoteDestroy(responsePtr);
      return response;
    } finally {
      malloc.free(msgPtr);
    }
  }

  /// Send a JSON message via WebSocket
  FFIResponse sendJson(Map<String, dynamic> json) {
    return send(jsonEncode(json));
  }
}
