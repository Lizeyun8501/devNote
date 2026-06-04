/// FFIBridge - Dart 与 Rust 之间的 FFI 桥接层
///
/// ## 当前实现
/// 采用自研的 DynamicLibrary + NativeFunction 绑定方案（~238 行 Dart + ~1840 行 Rust），
/// 借鉴 AppFlowy 的 FFI 实现模式：Event-Dispatch 架构、JSON 序列化通信。
///
/// ====================================================================
/// ## 开源替代迁移路径：flutter_rust_bridge v2
/// ====================================================================
///
/// ### 建议策略：渐进式迁移（现有代码不动，新功能用 FRB）
///
/// ### 第一阶段（当前 - 准备）
/// - [ ] 添加 flutter_rust_bridge 作为依赖
/// - [ ] 创建 frb/ 目录，专门存放 FRB 生成的代码
/// - [ ] 在 Rust 端创建 frb_api.rs，导出 FRB 兼容的函数
///
/// ### 第二阶段（新功能优先）
/// - [ ] 新功能（如 P2P 连接、Plugin 管理）直接使用 FRB 生成绑定
/// - [ ] 新增加的 Rust 函数通过 FRB 导出（而非手写 Event-Dispatch 模式）
/// - [ ] 验证 FRB 绑定的稳定性、性能和异步支持
///
/// ### 第三阶段（逐步迁移）
/// - [ ] 将 Event-Dispatch 的核心事件逐个替换为 FRB 直接函数调用
/// - [ ] 按层迁移：read-only 函数 → write 函数 → Stream 订阅
/// - [ ] 每迁移一个事件，删除对应手写 FFI 代码
///
/// ### 迁移收益
/// - 消除手动 malloc/free 和 catch_unwind 的 ~300 行内存管理代码
/// - 自动生成类型安全绑定，消除双端 JSON schema 不一致的 bug
/// - SSE 编解码器比 JSON 序列化快数倍
/// - 新增 Rust 函数只需 `flutter_rust_bridge_codegen generate`
///
/// ### 风险控制
/// - 旧代码和新 FRB 代码可以共存（不同的事件命名空间）
/// - 每个事件迁移后可单独验证，支持回滚
/// - 预计迁移周期：3-6 个月
///
/// 来源: https://pub.dev/packages/flutter_rust_bridge
/// 版本: v2.12.0
/// Flutter Favorite: ✅
/// ====================================================================

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

  /// FfiV2Adapter —— flutter_rust_bridge 渐进迁移适配器
  ///
  /// 使用方式：
  ///   final bridge = FFIBridge();
  ///   // 旧代码继续使用 bridge.dispatch()
  ///   // 新代码使用 bridge.v2Adapter.noteSearch()
  FfiV2Adapter? _v2Adapter;
  FfiV2Adapter get v2Adapter {
    _v2Adapter ??= FfiV2Adapter(this);
    return _v2Adapter!;
  }
}

/// FfiV2Adapter —— flutter_rust_bridge 迁移适配器
///
/// 当添加新功能到 Rust 端时：
/// 1. 在 Rust 端用 FRB 宏标注导出的函数
/// 2. 运行 `flutter_rust_bridge_codegen generate` 生成 Dart 绑定
/// 3. 在此适配器中封装生成的绑定，提供与 FFIBridge 一致的接口
///
/// 当迁移现有功能时：
/// 1. 在 Rust 端重新实现对应函数，添加 FRB 注解
/// 2. 生成绑定后，在适配器中实现新方法
/// 3. 逐步替换调用方，最后移除旧的自研 FFI 代码
class FfiV2Adapter {
  final FFIBridge legacy;

  FfiV2Adapter(this.legacy);

  /// 示例：FRB 生成的搜索函数（迁移完成后替换 SearchEvent）
  /// Future<List<SearchResult>> noteSearch(String query) =>
  ///     frbGeneratedSearch(query);

  /// 所有新 Rust 功能都通过此类方法暴露，而非直接新建 dispatch handler
}