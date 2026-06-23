// AUTO-GENERED BY flutter_rust_bridge v2 — DO NOT EDIT MANUALLY
//
// 此文件由 `flutter_rust_bridge_codegen generate` 自动生成。
// 首次使用前必须运行 codegen：
//   flutter_rust_bridge_codegen generate
//
// 文档: https://cjycode.com/flutter_rust_bridge/

import 'dart:ffi' as ffi;
import 'dart:io' as io;

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'frb_generated.io.dart' if (dart.library.html) 'frb_generated.web.dart' as platform;

/// FRB 运行时入口 —— 负责加载 native 动态库并初始化编解码器
///
/// 调用方式：
/// ```dart
/// await RustLib.init();
/// ```
/// init() 会自动加载 libdevnote_ffi.so/.dylib/.dll 并完成 FRB 内部状态初始化。
class RustLib {
  RustLib._();

  static final RustLib instance = RustLib._();

  /// FRB 内部 API 句柄（codegen 写入实际调用逻辑）
  late final RustLibApi api;

  /// 是否已初始化
  bool _initialized = false;
  bool get initialized => _initialized;

  /// 初始化 FRB 运行时 —— 加载 native 动态库 + 初始化编解码器
  Future<void> init() async {
    if (_initialized) return;
    await platform.initImpl(this);
    _initialized = true;
  }

  /// 加载平台对应的 native 动态库
  ffi.DynamicLibrary _loadNativeLibrary() {
    if (io.Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libdevnote_ffi.so');
    }
    if (io.Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }
    if (io.Platform.isMacOS) {
      return ffi.DynamicLibrary.open('libdevnote_ffi.dylib');
    }
    if (io.Platform.isLinux) {
      return ffi.DynamicLibrary.open('libdevnote_ffi.so');
    }
    if (io.Platform.isWindows) {
      return ffi.DynamicLibrary.open('devnote_ffi.dll');
    }
    throw UnsupportedError('Unsupported platform: ${io.Platform.operatingSystem}');
  }
}

/// FRB API 句柄 —— codegen 生成的实际函数调用入口
///
/// 每个方法对应 frb_api.rs 中的一个 pub fn。
/// codegen 运行后会替换为真实的 SSE 编解码调用。
class RustLibApi {
  RustLibApi._(this._dylib);

  final ffi.DynamicLibrary _dylib;
}
