/// LibP2PAdapter - 基于 WebRTC 的 P2P 设备发现与连接适配器
///
/// 借鉴开源项目:
/// 1. webrtc-rs: https://github.com/webrtc-rs/webrtc
///    借鉴内容: WebRTC 连接建立流程（ICE/STUN/TURN 协商、SDP 交换、DTLS 加密）
///
/// 2. libp2p: https://github.com/libp2p/libp2p
///    借鉴内容: DHT 分布式哈希表设备发现、PeerID 标识体系、传输协议抽象层
///
/// 设计原理:
/// libp2p 是一个模块化的 P2P 网络栈，支持多种传输层（TCP、WebRTC、WebTransport）。
/// webrtc-rs 是 Rust 实现的 WebRTC 协议栈，提供 NAT 穿透和点对点通信能力。
///
/// 本适配器在 Dart 侧实现 libp2p 的核心概念抽象:
/// - PeerID: 使用 PeerID 唯一标识每个设备节点
/// - ICE 协商: 通过 STUN/TURN 服务器实现 NAT 穿透
/// - 信令交换: 通过信令服务器交换 SDP（Session Description Protocol）
/// - 设备发现: 支持 mDNS 局域网发现 + 信令服务器广域网发现
///
/// 架构映射:
/// ```
/// libp2p 概念        → 本实现
/// ─────────────────────────────
/// PeerID            → PeerId 类（Base58 编码）
/// Transport          → WebRTCTransport（ICE 连接）
/// DHT               → 信令服务器 + 本地 Peer 缓存
/// Swarm             → LibP2PAdapter（统一管理连接）
/// Stream            → DataChannel（RTCDataChannel）
/// ```
///
/// 注意: 由于 Dart WebRTC 支持的平台限制，本实现提供:
/// - 完整的接口定义和连接状态管理
/// - 信令协议抽象（可通过不同后端实现）
/// - FFI 桥接点（可调用 rust-core 的 devnote-p2p 模块）

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// PeerID —— P2P 网络中节点的唯一标识符
///
/// 借鉴 libp2p 的 PeerId 设计:
/// https://github.com/libp2p/specs/blob/master/peer-ids/peer-ids.md
///
/// libp2p PeerID 通常由公钥的哈希值派生（SHA-256 → Base58 编码）。
/// 此处简化为随机生成的字符串标识符，格式类似 libp2p 的 Base58 编码 ID。
class PeerId {
  final String id;

  const PeerId(this.id);

  /// 生成新的 PeerID —— 借鉴 libp2p 的随机 ID 生成策略
  ///
  /// 格式: "Qm" + 46 个 Base58 字符 = 48 字符（与 IPFS/libp2p ID 风格一致）
  factory PeerId.generate() {
    const base58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    final random = DateTime.now().microsecondsSinceEpoch;
    final buffer = StringBuffer('Qm');
    for (int i = 0; i < 46; i++) {
      final idx = (random * (i + 1) * 31 + i * 17) % base58.length;
      buffer.write(base58[idx.abs() % base58.length]);
    }
    return PeerId(buffer.toString());
  }

  /// 从字符串解析 PeerID
  factory PeerId.parse(String id) {
    if (id.isEmpty) throw FormatException('PeerID 不能为空');
    return PeerId(id);
  }

  /// 获取 PeerID 的简短显示名（前 8 个字符）
  String get shortId => id.length > 8 ? id.substring(0, 8) : id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PeerId && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PeerId($shortId...)';
}

/// ICE 候选信息 —— 用于 WebRTC NAT 穿透
///
/// 借鉴 webrtc-rs 的 ICE Candidate 结构:
/// https://github.com/webrtc-rs/webrtc/blob/master/webrtcice/src/candidate/candidate.go
///
/// ICE（Interactive Connectivity Establishment）协议通过尝试多种候选地址
/// 来建立 P2P 连接，包括:
/// - host: 本地网络地址（同一局域网内直连）
/// - srflx: STUN 反射地址（通过 STUN 服务器获取的公网地址）
/// - relay: TURN 中继地址（通过 TURN 服务器中转，当直连失败时使用）
class IceCandidate {
  /// 候选地址
  final String address;

