// P1 修复 (P1-2): FFIBridge God Class 拆分 —— P2P 领域 Mixin
//
// 从 FFIBridge 中抽取的 P2P API。所有方法均为 stub（P2P 在 Dart 端独立实现），
// 调用方应检测返回值并使用 Dart 兜底实现。
//
// 拆分理由:
// - 6 个方法全部为占位 stub，P2P 实际由 Dart 端 webrtc/dart-libp2p 实现
// - 与 FFI 核心 C ABI 分发职责无关
// - 独立后消除 FFIBridge 的虚假职责

/// P2P API Mixin —— 全部为 stub，P2P 在 Dart 端独立实现
///
/// 调用方应检测返回 JSON 中的 `running`/`peers` 字段，空结果时走 Dart 兜底。
mixin P2PMixin {
  Future<void> p2pStart({required String peerId}) async {}

  Future<void> p2pStop() async {}

  Future<String> p2pGetPeers() async => '{"peers":[]}';

  Future<void> p2pConnectPeer({
    required String peerId,
    required String multiaddr,
  }) async {}

  Future<void> p2pDisconnectPeer({required String peerId}) async {}

  Future<String> p2pGetStatus() async => '{"running":false,"peer_count":0}';
}
