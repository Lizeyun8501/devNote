// P2 修复 (P2-4): FFIBridge God Class 进一步拆分 —— Canvas 领域 Mixin
//
// 从 FFIBridge 中抽取的 Canvas API。部分方法通过 C ABI 调用 Rust，
// 部分（无对应 handler）为 stub 返回降级结果。
//
// 拆分理由:
// - Canvas 操作与 FFI 核心职责（C ABI 分发）无关，属领域 API
// - 16 个方法（6 个 FFI + 10 个 stub），约 60 行，污染 FFIBridge 主类
// - 独立后便于未来实现 Canvas 持久化或移除未实现的 stub

import 'dart:convert';

/// Canvas API Mixin
///
/// 宿主类需实现 [ffiCheckAvailable] 和 [ffiDispatch] 提供 C ABI 访问能力。
/// 无对应 C ABI handler 的方法返回降级结果（空 JSON/空操作），
/// 调用方应检测返回值而非依赖 try-catch。
mixin CanvasMixin {
  /// 宿主类提供：检查 FFI 是否可用，不可用则抛 StateError
  void ffiCheckAvailable();

  /// 宿主类提供：通过 C ABI 调用 Rust dispatch，返回解析后的 JSON 数据
  dynamic ffiDispatch(String event, [Map<String, dynamic>? payload]);

  // ── 有 C ABI handler 的方法 ──────────────────────────────

  Future<void> canvasAddNode({required String canvasId, required String nodeJson}) async {
    ffiCheckAvailable();
    ffiDispatch('CanvasEvent.AddNode', {
      'canvas_id': canvasId,
      'node': jsonDecode(nodeJson),
    });
  }

  Future<void> canvasRemoveNode({required String canvasId, required String nodeId}) async {
    ffiCheckAvailable();
    ffiDispatch('CanvasEvent.RemoveNode', {
      'canvas_id': canvasId,
      'node_id': nodeId,
    });
  }

  Future<void> canvasAutoLayout({required String canvasId, required String layoutType}) async {
    ffiCheckAvailable();
    ffiDispatch('CanvasEvent.AutoLayout', {
      'canvas_id': canvasId,
      'layout_type': layoutType,
    });
  }

  Future<void> canvasAddEdge({required String canvasId, required String edgeJson}) async {
    ffiCheckAvailable();
    ffiDispatch('CanvasEvent.AddEdge', {
      'canvas_id': canvasId,
      'edge': jsonDecode(edgeJson),
    });
  }

  Future<void> canvasSaveCanvas({required String canvasId, required String path}) async {
    ffiCheckAvailable();
    ffiDispatch('CanvasEvent.SaveJson', {
      'canvas_id': canvasId,
      'path': path,
    });
  }

  Future<String> canvasLoadCanvas({required String path}) async {
    ffiCheckAvailable();
    final result = ffiDispatch('CanvasEvent.LoadJson', {'path': path});
    return jsonEncode(result);
  }

  // ── 无 C ABI handler 的 stub 方法（返回降级结果）──────────
  // P0 修复: 原 throw UnimplementedError 会导致调用方崩溃，改为返回降级结果

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
