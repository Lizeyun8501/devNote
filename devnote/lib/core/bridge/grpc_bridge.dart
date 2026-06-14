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
    // 修复: 原代码对 Pointer<Uint8> 调用 toDartString() 不存在,改为 cast 到 Pointer<Utf8>
    final message = ptr.ref.message.cast<Utf8>().toDartString();
    final dataPtr = ptr.ref.data;

    Uint8List? data;
    if (dataPtr != nullptr) {
      // 修复: 原代码将字节流误用 toDartString 后取 codeUnits,
      // 正确做法是按 data_len 长度复制字节
      final length = ptr.ref.data_len;
      data = Uint8List(length);
      for (var i = 0; i < length; i++) {
        data[i] = dataPtr.elementAt(i).value;
      }
    }

    return FFIResponse(code: code, message: message, data: data);
  }

  void dispose() {
    _dylib = null;
    _initialized = false;
  }
}