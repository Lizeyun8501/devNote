// FFI 桥接层 —— Dart 端通过 C ABI 调用 Rust 函数
// 借鉴 AppFlowy 的 FFI 绑定实现模式
//
// 借鉴 AppFlowy 的 FFI 绑定实现模式
// 来源: https://github.com/AppFlowy-IO/AppFlowy
// 借鉴内容: DynamicLibrary 动态加载 native 库、Native/Dart 函数类型定义映射、
//         malloc/free 内存管理、跨平台库路径适配

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi_request.dart';
import 'ffi_response.dart';

/// FFI 协议版本 —— 与 Rust 端 devnote-ffi FFI_API_VERSION 常量严格一致
/// 修改此值时必须同步修改 Rust 端并记录到 migration_notes.md
const int kFFIApiVersion = 1;

/// 协议协商结果
class FfiVersionInfo {
  final int apiVersion;
  final String rustVersion;
  final int compatibleMin;
  final List<String> features;

  FfiVersionInfo({
    required this.apiVersion,
    required this.rustVersion,
    required this.compatibleMin,
    required this.features,
  });

  bool get isCompatible => apiVersion >= compatibleMin && kFFIApiVersion >= compatibleMin;
}

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

  /// FFI 协议协商 —— init() 后必须调用以确保 native 库与 UI 协议版本兼容
  /// 借鉴 AppFlowy 的 FFI 版本协商
  /// 来源: https://github.com/AppFlowy-IO/AppFlowy
  Future<FfiVersionInfo?> negotiateVersion() async {
    if (!_isAvailable || devnoteDispatch == null) return null;
    try {
      final req = FFIRequest(
        event: 'SystemEvent.GetVersion',
        payload: Uint8List(0),
        requestId: 0,
      );
      final resp = invoke(req);
      if (resp.code != 0 || resp.data == null) return null;
      final m = jsonDecode(resp.data!) as Map<String, dynamic>;
      return FfiVersionInfo(
        apiVersion: m['api_version'] as int? ?? 0,
        rustVersion: m['rust_version'] as String? ?? 'unknown',
        compatibleMin: m['compatible_min'] as int? ?? 1,
        features: List<String>.from(m['features'] as List? ?? const []),
      );
    } catch (_) {
      return null;
    }
  }

  /// 健康检查 —— 返回各引擎的就绪状态
  Future<Map<String, bool>?> healthCheck() async {
    if (!_isAvailable || devnoteDispatch == null) return null;
    try {
      final req = FFIRequest(
        event: 'SystemEvent.HealthCheck',
        payload: Uint8List(0),
        requestId: 0,
      );
      final resp = invoke(req);
      if (resp.code != 0 || resp.data == null) return null;
      final m = jsonDecode(resp.data!) as Map<String, dynamic>;
      final engines = m['engines'] as Map<String, dynamic>? ?? const {};
      return engines.map((k, v) => MapEntry(k, v == true));
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _dylib = null;
  }
}
