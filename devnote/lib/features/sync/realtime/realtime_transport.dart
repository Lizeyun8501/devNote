// 实时协作 WebSocket 传输层
//
// 借鉴项目：
// - **Logseq RTC** ([GitHub](https://github.com/logseq/logseq)): WebSocket +
//   操作广播的实时协作（RTC）实现，本类参考其传输层职责划分——传输层只
//   负责"连接 / 收 / 发 / 重连"，业务层（RealtimeCollabService）负责协议
//   语义解释（op / presence / sync_request / sync_response / heartbeat）。
// - **Yjs y-websocket** ([GitHub](https://github.com/yjs/y-websocket)): 借鉴其
//   消息类型枚举与"心跳保活 + 自动重连"策略。
//
// 设计要点：
// 1. 基于 web_socket_channel（pubspec 已声明 ^3.0.1），跨平台一致行为。
// 2. 上行/下行均为 JSON 文本帧，下行通过 `messages` 流对外暴露。
// 3. 内置自动重连（指数退避，最大 30 秒），重连成功后通过
//    `onReconnected` 回调通知业务层补发缓冲区。
// 4. 不在此层解释业务语义，仅做透传，便于单元测试与协议演进。

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:devnote/core/observability/app_logger.dart';

/// WebSocket 连接状态机
///
/// 借鉴 Yjs y-websocket 的连接状态划分：
/// - `disconnected`: 未连接或已主动断开
/// - `connecting`: 正在建立连接
/// - `connected`: 连接已建立且可用
/// - `reconnecting`: 因网络抖动正在自动重连
/// - `error`: 不可恢复的错误（如认证失败）
enum RealtimeConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// 实时协作消息类型枚举
///
/// 借鉴 Logseq RTC 与 Yjs y-websocket 的协议消息划分：
/// - `join`: 加入笔记协作会话
/// - `op`: 增量操作广播
/// - `presence`: 协作者在线状态（光标 / 选区）
/// - `syncRequest`: 请求缺失操作（基于向量时钟）
/// - `syncResponse`: 返回缺失操作列表
/// - `heartbeat`: 心跳保活
enum RealtimeMessageType {
  join,
  op,
  presence,
  syncRequest,
  syncResponse,
  heartbeat;

  /// 字符串标识 ↔ 枚举互转（用于 JSON 协议序列化）
  String get label {
    switch (this) {
      case RealtimeMessageType.join:
        return 'join';
      case RealtimeMessageType.op:
        return 'op';
      case RealtimeMessageType.presence:
        return 'presence';
      case RealtimeMessageType.syncRequest:
        return 'sync_request';
      case RealtimeMessageType.syncResponse:
        return 'sync_response';
      case RealtimeMessageType.heartbeat:
        return 'heartbeat';
    }
  }

  static RealtimeMessageType? fromLabel(String? label) {
    switch (label) {
      case 'join':
        return RealtimeMessageType.join;
      case 'op':
        return RealtimeMessageType.op;
      case 'presence':
        return RealtimeMessageType.presence;
      case 'sync_request':
        return RealtimeMessageType.syncRequest;
      case 'sync_response':
        return RealtimeMessageType.syncResponse;
      case 'heartbeat':
        return RealtimeMessageType.heartbeat;
      default:
        return null;
    }
  }
}

/// 实时协作 WebSocket 传输层
///
/// 职责：
/// - 建立 / 关闭 WebSocket 连接
/// - 发送 JSON 消息（`send`）
/// - 暴露下行消息流（`messages`）
/// - 暴露连接状态流（`statusStream`）
/// - 自动重连（指数退避，最大 30 秒）
/// - 重连成功后通过 `onReconnected` 通知业务层
///
/// 不在此层解释业务语义（如 op / presence），仅做透传。
class RealtimeTransport {
  RealtimeTransport();

  static const String _tag = 'RealtimeTransport';

  /// 心跳间隔（30 秒）—— 借鉴 Yjs y-websocket 默认 30s 心跳
  static const Duration heartbeatInterval = Duration(seconds: 30);

