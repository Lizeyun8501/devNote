// FFI 桥接层 —— Dart 端通过 C ABI 调用 Rust 函数
// 借鉴 AppFlowy 的 FFI 绑定实现模式
//
// 借鉴 AppFlowy 的 FFI 绑定实现模式
// 来源: https://github.com/AppFlowy-IO/AppFlowy
// 借鉴内容: DynamicLibrary 动态加载 native 库、Native/Dart 函数类型定义映射、
//         malloc/free 内存管理、跨平台库路径适配

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi_request.dart';
import 'ffi_response.dart';

typedef DevnoteInitNative = Pointer<FFIResponseC> Function();
typedef DevnoteInitDart = Pointer<FFIResponseC> Function();

typedef DevnoteDestroyNative = Void Function(Pointer<FFIResponseC>);
typedef DevnoteDestroyDart = void Function(Pointer<FFIResponseC>);

typedef DevnotePingNative = Pointer<Utf8> Function();
typedef DevnotePingDart = Pointer<Utf8> Function();

typedef DevnoteDispatchNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef DevnoteDispatchDart = Pointer<Utf8> Function(Pointer<Utf8>);

typedef DevnoteFreeStringNative = Void Function(Pointer<Utf8>);
typedef DevnoteFreeStringDart = void Function(Pointer<Utf8>);

@Native<DevnoteFreeStringNative>()
external void devnoteFreeString(Pointer<Utf8> s);

final class FFIResponseC extends Struct {
  @Int32()
  external int code;

  external Pointer<Utf8> message;

  external Pointer<Utf8> data;
}

class FFIBridge {
  FFIBridge();

  DynamicLibrary? _dylib;
  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

  DevnoteInitDart? devnoteInit;
  DevnoteDestroyDart? devnoteDestroy;
  DevnotePingDart? devnotePing;
  DevnoteDispatchDart? devnoteDispatch;

  Future<void> init() async {
    try {
      _dylib = _loadDynamicLibrary();
      devnoteInit = _dylib!.lookupFunction<DevnoteInitNative, DevnoteInitDart>(
        'devnote_init',
      );
      devnoteDestroy = _dylib!.lookupFunction<DevnoteDestroyNative, DevnoteDestroyDart>(
        'devnote_destroy',
      );
      devnotePing = _dylib!.lookupFunction<DevnotePingNative, DevnotePingDart>(
        'devnote_ping',
      );
      devnoteDispatch = _dylib!.lookupFunction<DevnoteDispatchNative, DevnoteDispatchDart>(
        'devnote_dispatch',
      );

      // Call devnote_init() via FFI to initialize the Rust runtime
      final initResult = devnoteInit!();
      try {
        if (initResult.code == 0) {
          _isAvailable = true;
        } else {
          _isAvailable = false;
        }
      } finally {
        if (devnoteDestroy != null) {
          devnoteDestroy!(initResult);
        }
      }
    } catch (e) {
      _isAvailable = false;
      _dylib = null;
      devnoteInit = null;
      devnoteDestroy = null;
      devnotePing = null;
      devnoteDispatch = null;
      rethrow;
    }
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

  FFIResponse invoke(FFIRequest request) {
    if (!_isAvailable || devnoteDispatch == null) {
      return const FFIResponse(code: -1, message: 'FFI bridge not available');
    }
    final requestBuffer = request.toBuffer();
    final requestPtr = malloc<Uint8>(requestBuffer.length + 1);
    try {
      for (var i = 0; i < requestBuffer.length; i++) {
        requestPtr[i] = requestBuffer[i];
      }
      requestPtr[requestBuffer.length] = 0;

      final responsePtr = devnoteDispatch!(requestPtr.cast<Utf8>());
      try {
        final responseStr = responsePtr.toDartString();
        return FFIResponse.fromBuffer(Uint8List.fromList(responseStr.codeUnits));
      } finally {
        devnoteFreeString(responsePtr);
      }
    } finally {
      malloc.free(requestPtr);
    }
  }

  String ping() {
    if (!_isAvailable || devnotePing == null) {
      return 'FFI not available';
    }
    final ptr = devnotePing!();
    try {
      return ptr.toDartString();
    } finally {
      devnoteFreeString(ptr);
    }
  }

  void dispose() {
    _dylib = null;
  }
}
