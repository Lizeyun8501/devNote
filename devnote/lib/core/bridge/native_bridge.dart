import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi_response.dart';

/// 修复(P1): 抽取 NativeBridge 基类，消除 GrpcBridge / WebSocketBridge 中的重复代码。
///
/// 原实现中以下代码在两个 bridge 中逐字符相同：
///   - _loadDynamicLibrary()（18 行平台判断）
///   - _readResponse()（FFIResponse 解析）
///   - devnoteDestroy lookup
///   - init() / dispose() 结构
///
/// 基类提供公共逻辑，子类仅需实现 [lookupFunctions] 注册各自的 FFI 函数。
typedef DevnoteDestroyNative = Void Function(Pointer<FFIResponseC>);
typedef DevnoteDestroyDart = void Function(Pointer<FFIResponseC>);

abstract class NativeBridge {
  DynamicLibrary? _dylib;
  late final DevnoteDestroyDart devnoteDestroy;
  bool _initialized = false;

  /// 子类实现：在 [_dylib] 上查找各自的 FFI 函数并赋值给字段。
  void lookupFunctions(DynamicLibrary dylib);

  /// 初始化 FFI 桥接：加载动态库 + 查找函数。
  void init() {
    if (_initialized) return;
    _dylib = _loadDynamicLibrary();
    devnoteDestroy =
        _dylib!.lookupFunction<DevnoteDestroyNative, DevnoteDestroyDart>(
      'devnote_destroy',
    );
    lookupFunctions(_dylib!);
    _initialized = true;
  }

  /// 跨平台加载 native 动态库。
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

  /// 从 FFI 返回的 C 结构体指针读取响应。
  /// 字段顺序与 Rust 端 #[repr(C)] FFIResponse 一致：code / message / data。
  FFIResponse readResponse(Pointer<FFIResponseC> ptr) {
    final code = ptr.ref.code;
    final message = ptr.ref.message.toDartString();
    final dataPtr = ptr.ref.data;

    Uint8List? data;
    if (dataPtr != nullptr) {
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
