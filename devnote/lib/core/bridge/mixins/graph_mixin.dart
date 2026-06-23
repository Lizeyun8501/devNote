// Graph API Mixin —— 基于 flutter_rust_bridge v2
//
// 从 FFIBridge 中抽取的知识图谱 API。通过 FRB 生成的类型安全绑定调用 Rust。
//
// 拆分理由:
// - Graph 操作属领域 API，独立后便于维护
// - 9 个方法（2 个 FRB + 7 个 stub），约 25 行
// - 独立后便于未来实现真实图谱查询或对接 petgraph

import 'package:devnote/src/rust/library.dart' as rust;

/// Graph API Mixin
///
/// 宿主类需实现 [ffiCheckAvailable] 提供 FFI 可用性检查。
/// 无对应 FRB 函数的方法返回空 JSON，调用方应处理空结果。
mixin GraphMixin {
  /// 宿主类提供：检查 FFI 是否可用，不可用则抛 StateError
  void ffiCheckAvailable();

  // ── 有 FRB 绑定的方法 ───────────────────────────────────

  Future<String> calculateCentrality() async {
    ffiCheckAvailable();
    return rust.calculateCentrality();
  }

  Future<String> detectClusters() async {
    ffiCheckAvailable();
    return rust.detectClusters();
  }

  // ── 无 FRB 绑定的 stub 方法（返回空 JSON）──────────

  Future<String> getGraph() async => '{"nodes":[],"edges":[]}';
  Future<String> getNodeDetails({required String nodeId}) async => '{}';
  Future<String> getRelatedNodes({required String nodeId}) async => '{"nodes":[]}';
  Future<String> searchNodes({required String query}) async => '{"nodes":[]}';
  Future<String> getGraphStats() async => '{"node_count":0,"edge_count":0}';
  Future<String> getShortestPath({required String fromId, required String toId}) async => '{"path":[]}';
  Future<String> getNeighbors({required String nodeId, required int depth}) async => '{"nodes":[]}';
}
