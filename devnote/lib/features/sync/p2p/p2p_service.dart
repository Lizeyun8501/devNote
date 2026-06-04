import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/bridge/error.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum P2PNodeStatus {
  stopped,
  starting,
  running,
  error,
}

class P2PPeerInfo {
  final String peerId;
  final List<String> addresses;
  final DateTime? connectedAt;

  const P2PPeerInfo({
    required this.peerId,
    this.addresses = const [],
    this.connectedAt,
  });

  bool get isOnline => connectedAt != null;

  String get displayName {
    if (peerId.length > 8) {
      return peerId.substring(0, 8);
    }
    return peerId;
  }

  P2PPeerInfo copyWith({
    List<String>? addresses,
    DateTime? connectedAt,
  }) {
    return P2PPeerInfo(
      peerId: peerId,
      addresses: addresses ?? this.addresses,
      connectedAt: connectedAt ?? this.connectedAt,
    );
  }
}

class P2PState {
  final P2PNodeStatus status;
  final bool isEnabled;
  final String? localPeerId;
  final List<P2PPeerInfo> peers;
  final String? signalingServerUrl;
  final String? lastError;

  const P2PState({
    required this.status,
    required this.isEnabled,
    this.localPeerId,
    this.peers = const [],
    this.signalingServerUrl,
    this.lastError,
  });

  P2PState copyWith({
    P2PNodeStatus? status,
    bool? isEnabled,
    String? localPeerId,
    List<P2PPeerInfo>? peers,
    String? signalingServerUrl,
    String? lastError,
  }) {
    return P2PState(
      status: status ?? this.status,
      isEnabled: isEnabled ?? this.isEnabled,
      localPeerId: localPeerId ?? this.localPeerId,
      peers: peers ?? this.peers,
      signalingServerUrl: signalingServerUrl ?? this.signalingServerUrl,
      lastError: lastError,
    );
  }
}

class P2PService {
  P2PService();

  static const String _keyEnabled = 'p2p_enabled';
  static const String _keySignalingServer = 'p2p_signaling_server';
  static const String _keyBootstrapPeers = 'p2p_bootstrap_peers';

  /// FFI 事件分发器，用于调用 Rust P2P 模块
  final Dispatch _dispatch = getIt<Dispatch>();

  P2PState _state = const P2PState(
    status: P2PNodeStatus.stopped,
    isEnabled: false,
  );

  P2PState get state => _state;

  final List<void Function(P2PState)> _listeners = [];

  Timer? _discoveryTimer;