  /// 重连基础延迟（1 秒），指数退避起点
  static const Duration _reconnectBaseDelay = Duration(seconds: 1);

  /// 重连最大延迟（30 秒），指数退避上限
  static const Duration _reconnectMaxDelay = Duration(seconds: 30);

  WebSocketChannel? _channel;
  String? _url;
  String? _token;

  /// 当前连接状态
  RealtimeConnectionStatus _status = RealtimeConnectionStatus.disconnected;
  RealtimeConnectionStatus get status => _status;

  /// 下行消息流控制器（广播，允许多订阅者）
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// 连接状态变更流
  final StreamController<RealtimeConnectionStatus> _statusController =
      StreamController<RealtimeConnectionStatus>.broadcast();
  Stream<RealtimeConnectionStatus> get statusStream => _statusController.stream;

  /// 重连成功回调（业务层用于补发缓冲区操作）
  void Function()? onReconnected;

  /// 心跳定时器
  Timer? _heartbeatTimer;

  /// 重连定时器
  Timer? _reconnectTimer;

  /// 当前重连次数（用于指数退避计算）
  int _reconnectAttempts = 0;

  /// 是否已主动断开（主动断开时不触发自动重连）
  bool _manuallyDisconnected = false;

  /// 下行消息流订阅（用于在 dispose 时取消）
  StreamSubscription? _incomingSubscription;

  /// 建立 WebSocket 连接
  ///
  /// [url] WebSocket 服务器地址（ws:// 或 wss://）
  /// [token] 认证令牌，作为子协议或查询参数传递
  Future<void> connect(String url, {String? token}) async {
    if (_status == RealtimeConnectionStatus.connecting ||
        _status == RealtimeConnectionStatus.connected) {
      AppLogger.w(_tag, 'connect 被调用但当前状态为 $_status，忽略重复连接');
      return;
    }

    _url = url;
    _token = token;
    _manuallyDisconnected = false;
    _updateStatus(RealtimeConnectionStatus.connecting);

    await _doConnect();
  }

  /// 实际建立连接的内部方法
  Future<void> _doConnect() async {
    if (_url == null) {
      AppLogger.e(_tag, 'connect 失败：url 为空');
      _updateStatus(RealtimeConnectionStatus.error);
      return;
    }

    try {
      // 拼接 token 到查询参数（与 sync-server 现有鉴权约定一致）
      final uri = _token != null
          ? Uri.parse(_url!).replace(queryParameters: {
              'token': _token,
            })
          : Uri.parse(_url!);

      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _reconnectAttempts = 0;
      _updateStatus(RealtimeConnectionStatus.connected);
      AppLogger.i(_tag, 'WebSocket 连接成功: $_url');

      _startHeartbeat();
      _subscribeIncoming();
    } catch (e, st) {
      AppLogger.e(_tag, 'WebSocket 连接失败', error: e, stackTrace: st);
      _updateStatus(RealtimeConnectionStatus.error);
      _scheduleReconnect();
    }
  }

  /// 订阅下行消息流
  void _subscribeIncoming() {
    _incomingSubscription?.cancel();
    _incomingSubscription = _channel!.stream.listen(
      (data) {
        _onIncoming(data);
      },
      onError: (Object error, StackTrace st) {
        AppLogger.e(_tag, 'WebSocket 流错误', error: error, stackTrace: st);
        _handleDisconnect();
      },
      onDone: () {
        AppLogger.w(_tag, 'WebSocket 流结束');
        _handleDisconnect();
      },
      cancelOnError: true,
    );
  }

