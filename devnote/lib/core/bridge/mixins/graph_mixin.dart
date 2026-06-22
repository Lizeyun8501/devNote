// P2 修复 (P2-4): FFIBridge God Class 进一步拆分 —— Graph 领域 Mixin
//
// 从 FFIBridge 中抽取的知识图谱 API。部分方法通过 C ABI 调用 Rust，
// 部分（无对应 handler）为 stub 返回降级结果。
//
// 拆分理由:
// - Graph 操作与 FFI 核心职责（C ABI 分发）无关，属领域 API
// - 9 个方法（2 个 FFI + 7 个 stub），约 25 行
// - 独立后便于未来实现真实图谱查询或对接 petgraph

import 'dart:convert';

/// Graph API Mixin
///
/// 宿主类需实现 [ffiCheckAvailable] 和 [ffiDispatch] 提供 C ABI 访问能力。
/// 无对应 C ABI handler 的方法返回空 JSON，调用方应处理空结果。
mixin GraphMixin {
  /// 宿主类提供：检查 FFI 是否可用，不可用则抛 StateError
  void ffiCheckAvailable();

  /// 宿主类提供：通过 C ABI 调用 Rust dispatch，返回解析后的 JSON 数据
  dynamic ffiDispatch(String event, [Map<String, dynamic>? payload]);

  // ── 有 C ABI handler 的方法 ──────────────────────────────

  Future<String> calculateCentrality() async {
    ffiCheckAvailable();
    return jsonEncode(ffiDispatch('GraphEvent.CalculateCentrality'));
  }

  Future<String> detectClusters() async {
    ffiCheckAvailable();
    return jsonEncode(ffiDispatch('GraphEvent.DetectClusters'));
  }

  // ── 无 C ABI handler 的 stub 方法（返回空 JSON）──────────
  // P0 修复: 返回空 JSON 而非抛异常，调用方应处理空结果

  Future<String> getGraph() async => '{"nodes":[],"edges":[]}';
  Future<String> getNodeDetails({required String nodeId}) async => '{}';
  Future<String> getRelatedNodes({required String nodeId}) async => '{"nodes":[]}';
  Future<String> searchNodes({required String query}) async => '{"nodes":[]}';
  Future<String> getGraphStats() async => '{"node_count":0,"edge_count":0}';
  Future<String> getShortestPath({required String fromId, required String toId}) async => '{"path":[]}';
  Future<String> getNeighbors({required String nodeId, required int depth}) async => '{"nodes":[]}';
}