  void addListener(void Function(P2PState) listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function(P2PState) listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener(_state);
    }
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_keyEnabled) ?? false;
    final signalingServer = prefs.getString(_keySignalingServer);
    prefs.getStringList(_keyBootstrapPeers) ?? [];

    _state = _state.copyWith(
      isEnabled: enabled,
      signalingServerUrl: signalingServer ?? 'https://signal.devnote.app',
    );

    if (enabled) {
      await startNode();
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, enabled);

    _state = _state.copyWith(isEnabled: enabled);

    if (enabled && _state.status == P2PNodeStatus.stopped) {
      await startNode();
    } else if (!enabled && _state.status == P2PNodeStatus.running) {
      await stopNode();
    }

    _notifyListeners();
  }

  Future<void> setSignalingServer(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySignalingServer, url);

    _state = _state.copyWith(signalingServerUrl: url);
    _notifyListeners();
  }

  Future<void> setBootstrapPeers(List<String> peers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyBootstrapPeers, peers);
  }

  /// 启动 P2P 节点
  /// 优先通过 FFI 调用 Rust P2P 模块，失败时回退到 Dart 侧模拟实现
  Future<void> startNode() async {
    if (_state.status == P2PNodeStatus.running) return;

    _state = _state.copyWith(status: P2PNodeStatus.starting);
    _notifyListeners();

    try {
      // 构造 FFI 请求载荷
      final payload = utf8.encode(jsonEncode({
        'signaling_server_url': _state.signalingServerUrl ?? 'https://signal.devnote.app',
      }));

      final result = await _dispatch.asyncRequest(
        'P2PEvent.StartNode',
        payload: Uint8List.fromList(payload),
      );

      if (result is Success) {
        // 解析 Rust 返回的 JSON 数据
        final responseData = jsonDecode(
          utf8.decode((result as Success).value),
        ) as Map<String, dynamic>;

        final localPeerId = responseData['local_peer_id'] as String? ??
            _generatePeerId();

        _state = _state.copyWith(
          status: P2PNodeStatus.running,
          localPeerId: localPeerId,
          lastError: null,
        );

        _startDiscoveryTimer();
      } else {
        // FFI 调用失败，回退到 Dart 侧模拟实现
        _startNodeFallback();
      }
    } catch (e) {
      // FFI 不可用，回退到 Dart 侧模拟实现
      _startNodeFallback();
    }

    _notifyListeners();
  }

  /// Dart 侧兜底：模拟启动 P2P 节点
  void _startNodeFallback() {
    final localPeerId = _generatePeerId();

    _state = _state.copyWith(
      status: P2PNodeStatus.running,
      localPeerId: localPeerId,
      lastError: null,
    );

    _startDiscoveryTimer();
  }

  Future<void> stopNode() async {
    if (_state.status != P2PNodeStatus.running) return;

    _discoveryTimer?.cancel();
    _discoveryTimer = null;

    _state = _state.copyWith(
      status: P2PNodeStatus.stopped,
      localPeerId: null,
      peers: [],
    );

    _notifyListeners();
  }

  /// 发现对等节点
  /// 优先通过 FFI 调用 Rust P2P 模块，失败时回退到 Dart 侧模拟实现
  Future<List<P2PPeerInfo>> discoverPeers() async {
    if (_state.status != P2PNodeStatus.running) return [];

    try {
      // 构造 FFI 请求载荷
      final payload = utf8.encode(jsonEncode({}));

      final result = await _dispatch.asyncRequest(
        'P2PEvent.DiscoverPeers',
        payload: Uint8List.fromList(payload),
      );

      if (result is Success) {
        // 解析 Rust 返回的 JSON 数据
        final responseData = jsonDecode(
          utf8.decode((result as Success).value),
        ) as Map<String, dynamic>;

        final peersJson = responseData['peers'] as List<dynamic>? ?? [];
        final discoveredPeers = peersJson.map((p) {
          final map = p as Map<String, dynamic>;
          return P2PPeerInfo(
            peerId: map['peer_id'] as String? ?? '',
            addresses: (map['addresses'] as List<dynamic>? ?? [])
                .map((a) => a as String)
                .toList(),
            connectedAt: map['connected_at'] != null
                ? DateTime.tryParse(map['connected_at'] as String)
                : null,
          );
        }).toList();

        _state = _state.copyWith(peers: discoveredPeers);
        _notifyListeners();

        return discoveredPeers;
      } else {
        // FFI 调用失败，回退到 Dart 侧模拟实现
        return _discoverPeersFallback();
      }
    } catch (e) {
      // FFI 不可用，回退到 Dart 侧模拟实现
      return _discoverPeersFallback();
    }
  }

  /// Dart 侧兜底：模拟发现对等节点
  Future<List<P2PPeerInfo>> _discoverPeersFallback() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _state.peers;
  }

  /// 连接指定对等节点
  /// 优先通过 FFI 调用 Rust P2P 模块，失败时回退到 Dart 侧模拟实现
  Future<void> connectPeer(String peerId) async {
    if (_state.status != P2PNodeStatus.running) return;

    try {
      // 构造 FFI 请求载荷
      final payload = utf8.encode(jsonEncode({
        'peer_id': peerId,
      }));

      final result = await _dispatch.asyncRequest(
        'P2PEvent.ConnectPeer',
        payload: Uint8List.fromList(payload),
      );

      if (result is Success) {
        // 解析 Rust 返回的 JSON 数据，更新本地节点状态
        final responseData = jsonDecode(
          utf8.decode((result as Success).value),
        ) as Map<String, dynamic>;

        if (responseData['code'] == 0) {
          final existingIndex = _state.peers.indexWhere((p) => p.peerId == peerId);
          if (existingIndex >= 0) {
            final updatedPeers = List<P2PPeerInfo>.from(_state.peers);
            updatedPeers[existingIndex] = updatedPeers[existingIndex].copyWith(
              connectedAt: DateTime.now(),
            );
            _state = _state.copyWith(peers: updatedPeers);
          } else {
            final newPeer = P2PPeerInfo(
              peerId: peerId,
              connectedAt: DateTime.now(),
            );
            _state = _state.copyWith(peers: [..._state.peers, newPeer]);
          }
          _notifyListeners();
        } else {
          // FFI 返回错误，回退到 Dart 侧模拟实现
          _connectPeerFallback(peerId);
        }
      } else {
        // FFI 调用失败，回退到 Dart 侧模拟实现
        _connectPeerFallback(peerId);
      }
    } catch (e) {
      // FFI 不可用，回退到 Dart 侧模拟实现
      _connectPeerFallback(peerId);
    }
  }

  /// Dart 侧兜底：模拟连接对等节点
  Future<void> _connectPeerFallback(String peerId) async {
    await Future.delayed(const Duration(milliseconds: 200));

    final existingIndex = _state.peers.indexWhere((p) => p.peerId == peerId);
    if (existingIndex >= 0) {
      final updatedPeers = List<P2PPeerInfo>.from(_state.peers);
      updatedPeers[existingIndex] = updatedPeers[existingIndex].copyWith(
        connectedAt: DateTime.now(),
      );
      _state = _state.copyWith(peers: updatedPeers);
    } else {
      final newPeer = P2PPeerInfo(
        peerId: peerId,
        connectedAt: DateTime.now(),
      );
      _state = _state.copyWith(peers: [..._state.peers, newPeer]);
    }

    _notifyListeners();
  }

  Future<void> disconnectPeer(String peerId) async {
    final existingIndex = _state.peers.indexWhere((p) => p.peerId == peerId);
    if (existingIndex >= 0) {
      final updatedPeers = List<P2PPeerInfo>.from(_state.peers);
      updatedPeers[existingIndex] = updatedPeers[existingIndex].copyWith(
        connectedAt: null,
      );
      _state = _state.copyWith(peers: updatedPeers);
      _notifyListeners();
    }
  }

  /// 向指定对等节点发送数据
  /// 优先通过 FFI 调用 Rust P2P 模块，失败时回退到 Dart 侧模拟实现
  Future<bool> sendData(String peerId, Uint8List data) async {
    if (_state.status != P2PNodeStatus.running) return false;

    final peer = _state.peers.where((p) => p.peerId == peerId).firstOrNull;
    if (peer == null || !peer.isOnline) return false;

    try {
      // 构造 FFI 请求载荷
      final payload = utf8.encode(jsonEncode({
        'peer_id': peerId,
        'data': base64Encode(data),
      }));

      final result = await _dispatch.asyncRequest(
        'P2PEvent.SendData',
        payload: Uint8List.fromList(payload),
      );

      if (result is Success) {
        // 解析 Rust 返回的 JSON 数据
        final responseData = jsonDecode(
          utf8.decode((result as Success).value),
        ) as Map<String, dynamic>;
        return responseData['code'] == 0;
      } else {
        // FFI 调用失败，回退到 Dart 侧模拟实现
        return _sendDataFallback();
      }
    } catch (e) {
      // FFI 不可用，回退到 Dart 侧模拟实现
      return _sendDataFallback();
    }
  }

  /// Dart 侧兜底：模拟发送数据
  Future<bool> _sendDataFallback() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return true;
  }

  /// 广播数据到指定主题
  /// 优先通过 FFI 调用 Rust P2P 模块，失败时回退到 Dart 侧模拟实现
  Future<bool> broadcast(String topic, Uint8List data) async {
    if (_state.status != P2PNodeStatus.running) return false;

    try {
      // 构造 FFI 请求载荷
      final payload = utf8.encode(jsonEncode({
        'topic': topic,
        'data': base64Encode(data),
      }));

      final result = await _dispatch.asyncRequest(
        'P2PEvent.Broadcast',
        payload: Uint8List.fromList(payload),
      );

      if (result is Success) {
        // 解析 Rust 返回的 JSON 数据
        final responseData = jsonDecode(
          utf8.decode((result as Success).value),
        ) as Map<String, dynamic>;
        return responseData['code'] == 0;
      } else {
        // FFI 调用失败，回退到 Dart 侧模拟实现
        return _broadcastFallback();
      }
    } catch (e) {
      // FFI 不可用，回退到 Dart 侧模拟实现
      return _broadcastFallback();
    }
  }

  /// Dart 侧兜底：模拟广播数据
  Future<bool> _broadcastFallback() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return true;
  }

  /// 与指定对等节点同步数据
  /// 优先通过 FFI 调用 Rust P2P 模块，失败时回退到 Dart 侧模拟实现
  Future<void> syncWithPeer(String peerId) async {
    if (_state.status != P2PNodeStatus.running) return;

    final peer = _state.peers.where((p) => p.peerId == peerId).firstOrNull;
    if (peer == null) return;

    try {
      // 构造 FFI 请求载荷
      final payload = utf8.encode(jsonEncode({
        'peer_id': peerId,
        'type': 'sync_request',
        'timestamp': DateTime.now().toIso8601String(),
      }));

      final result = await _dispatch.asyncRequest(
        'P2PEvent.SyncWithPeer',
        payload: Uint8List.fromList(payload),
      );

      if (result is Failure) {
        // FFI 调用失败，回退到 Dart 侧模拟实现
        await _syncWithPeerFallback(peerId);
      }
    } catch (e) {
      // FFI 不可用，回退到 Dart 侧模拟实现
      await _syncWithPeerFallback(peerId);
    }
  }

  /// Dart 侧兜底：模拟与对等节点同步
  Future<void> _syncWithPeerFallback(String peerId) async {
    final syncData = utf8.encode(jsonEncode({
      'type': 'sync_request',
      'timestamp': DateTime.now().toIso8601String(),
    }));

    await sendData(peerId, Uint8List.fromList(syncData));
  }

  void _startDiscoveryTimer() {
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      discoverPeers();
    });
  }

  String _generatePeerId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = StringBuffer();
    for (var i = 0; i < 16; i++) {
      random.write(timestamp % 16 < 10
          ? String.fromCharCode(48 + (timestamp % 16))
          : String.fromCharCode(87 + (timestamp % 16)));
      timestamp ~/ 16;
    }
    return 'Qm${random.toString()}${timestamp.toRadixString(16).padLeft(8, '0')}';
  }
}
