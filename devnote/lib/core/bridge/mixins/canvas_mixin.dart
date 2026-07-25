// Canvas API Mixin —— 基于 flutter_rust_bridge v2
//
// 从 FFIBridge 中抽取的 Canvas API。通过 FRB 生成的类型安全绑定调用 Rust。
//
// 拆分理由:
// - Canvas 操作属领域 API，独立后便于维护
// - 16 个方法（6 个 FRB + 10 个 stub），约 60 行
// - 独立后便于未来实现 Canvas 持久化或移除未实现的 stub

import 'package:devnote/src/rust/library.dart' as rust;

/// Canvas API Mixin
///
/// 宿主类需实现 [ffiCheckAvailable] 提供 FFI 可用性检查。
/// 无对应 FRB 函数的方法返回降级结果（空 JSON/空操作），
/// 调用方应检测返回值而非依赖 try-catch。
mixin CanvasMixin {
  /// 宿主类提供：检查 FFI 是否可用，不可用则抛 StateError
  void ffiCheckAvailable();

  /// 宿主类提供：P0 架构修复 —— 引擎句柄，所有 FRB API 调用均需传入
  BigInt get engineHandle;

  // ── 有 FRB 绑定的方法 ───────────────────────────────────

  Future<void> canvasAddNode({required String canvasId, required String nodeJson}) async {
    ffiCheckAvailable();
    await rust.canvasAddNode(engineHandle: engineHandle, canvasId: canvasId, nodeJson: nodeJson);
  }

  Future<void> canvasRemoveNode({required String canvasId, required String nodeId}) async {
    ffiCheckAvailable();
    await rust.canvasRemoveNode(engineHandle: engineHandle, canvasId: canvasId, nodeId: nodeId);
  }

  Future<void> canvasAutoLayout({required String canvasId, required String layoutType}) async {
    ffiCheckAvailable();
    await rust.canvasAutoLayout(engineHandle: engineHandle, canvasId: canvasId, layoutType: layoutType);
  }

  Future<void> canvasAddEdge({required String canvasId, required String edgeJson}) async {
    ffiCheckAvailable();
    await rust.canvasAddEdge(engineHandle: engineHandle, canvasId: canvasId, edgeJson: edgeJson);
  }

  Future<void> canvasSaveCanvas({required String canvasId, required String path}) async {
    ffiCheckAvailable();
    await rust.canvasSaveCanvas(engineHandle: engineHandle, canvasId: canvasId, path: path);
  }

  Future<String> canvasLoadCanvas({required String path}) async {
    ffiCheckAvailable();
    return rust.canvasLoadCanvas(engineHandle: engineHandle, path: path);
  }

  // ── 无 FRB 绑定的 stub 方法（返回降级结果）──────────

  Future<String> canvasCreateCanvas() async => '{}';
  Future<Map<String, dynamic>> canvasGetCanvas({required String canvasId}) async => {};
  Future<void> canvasMoveNode({required String canvasId, required String nodeId, required double x, required double y}) async {}
  Future<void> canvasResizeNode({required String canvasId, required String nodeId, required double width, required double height}) async {}
  Future<void> canvasRemoveEdge({required String canvasId, required String edgeId}) async {}
  Future<void> canvasStartCollaboration({required String canvasId, required String sessionId}) async {}
  Future<Map<String, dynamic>> canvasJoinCollaboration({required String sessionId}) async => {};
  Future<void> canvasBroadcastChange({required String changeJson}) async {}
  Future<void> canvasEndCollaboration({required String sessionId}) async {}
}