  /// 候选类型: host, srflx, relay
  final String type;

  /// 候选优先级（webrtc-rs 的 priority 计算方式）
  final int priority;

  const IceCandidate({
    required this.address,
    required this.type,
    required this.priority,
  });

  /// 序列化为 JSON —— 用于信令传输
  Map<String, dynamic> toJson() => {
        'address': address,
        'type': type,
        'priority': priority,
      };

  factory IceCandidate.fromJson(Map<String, dynamic> json) => IceCandidate(
        address: json['address'] as String,
        type: json['type'] as String,
        priority: json['priority'] as int,
      );
}

/// SDP Offer/Answer —— WebRTC 会话描述协议
///
/// 借鉴 webrtc-rs 的 SessionDescription:
/// https://github.com/webrtc-rs/webrtc/blob/master/webrtc/src/api/session_description.rs
///
/// SDP（Session Description Protocol）描述了媒体流和传输配置:
/// - m= 行: 媒体描述（本实现中用于数据通道）
/// - c= 行: 连接信息
/// - a= 行: 属性（ICE 候选、DTLS 指纹等）
class SessionDescription {
  /// SDP 类型: offer 或 answer
  final String type;

  /// SDP 内容
  final String sdp;

  const SessionDescription({
    required this.type,
    required this.sdp,
  });

  Map<String, dynamic> toJson() => {'type': type, 'sdp': sdp};

  factory SessionDescription.fromJson(Map<String, dynamic> json) =>
      SessionDescription(
        type: json['type'] as String,
        sdp: json['sdp'] as String,
      );
}

/// 连接状态 —— 借鉴 webrtc-rs 的 ICE 连接状态机
///
/// 来源: https://github.com/webrtc-rs/webrtc/blob/master/webrtcice/src/agent/agent.go
enum LibP2PConnectionState {
  /// 未连接
  disconnected,

  /// 正在连接（ICE 协商中）
  connecting,

  /// 已连接（P2P 通道建立）
  connected,

  /// 连接断开
  closed,

  /// 连接失败
  failed,
}

/// 对等节点信息 —— 借鉴 libp2p 的 PeerInfo
///
/// 来源: https://github.com/libp2p/go-libp2p/core/peer/peer.go
class LibP2PPeerInfo {
  final PeerId peerId;
  final List<String> addresses;
  final LibP2PConnectionState state;
  final DateTime? lastSeenAt;

  const LibP2PPeerInfo({
    required this.peerId,
    this.addresses = const [],
    this.state = LibP2PConnectionState.disconnected,
    this.lastSeenAt,
  });

  bool get isOnline => state == LibP2PConnectionState.connected;

  String get displayName => peerId.shortId;

