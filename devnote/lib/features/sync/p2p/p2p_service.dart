import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
  P2PService._();

  static final P2PService _instance = P2PService._();
  static P2PService get instance => _instance;

  static const String _keyEnabled = 'p2p_enabled';
  static const String _keySignalingServer = 'p2p_signaling_server';
  static const String _keyBootstrapPeers = 'p2p_bootstrap_peers';

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

  Future<void> startNode() async {
    if (_state.status == P2PNodeStatus.running) return;

    _state = _state.copyWith(status: P2PNodeStatus.starting);
    _notifyListeners();

    try {
      await Future.delayed(const Duration(milliseconds: 500));

      final localPeerId = _generatePeerId();

      _state = _state.copyWith(
        status: P2PNodeStatus.running,
        localPeerId: localPeerId,
        lastError: null,
      );

      _startDiscoveryTimer();
    } catch (e) {
      _state = _state.copyWith(
        status: P2PNodeStatus.error,
        lastError: e.toString(),
      );
    }

    _notifyListeners();
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

  Future<List<P2PPeerInfo>> discoverPeers() async {
    if (_state.status != P2PNodeStatus.running) return [];

    await Future.delayed(const Duration(milliseconds: 300));

    return _state.peers;
  }

  Future<void> connectPeer(String peerId) async {
    if (_state.status != P2PNodeStatus.running) return;

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

  Future<bool> sendData(String peerId, Uint8List data) async {
    if (_state.status != P2PNodeStatus.running) return false;

    final peer = _state.peers.where((p) => p.peerId == peerId).firstOrNull;
    if (peer == null || !peer.isOnline) return false;

    await Future.delayed(const Duration(milliseconds: 100));
    return true;
  }

  Future<bool> broadcast(String topic, Uint8List data) async {
    if (_state.status != P2PNodeStatus.running) return false;

    await Future.delayed(const Duration(milliseconds: 100));
    return true;
  }

  Future<void> syncWithPeer(String peerId) async {
    if (_state.status != P2PNodeStatus.running) return;

    final peer = _state.peers.where((p) => p.peerId == peerId).firstOrNull;
    if (peer == null) return;

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
