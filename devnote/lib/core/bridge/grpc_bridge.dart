import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi_response.dart';

typedef DevnoteDestroyNative = Void Function(Pointer<FFIResponseC>);
typedef DevnoteDestroyDart = void Function(Pointer<FFIResponseC>);

typedef DevnoteGrpcConnectNative = Pointer<FFIResponseC> Function(Pointer<Utf8>);
typedef DevnoteGrpcConnectDart = Pointer<FFIResponseC> Function(Pointer<Utf8>);

typedef DevnoteGrpcDisconnectNative = Pointer<FFIResponseC> Function();
typedef DevnoteGrpcDisconnectDart = Pointer<FFIResponseC> Function();

typedef DevnoteGrpcDispatchNative = Pointer<FFIResponseC> Function(
    Pointer<Utf8>, Pointer<Utf8>);
typedef DevnoteGrpcDispatchDart = Pointer<FFIResponseC> Function(
    Pointer<Utf8>, Pointer<Utf8>);

/// gRPC bridge that wraps the Rust FFI gRPC client
class GrpcBridge {
  GrpcBridge();

  DynamicLibrary? _dylib;

  late final DevnoteDestroyDart devnoteDestroy;
  late final DevnoteGrpcConnectDart devnoteGrpcConnect;
  late final DevnoteGrpcDisconnectDart devnoteGrpcDisconnect;
  late final DevnoteGrpcDispatchDart devnoteGrpcDispatch;

  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _dylib = _loadDynamicLibrary();
    devnoteDestroy =
        _dylib!.lookupFunction<DevnoteDestroyNative, DevnoteDestroyDart>(
      'devnote_destroy',
    );
    devnoteGrpcConnect =
        _dylib!.lookupFunction<DevnoteGrpcConnectNative, DevnoteGrpcConnectDart>(
      'devnote_grpc_connect',
    );
    devnoteGrpcDisconnect =
        _dylib!.lookupFunction<DevnoteGrpcDisconnectNative, DevnoteGrpcDisconnectDart>(
      'devnote_grpc_disconnect',
    );
    devnoteGrpcDispatch =
        _dylib!.lookupFunction<DevnoteGrpcDispatchNative, DevnoteGrpcDispatchDart>(
      'devnote_grpc_dispatch',
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

  /// Connect to a gRPC server
  /// 修复：添加 try-finally 确保 FFI 分配的内存即使异常也能释放
  FFIResponse connect(String serverAddr) {
    final addrPtr = serverAddr.toNativeUtf8();
    try {
      final responsePtr = devnoteGrpcConnect(addrPtr);
      final response = _readResponse(responsePtr);
      devnoteDestroy(responsePtr);
      return response;
    } finally {
      malloc.free(addrPtr);
    }
  }

  /// Disconnect from the gRPC server
  FFIResponse disconnect() {
    final responsePtr = devnoteGrpcDisconnect();
    final response = _readResponse(responsePtr);
    devnoteDestroy(responsePtr);
    return response;
  }

  /// Dispatch a request via gRPC
  /// 修复：添加 try-finally 确保 FFI 分配的内存即使异常也能释放
  FFIResponse dispatch(String method, {String? payload}) {
    final methodPtr = method.toNativeUtf8();
    final payloadPtr = payload?.toNativeUtf8() ?? nullptr;
    try {
      final responsePtr = devnoteGrpcDispatch(methodPtr, payloadPtr);
      final response = _readResponse(responsePtr);
      devnoteDestroy(responsePtr);
      return response;
    } finally {
      malloc.free(methodPtr);
      if (payloadPtr != nullptr) {
        malloc.free(payloadPtr);
      }
    }
  }

  FFIResponse _readResponse(Pointer<FFIResponseC> ptr) {
    final code = ptr.ref.code;
    // message 为 CString（null-terminated），直接用 toDartString() 读取
    final message = ptr.ref.message.toDartString();
    final dataPtr = ptr.ref.data;

    Uint8List? data;
    if (dataPtr != nullptr) {
      // 修复(P0): data 为 CString（null-terminated UTF-8），
      // 用 toDartString() 取字符串后转字节，替代旧代码读取未初始化的 data_len
      final dataStr = dataPtr.toDartString();
      data = Uint8List.fromList(utf8.encode(dataStr));
    }

    return FFIResponse(code: code, message: message, data: data);
  }

  void dispose() {
    _dylib = null;
    _initialized = false;
  }
}