  LibP2PPeerInfo copyWith({
    List<String>? addresses,
    LibP2PConnectionState? state,
    DateTime? lastSeenAt,
  }) {
    return LibP2PPeerInfo(
      peerId: peerId,
      addresses: addresses ?? this.addresses,
      state: state ?? this.state,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}

/// STUN/TURN 服务器配置 —— 借鉴 webrtc-rs 的 ICE 服务器配置
///
/// 来源: https://github.com/webrtc-rs/webrtc/blob/master/webrtcice/src/setting_engine.rs
///
/// STUN 服务器: 用于 NAT 穿透，获取本设备公网 IP 和端口
/// TURN 服务器: 当 NAT 穿透失败时，作为中继服务器转发数据
class IceServerConfig {
  /// 服务器 URL，例如: 'stun:stun.l.google.com:19302'
  final String url;

  /// 用户名（TURN 服务器需要）
  final String? username;

  /// 凭据（TURN 服务器需要）
  final String? credential;

  const IceServerConfig({
    required this.url,
    this.username,
    this.credential,
  });

  /// 默认的 Google STUN 服务器 —— 免费公开可用
  static const googleStun = IceServerConfig(
    url: 'stun:stun.l.google.com:19302',
  );

  /// 默认 STUN 服务器列表 —— 借鉴 webrtc-rs 推荐的公共 STUN 服务器
  static const defaultServers = [
    googleStun,
    IceServerConfig(url: 'stun:stun1.l.google.com:19302'),
    IceServerConfig(url: 'stun:stun.cloudflare.com:3478'),
  ];
}

/// LibP2PAdapter —— 基于 WebRTC 的 P2P 连接适配器
///
/// 核心设计借鉴:
/// 1. webrtc-rs 的 NAT 穿透实现（ICE/STUN/TURN 协商流程）
///    来源: https://github.com/webrtc-rs/webrtc
///
/// 2. libp2p 的 DHT 设备发现和连接管理
///    来源: https://github.com/libp2p/libp2p
///
/// 连接建立流程（借鉴 webrtc-rs 的 ICE 协商）:
/// ```
/// 发起端                          接收端
///   |                               |
///   |-- 1. createOffer() ---------->|  (通过信令服务器)
///   |                               |
///   |<-- 2. createAnswer() ---------|  (通过信令服务器)
///   |                               |
///   |-- 3. ICE Candidate 交换 -------->|  (Trickle ICE)
///   |                               |
///   |<-- 4. ICE Candidate 交换 --------|  (Trickle ICE)
///   |                               |
///   |---- 5. DTLS 握手 + 连接建立 ------->|  (P2P 直连)
///   |                               |
/// ```
///
/// 设备发现流程（借鉴 libp2p 的 DHT/Kademlia）:
/// 1. 节点启动后向信令服务器注册（类似 libp2p 的 Identify 协议）
/// 2. 定期查询信令服务器获取已知节点列表（类似 DHT 查询）
/// 3. 对发现的节点尝试建立连接
/// 4. 维护本地 Peer 缓存（TTL 过期机制）
class LibP2PAdapter {
  /// 本节点的 PeerID —— 借鉴 libp2p 的本地 Peer 标识
  PeerId? _localPeerId;

  PeerId? get localPeerId => _localPeerId;

  /// 当前连接状态 —— 借鉴 webrtc-rs 的 ICE 连接状态机
  LibP2PConnectionState _state = LibP2PConnectionState.disconnected;

  LibP2PConnectionState get state => _state;

  /// ICE 服务器配置 —— 用于 NAT 穿透
  /// 借鉴 webrtc-rs 的 SettingEngine 配置
  final List<IceServerConfig> _iceServers;

  /// 信令服务器 URL —— 用于 SDP 交换和 Peer 发现
  /// 借鉴 libp2p 的 Rendezvous 协议概念
  final String _signalingUrl;

  /// 已知的对等节点列表 —— 借鉴 libp2p 的 Peerstore
  final Map<String, LibP2PPeerInfo> _peers = {};

  /// 活跃连接 —— 已建立 P2P 通道的 PeerID 集合
  final Set<String> _activeConnections = {};

  /// 信令 WebSocket 连接
  StreamSubscription? _signalingSubscription;

  /// 状态监听器
  final List<void Function(LibP2PConnectionState)> _stateListeners = [];

  /// 数据接收回调
  final List<void Function(PeerId, Uint8List)> _dataListeners = [];

  /// 发现定时器
  Timer? _discoveryTimer;

  /// Peer 缓存过期时间 —— 借鉴 libp2p 的 Peerstore TTL 机制
  static const Duration _peerCacheTtl = Duration(minutes: 5);

  LibP2PAdapter({
    List<IceServerConfig>? iceServers,
    String? signalingUrl,
  })  : _iceServers = iceServers ?? IceServerConfig.defaultServers,
        _signalingUrl = signalingUrl ?? 'https://signal.devnote.app';

  /// 添加状态监听器
  void addStateListener(void Function(LibP2PConnectionState) listener) {
    _stateListeners.add(listener);
  }

  /// 移除状态监听器
  void removeStateListener(void Function(LibP2PConnectionState) listener) {
    _stateListeners.remove(listener);
  }

  /// 添加数据接收监听器
  void addDataListener(void Function(PeerId, Uint8List) listener) {
    _dataListeners.add(listener);
  }

  /// 移除数据接收监听器
  void removeDataListener(void Function(PeerId, Uint8List) listener) {
    _dataListeners.remove(listener);
  }

  void _notifyStateListeners() {
    for (final listener in _stateListeners) {
      listener(_state);
    }
  }

  // ==================== 初始化 ====================

  /// 初始化 LibP2P 适配器
  ///
  /// 借鉴 libp2p 的 Host 初始化流程:
  /// https://github.com/libp2p/go-libp2p/blob/master/options.go
  ///
  /// 初始化步骤:
  /// 1. 生成 PeerID（如果尚未生成）
  /// 2. 配置 ICE 服务器（STUN/TURN）
  /// 3. 连接信令服务器（类似 libp2p 的 Bootstrap）
  /// 4. 启动周期性设备发现
  Future<void> initialize() async {
    // 生成本地 PeerID —— 借鉴 libp2p 的 ID 生成
    _localPeerId ??= PeerId.generate();

    _state = LibP2PConnectionState.connecting;
    _notifyStateListeners();

    try {
      // 连接信令服务器 —— 类似 libp2p 的 Bootstrap 过程
      await _connectSignalingServer();

      // 向信令服务器注册本节点 —— 类似 libp2p 的 Identify 协议
      await _registerWithSignaling();

      _state = LibP2PConnectionState.connected;
      _notifyStateListeners();

      // 启动周期性设备发现 —— 借鉴 libp2p 的 DHT 定期刷新
      _startDiscoveryTimer();
    } catch (e) {
      _state = LibP2PConnectionState.failed;
      _notifyStateListeners();
      rethrow;
    }
  }

  /// 连接信令服务器
  ///
  /// 信令服务器用于交换 WebRTC 的 SDP 和 ICE 候选信息。
  /// 借鉴 webrtc-rs 的信令交换模式，实际实现可通过 WebSocket。
  Future<void> _connectSignalingServer() async {
    // TODO: 实际实现应通过 WebSocket 连接信令服务器
    // 借鉴 webrtc-rs 的信令协议设计:
    // 1. 建立 WebSocket 连接到信令服务器
    // 2. 监听 incoming messages (SDP offer/answer, ICE candidates)
    // 3. 转发消息到本地 WebRTC PeerConnection
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// 向信令服务器注册本节点
  ///
  /// 借鉴 libp2p 的 Identify 协议:
  /// https://github.com/libp2p/specs/blob/master/identify/README.md
  ///
  /// 注册信息包含:
  /// - PeerID: 节点唯一标识
  /// - Addresses: 可达地址列表
  /// - Protocols: 支持的协议列表
  Future<void> _registerWithSignaling() async {
    // TODO: 发送注册消息到信令服务器
    final registrationPayload = jsonEncode({
      'action': 'register',
      'peer_id': _localPeerId?.id,
      'timestamp': DateTime.now().toIso8601String(),
    });
    // 通过 WebSocket 发送 registrationPayload
  }

  // ==================== 设备发现 ====================

  /// 发现网络中的对等设备
  ///
  /// 借鉴 libp2p 的 DHT (Kademlia) 设备发现机制:
  /// https://github.com/libp2p/specs/blob/master/kad-dht/README.md
  ///
  /// 发现策略:
  /// 1. 通过信令服务器查询已注册的节点（广域网发现）
  /// 2. 通过 mDNS 查询局域网节点（局域网发现）
  /// 3. 合并结果，更新本地 Peer 缓存
  ///
  /// 返回: 对等节点 ID 列表
  Future<List<String>> discoverPeers() async {
    if (_state != LibP2PConnectionState.connected) return [];

    try {
      final discoveredPeers = await _querySignalingServer();

      // 更新本地 Peer 缓存 —— 借鉴 libp2p 的 Peerstore
      for (final peerInfo in discoveredPeers) {
        if (peerInfo.peerId != _localPeerId) {
          _peers[peerInfo.peerId.id] = peerInfo.copyWith(
            lastSeenAt: DateTime.now(),
          );
        }
      }

      // 清理过期的 Peer 缓存 —— 借鉴 libp2p 的 TTL 机制
      _cleanupExpiredPeers();

      return discoveredPeers
          .where((p) => p.peerId != _localPeerId)
          .map((p) => p.peerId.id)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 查询信令服务器获取已知节点列表
  ///
  /// 借鉴 libp2p 的 DHT FindPeers 查询:
  /// https://github.com/libp2p/specs/blob/master/kad-dht/README.md#findpeers
  Future<List<LibP2PPeerInfo>> _querySignalingServer() async {
    // TODO: 实际实现应通过信令服务器查询
    // 查询协议:
    // 1. 发送 'list_peers' 请求到信令服务器
    // 2. 接收节点列表响应
    // 3. 解析为 LibP2PPeerInfo 对象
    await Future.delayed(const Duration(milliseconds: 200));

    // 模拟返回缓存的节点
    return _peers.values.toList();
  }

  /// 清理过期的 Peer 缓存
  ///
  /// 借鉴 libp2p 的 Peerstore 过期策略:
  /// 超过 TTL 时间的 Peer 信息将被移除
  void _cleanupExpiredPeers() {
    final now = DateTime.now();
    _peers.removeWhere((id, info) {
      return info.lastSeenAt != null &&
          now.difference(info.lastSeenAt!) > _peerCacheTtl;
    });
  }

  /// 启动周期性设备发现
  void _startDiscoveryTimer() {
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      discoverPeers();
    });
  }

  // ==================== 连接管理 ====================

  /// 连接到指定对等设备
  ///
  /// 借鉴 webrtc-rs 的 WebRTC 连接建立流程:
  /// https://github.com/webrtc-rs/webrtc/blob/master/webrtc/src/api/peerconnection/peerconnection.go
  ///
  /// 连接流程（借鉴 WebRTC ICE 协商）:
  /// 1. 创建 RTCPeerConnection 并配置 ICE 服务器
  /// 2. 创建 DataChannel（用于数据传输）
  /// 3. 创建 SDP Offer
  /// 4. 通过信令服务器发送 Offer 到目标 Peer
  /// 5. 接收 SDP Answer
  /// 6. 交换 ICE 候选（Trickle ICE）
  /// 7. ICE 连接状态变为 connected → P2P 通道建立
  ///
  /// NAT 穿透策略（借鉴 webrtc-rs 的 ICE Agent）:
  /// 1. 尝试 Host 候选直连（同一局域网）
  /// 2. 失败时尝试 Srflx 候选（STUN 反射地址）
  /// 3. 最后尝试 Relay 候选（TURN 中继）
  Future<bool> connect(String peerId) async {
    if (_state != LibP2PConnectionState.connected) return false;
    if (_activeConnections.contains(peerId)) return true;

    try {
      // 步骤 1: 创建 WebRTC Offer —— 借鉴 webrtc-rs 的 CreateOffer
      final offer = await _createOffer();

      // 步骤 2: 通过信令服务器发送 Offer —— 借鉴 webrtc-rs 的信令交换
      final answer = await _exchangeOffer(peerId, offer);

      // 步骤 3: 设置远程描述并等待 ICE 连接建立
      await _establishConnection(peerId, answer);

      _activeConnections.add(peerId);

      // 更新 Peer 状态
      if (_peers.containsKey(peerId)) {
        _peers[peerId] = _peers[peerId]!.copyWith(
          state: LibP2PConnectionState.connected,
        );
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 创建 WebRTC SDP Offer
  ///
  /// 借鉴 webrtc-rs 的 PeerConnection.CreateOffer():
  /// https://github.com/webrtc-rs/webrtc/blob/master/webrtc/src/api/peerconnection/peerconnection.go
  Future<SessionDescription> _createOffer() async {
    // TODO: 实际实现应使用 dart_webrtc 或 FFI 调用原生 WebRTC
    // 创建 RTCPeerConnection 配置:
    // final configuration = RTCConfiguration(
    //   iceServers: _iceServers.map((s) => RTCIceServer(
    //     urls: [s.url],
    //     username: s.username,
    //     credential: s.credential,
    //   )).toList(),
    // );
    // final pc = await createPeerConnection(configuration);
    // await pc.createDataChannel('devnote', RTCDataChannelInit());
    // final offer = await pc.createOffer();
    // await pc.setLocalDescription(offer);

    // 模拟创建 Offer
    await Future.delayed(const Duration(milliseconds: 100));
    return const SessionDescription(
      type: 'offer',
      sdp: 'v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n',
    );
  }

  /// 通过信令服务器交换 SDP Offer/Answer
  ///
  /// 借鉴 webrtc-rs 的信令交换模式
  Future<SessionDescription> _exchangeOffer(
    String peerId,
    SessionDescription offer,
  ) async {
    // TODO: 实际实现应通过信令服务器:
    // 1. 发送 offer 到目标 peer
    // 2. 等待目标 peer 创建 answer
    // 3. 接收 answer 并返回
    await Future.delayed(const Duration(milliseconds: 200));
    return const SessionDescription(
      type: 'answer',
      sdp: 'v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n',
    );
  }

  /// 建立 WebRTC 连接
  ///
  /// 借鉴 webrtc-rs 的 ICE 连接建立流程:
  /// https://github.com/webrtc-rs/webrtc/blob/master/webrtcice/src/agent/agent.go
  Future<void> _establishConnection(
    String peerId,
    SessionDescription answer,
  ) async {
    // TODO: 实际实现:
    // 1. pc.setRemoteDescription(answer)
    // 2. 等待 ICE 连接状态变为 connected
    // 3. 监听 DataChannel 的 onmessage 事件
    await Future.delayed(const Duration(milliseconds: 100));
  }

  // ==================== 数据传输 ====================

  /// 向指定对等设备发送数据
  ///
  /// 借鉴 webrtc-rs 的 DataChannel.Send():
  /// https://github.com/webrtc-rs/webrtc/blob/master/webrtc/src/datachannel/datachannel.go
  ///
  /// 数据通过 RTCDataChannel 传输，支持:
  /// - 有序/无序传输
  /// - 可靠/部分可靠模式
  /// - 二进制和文本数据
  Future<bool> send(String peerId, Uint8List data) async {
    if (!_activeConnections.contains(peerId)) return false;

    try {
      // TODO: 实际实现应通过 DataChannel 发送:
      // final channel = _dataChannels[peerId];
      // channel?.send(Uint8List.fromList(data));

      return true;
    } catch (e) {
      return false;
    }
  }

  // ==================== 停止 ====================

  /// 停止 LibP2P 适配器 —— 关闭所有连接和资源
  ///
  /// 借鉴 libp2p 的 Host.Close() 和 webrtc-rs 的 PeerConnection.Close()
  Future<void> stop() async {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;

    _signalingSubscription?.cancel();
    _signalingSubscription = null;

    // 关闭所有活跃连接 —— 借鉴 webrtc-rs 的 PeerConnection.Close()
    for (final peerId in _activeConnections) {
      if (_peers.containsKey(peerId)) {
        _peers[peerId] = _peers[peerId]!.copyWith(
          state: LibP2PConnectionState.closed,
        );
      }
    }
    _activeConnections.clear();

    _state = LibP2PConnectionState.disconnected;
    _notifyStateListeners();
  }

  /// 断开指定对等设备的连接
  Future<void> disconnectPeer(String peerId) async {
    _activeConnections.remove(peerId);

    if (_peers.containsKey(peerId)) {
      _peers[peerId] = _peers[peerId]!.copyWith(
        state: LibP2PConnectionState.disconnected,
      );
    }

    // TODO: 实际实现应关闭对应的 DataChannel 和 PeerConnection
  }

  /// 获取当前已知的对等节点信息
  List<LibP2PPeerInfo> get knownPeers => _peers.values.toList();

  /// 获取已连接的 PeerID 列表
  List<String> get connectedPeers => _activeConnections.toList();

  /// 检查指定 Peer 是否在线
  bool isPeerOnline(String peerId) {
    final peer = _peers[peerId];
    return peer?.isOnline ?? false;
  }
}
