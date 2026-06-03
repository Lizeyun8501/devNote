import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi_response.dart';

typedef DevnoteDestroyNative = Void Function(Pointer<FFIResponseC>);
typedef DevnoteDestroyDart = void Function(Pointer<FFIResponseC>);

typedef DevnoteWsConnectNative = Pointer<FFIResponseC> Function(Pointer<Utf8>);
typedef DevnoteWsConnectDart = Pointer<FFIResponseC> Function(Pointer<Utf8>);

typedef DevnoteWsDisconnectNative = Pointer<FFIResponseC> Function();
typedef DevnoteWsDisconnectDart = Pointer<FFIResponseC> Function();

typedef DevnoteWsSendNative = Pointer<FFIResponseC> Function(Pointer<Utf8>);
typedef DevnoteWsSendDart = Pointer<FFIResponseC> Function(Pointer<Utf8>);

/// WebSocket bridge that wraps the Rust FFI WebSocket client
class WebSocketBridge {
  WebSocketBridge._();

  static final WebSocketBridge _instance = WebSocketBridge._();
  static WebSocketBridge get instance => _instance;

  DynamicLibrary? _dylib;

  late final DevnoteDestroyDart devnoteDestroy;
  late final DevnoteWsConnectDart devnoteWsConnect;
  late final DevnoteWsDisconnectDart devnoteWsDisconnect;
  late final DevnoteWsSendDart devnoteWsSend;

  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _dylib = _loadDynamicLibrary();
    devnoteDestroy =
        _dylib!.lookupFunction<DevnoteDestroyNative, DevnoteDestroyDart>(
      'devnote_destroy',
    );
    devnoteWsConnect =
        _dylib!.lookupFunction<DevnoteWsConnectNative, DevnoteWsConnectDart>(
      'devnote_ws_connect',
    );
    devnoteWsDisconnect =
        _dylib!.lookupFunction<DevnoteWsDisconnectNative, DevnoteWsDisconnectDart>(
      'devnote_ws_disconnect',
    );
    devnoteWsSend =
        _dylib!.lookupFunction<DevnoteWsSendNative, DevnoteWsSendDart>(
      'devnote_ws_send',
    );
    _initialized = true;
  }

  DynamicLibrary _loadDynamicLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libdevnote_ffi.so');
    }
    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open('libdevnote_ffi.dylib');
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('libdevnote_ffi.so');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('devnote_ffi.dll');
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  /// Connect to a WebSocket server
  FFIResponse connect(String url) {
    final urlPtr = url.toNativeUtf8();
    final responsePtr = devnoteWsConnect(urlPtr);
    malloc.free(urlPtr);

    final response = _readResponse(responsePtr);
    devnoteDestroy(responsePtr);
    return response;
  }

  /// Disconnect from the WebSocket server
  FFIResponse disconnect() {
    final responsePtr = devnoteWsDisconnect();
    final response = _readResponse(responsePtr);
    devnoteDestroy(responsePtr);
    return response;
  }

  /// Send a message via WebSocket
  FFIResponse send(String message) {
    final msgPtr = message.toNativeUtf8();
    final responsePtr = devnoteWsSend(msgPtr);
    malloc.free(msgPtr);

    final response = _readResponse(responsePtr);
    devnoteDestroy(responsePtr);
    return response;
  }

  /// Send a JSON message via WebSocket
  FFIResponse sendJson(Map<String, dynamic> json) {
    return send(jsonEncode(json));
  }

  FFIResponse _readResponse(Pointer<FFIResponseC> ptr) {
    final code = ptr.ref.code;
    final message = ptr.ref.message.toDartString();
    final dataPtr = ptr.ref.data;

    Uint8List? data;
    if (dataPtr != nullptr) {
      data = Uint8List.fromList(dataPtr.toDartString().codeUnits);
    }

    return FFIResponse(code: code, message: message, data: data);
  }

  void dispose() {
    _dylib = null;
    _initialized = false;
  }
}