  /// 处理下行原始数据，解析为 JSON 后投递到 `messages` 流
  void _onIncoming(dynamic data) {
    if (data is String) {
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        _messageController.add(json);
      } catch (e) {
        AppLogger.w(_tag, '下行消息 JSON 解析失败: $e, raw=$data');
      }
    } else if (data is List<int>) {
      // 二进制帧当前协议未使用，预留扩展
      AppLogger.d(_tag, '收到二进制帧（${data.length} 字节），当前协议未处理');
    }
  }

  /// 发送 JSON 消息
  ///
  /// 若当前未连接，返回 false 由业务层决定是否入缓冲区。
  Future<bool> send(Map<String, dynamic> message) async {
    if (_channel == null || _status != RealtimeConnectionStatus.connected) {
      AppLogger.w(_tag, 'send 失败：连接未就绪（status=$_status）');
      return false;
    }
    try {
      final encoded = jsonEncode(message);
      _channel!.sink.add(encoded);
      return true;
    } catch (e) {
      AppLogger.e(_tag, 'send 异常', error: e);
      return false;
    }
  }

  /// 主动断开连接
  ///
  /// 标记为主动断开，不会触发自动重连。
  Future<void> disconnect() async {
    AppLogger.i(_tag, '主动断开 WebSocket 连接');
    _manuallyDisconnected = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _incomingSubscription?.cancel();
    _incomingSubscription = null;
    await _channel?.sink.close();
    _channel = null;
    _updateStatus(RealtimeConnectionStatus.disconnected);
  }

  /// 处理连接断开（被动）
  void _handleDisconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _incomingSubscription?.cancel();
    _incomingSubscription = null;
    _channel = null;

    if (_manuallyDisconnected) {
      _updateStatus(RealtimeConnectionStatus.disconnected);
      return;
    }

    _updateStatus(RealtimeConnectionStatus.reconnecting);
    _scheduleReconnect();
  }

  /// 调度自动重连（指数退避）
  ///
  /// 退避公式：delay = min(baseDelay * 2^attempts, maxDelay)
  /// 借鉴 Yjs y-websocket 与 go-retryablehttp 的指数退避策略。
  void _scheduleReconnect() {
    if (_manuallyDisconnected) return;
    if (_url == null) return;

    _reconnectTimer?.cancel();
    final delay = _computeReconnectDelay(_reconnectAttempts);
    _reconnectAttempts++;
    AppLogger.i(
      _tag,
      '计划在 ${delay.inSeconds}s 后重连（第 $_reconnectAttempts 次）',
    );
    _updateStatus(RealtimeConnectionStatus.reconnecting);
    _reconnectTimer = Timer(delay, () async {
      if (_manuallyDisconnected) return;
      final wasReconnecting = _reconnectAttempts > 1;
      await _doConnect();
      // 重连成功后通知业务层补发缓冲区
      if (_status == RealtimeConnectionStatus.connected &&
          wasReconnecting &&
          onReconnected != null) {
        AppLogger.i(_tag, '重连成功，通知业务层补发缓冲区');
        onReconnected!();
      }
    });
  }

  /// 计算指数退避延迟
  Duration _computeReconnectDelay(int attempt) {
    // delay = base * 2^attempt，上限为 maxDelay
    final seconds = _reconnectBaseDelay.inSeconds *
        (1 << (attempt < 5 ? attempt : 5)); // 防止位移溢出
    final delay = Duration(seconds: seconds);
    return delay > _reconnectMaxDelay ? _reconnectMaxDelay : delay;
  }

  /// 启动心跳定时器
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      _sendHeartbeat();
    });
  }

  /// 发送心跳消息
  Future<void> _sendHeartbeat() async {
    final ok = await send({
      'type': RealtimeMessageType.heartbeat.label,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    if (!ok) {
      AppLogger.w(_tag, '心跳发送失败，可能连接已断开');
    }
  }

  /// 更新连接状态并广播
  void _updateStatus(RealtimeConnectionStatus newStatus) {
    if (_status == newStatus) return;
    _status = newStatus;
    AppLogger.d(_tag, '连接状态变更: $newStatus');
    _statusController.add(newStatus);
  }

  /// 释放所有资源
  ///
  /// 调用后不可再使用本实例。
  Future<void> dispose() async {
    await disconnect();
    await _messageController.close();
    await _statusController.close();
    developer.log('RealtimeTransport disposed', name: _tag);
  }
}
