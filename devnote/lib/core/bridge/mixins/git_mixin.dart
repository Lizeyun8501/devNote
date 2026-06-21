// P1 修复 (P1-2): FFIBridge God Class 拆分 —— Git 领域 Mixin
//
// 从 FFIBridge 中抽取的 Git API。所有方法均为 stub（Rust 端无对应 C ABI handler），
// 调用方应检测返回值并使用 Dart 端 process_runner 兜底实现。
//
// 拆分理由:
// - 7 个方法全部为占位 stub，污染 FFIBridge 主类
// - Git 操作与 FFI 核心职责（C ABI 分发）无关
// - 独立后便于未来实现真实 Git 集成或彻底移除

/// Git API Mixin —— 全部为 stub，无对应 C ABI handler
///
/// 调用方应检测返回 JSON 中的 `success` 字段，失败时走 Dart 端兜底实现。
mixin GitMixin {
  Future<String> gitInit({required String repoPath}) async =>
      '{"success":false,"error":"git FFI not available"}';

  Future<String> gitStatus({required String repoPath}) async =>
      '{"success":false,"error":"git FFI not available"}';

  Future<String> gitCommit({
    required String repoPath,
    required String message,
  }) async =>
      '{"success":false,"error":"git FFI not available"}';

  Future<String> gitLog({required String repoPath, required int limit}) async =>
      '{"commits":[]}';

  Future<String> gitBranch({required String repoPath}) async =>
      '{"branches":[]}';

  Future<String> gitCheckout({
    required String repoPath,
    required String branch,
  }) async =>
      '{"success":false,"error":"git FFI not available"}';

  Future<String> gitDiff({required String repoPath}) async => '{"diff":""}';
}
