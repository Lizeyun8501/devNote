import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'ffi_response.dart';
import 'native_bridge.dart';

typedef DevnoteGrpcConnectNative = Pointer<FFIResponseC> Function(Pointer<Utf8>);
typedef DevnoteGrpcConnectDart = Pointer<FFIResponseC> Function(Pointer<Utf8>);

typedef DevnoteGrpcDisconnectNative = Pointer<FFIResponseC> Function();
typedef DevnoteGrpcDisconnectDart = Pointer<FFIResponseC> Function();

typedef DevnoteGrpcDispatchNative = Pointer<FFIResponseC> Function(
    Pointer<Utf8>, Pointer<Utf8>);
typedef DevnoteGrpcDispatchDart = Pointer<FFIResponseC> Function(
    Pointer<Utf8>, Pointer<Utf8>);

/// gRPC bridge that wraps the Rust FFI gRPC client
/// 修复(P1): 继承 NativeBridge，消除与 WebSocketBridge 重复的 _loadDynamicLibrary /
/// _readResponse / devnoteDestroy lookup / init / dispose 代码。
class GrpcBridge extends NativeBridge {
  GrpcBridge();

  late final DevnoteGrpcConnectDart devnoteGrpcConnect;
  late final DevnoteGrpcDisconnectDart devnoteGrpcDisconnect;
  late final DevnoteGrpcDispatchDart devnoteGrpcDispatch;

  @override
  void lookupFunctions(DynamicLibrary dylib) {
    devnoteGrpcConnect =
        dylib.lookupFunction<DevnoteGrpcConnectNative, DevnoteGrpcConnectDart>(
      'devnote_grpc_connect',
    );
    devnoteGrpcDisconnect =
        dylib.lookupFunction<DevnoteGrpcDisconnectNative, DevnoteGrpcDisconnectDart>(
      'devnote_grpc_disconnect',
    );
    devnoteGrpcDispatch =
        dylib.lookupFunction<DevnoteGrpcDispatchNative, DevnoteGrpcDispatchDart>(
      'devnote_grpc_dispatch',
    );
  }

  /// Connect to a gRPC server
  FFIResponse connect(String serverAddr) {
    final addrPtr = serverAddr.toNativeUtf8();
    try {
      final responsePtr = devnoteGrpcConnect(addrPtr);
      final response = readResponse(responsePtr);
      devnoteDestroy(responsePtr);
      return response;
    } finally {
      malloc.free(addrPtr);
    }
  }

  /// Disconnect from the gRPC server
  FFIResponse disconnect() {
    final responsePtr = devnoteGrpcDisconnect();
    final response = readResponse(responsePtr);
    devnoteDestroy(responsePtr);
    return response;
  }

  /// Dispatch a request via gRPC
  FFIResponse dispatch(String method, {String? payload}) {
    final methodPtr = method.toNativeUtf8();
    final payloadPtr = payload?.toNativeUtf8() ?? nullptr;
    try {
      final responsePtr = devnoteGrpcDispatch(methodPtr, payloadPtr);
      final response = readResponse(responsePtr);
      devnoteDestroy(responsePtr);
      return response;
    } finally {
      malloc.free(methodPtr);
      if (payloadPtr != nullptr) {
        malloc.free(payloadPtr);
      }
    }
  }
}
