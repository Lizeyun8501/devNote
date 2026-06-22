// P1 修复 (P1-2): FFIBridge God Class 拆分 —— Knowledge 领域 Mixin
//
// 从 FFIBridge 中抽取的 Knowledge API。所有方法均为 stub（Rust 端无对应 C ABI handler），
// 调用方应使用 Dart 端 sqflite 兜底实现。
//
// 拆分理由:
// - 3 个方法全部为占位 stub
// - Knowledge 服务实际走 sqflite 持久化，与 FFI 无关
// - 独立后消除 FFIBridge 的虚假职责

/// Knowledge API Mixin —— 全部为 stub，KnowledgeService 应使用 sqflite 兜底
///
/// 返回空 JSON 结构，调用方检测空数据后走 Dart 端 sqflite 查询。
mixin KnowledgeMixin {
  Future<String> getKnowledgeMap({required String noteId}) async =>
      '{"nodes":[],"edges":[]}';

  Future<String> getLearningStats({required String noteId}) async =>
      '{"total_notes":0,"reviewed_notes":0,"streak_days":0}';

  Future<String> getDashboard() async => '{"stats":{},"recent_notes":[]}';
}
