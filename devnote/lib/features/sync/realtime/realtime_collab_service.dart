// 实时协作服务（Realtime Collaboration Service）
//
// 在现有 VectorClock CRDT（lib/features/sync/conflict/conflict_resolver.dart）
// 基础上叠加操作日志（OpLog）广播与 WebSocket 通道，实现多人实时协同编辑。
//
// ## 借鉴的开源项目
// - **Anytype any-sync** ([GitHub](https://github.com/anyproto/any-sync)):
//   DAG 操作图 + P2P 广播。本服务借鉴其"操作日志为核心数据单元"的思想：
//   每次本地编辑产生一个 `CollabOperation`，通过 WebSocket 广播给同会话的
//   其他设备，远端按向量时钟排序后应用。
// - **Logseq RTC** ([GitHub](https://github.com/logseq/logseq)):
//   WebSocket + 操作广播的实时协作。本服务借鉴其"增量操作传输"原则——
//   只传输操作增量，不传输完整文档，降低带宽与冲突面。
// - **Yjs / Automerge** ([GitHub](https://github.com/yjs/yjs)):
//   CRDT 操作语义。本服务复用现有 devnote-crdt 的 YATA 算法思想（通过
//   `ConflictResolver.mergeWithVectorClocks` 间接复用），并对并发文本块
//   采用字符级合并。
// - **Yjs y-websocket** ([GitHub](https://github.com/yjs/y-websocket)):
//   心跳保活 + 自动重连 + 操作缓冲区补发。
//
// ## 核心数据流
// 1. 本地编辑 → EditorBloc 调用 `broadcastOperation(op)` → 写入 OpLog →
//    通过 RealtimeTransport 广播 `{"type":"op",...}`
// 2. 远端 `{"type":"op",...}` → RealtimeTransport.messages →
//    RealtimeCollabService.incomingOperations → EditorBloc 应用
// 3. 网络断开 → 操作入缓冲区（SharedPreferences 持久化）→ 重连后补发
// 4. 光标移动 → `updateCursor(...)` → 广播 `{"type":"presence",...}` →
//    presenceUpdates 流 → CollabCursorOverlay 渲染

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:devnote/core/observability/app_logger.dart';
import 'package:devnote/features/sync/conflict/conflict_resolver.dart';
import 'package:devnote/features/sync/realtime/realtime_transport.dart';

/// 协作操作类型枚举
///
/// 借鉴 Anytype any-sync 的操作类型划分与 Yjs 的 CRDT 操作语义：
/// - `insert`: 插入新 block
/// - `update`: 更新 block 内容
/// - `delete`: 删除 block
/// - `move`: 移动 block 位置
/// - `cursor`: 光标 / 选区移动（presence 协议，不修改文档）
enum CollabOperationType {
  insert,
  update,
  delete,
  move,
  cursor;

  String get label {
    switch (this) {
      case CollabOperationType.insert:
        return 'insert';
      case CollabOperationType.update:
        return 'update';
      case CollabOperationType.delete:
        return 'delete';
      case CollabOperationType.move:
        return 'move';
      case CollabOperationType.cursor:
        return 'cursor';
    }
  }

  static CollabOperationType fromLabel(String? label) {
    switch (label) {
      case 'insert':
        return CollabOperationType.insert;
      case 'update':
        return CollabOperationType.update;
      case 'delete':
        return CollabOperationType.delete;
      case 'move':
        return CollabOperationType.move;
      case 'cursor':
        return CollabOperationType.cursor;
      default:
        return CollabOperationType.update;
    }
  }
}

/// 协作操作数据类
///
/// 借鉴 Anytype any-sync 的 Operation 模型：每个操作携带操作 ID、设备 ID、
/// 向量时钟、目标 block ID、操作类型与负载，是 OpLog 与广播协议的核心单元。
class CollabOperation {
  /// 操作唯一 ID（UUID v4）
  final String opId;

  /// 发起操作的设备 ID
  final String deviceId;

  /// 操作发生时的向量时钟（含所有设备的时钟分量）
  final VectorClock vectorClock;

  /// 操作目标 block ID（cursor 类型时为光标所在 block）
  final String blockId;

  /// 操作类型
  final CollabOperationType opType;

  /// 操作负载（如 update 时为新的 content，move 时为 newPosition）
  final Map<String, dynamic> payload;

  /// 操作时间戳（毫秒）
  final int timestamp;

  const CollabOperation({
    required this.opId,
    required this.deviceId,
    required this.vectorClock,
    required this.blockId,
    required this.opType,
    required this.payload,
    required this.timestamp,
  });

  /// 从 JSON 反序列化（用于 WebSocket 协议传输）
  factory CollabOperation.fromJson(Map<String, dynamic> json) {
    final vcJson = json['vector_clock'] as Map<String, dynamic>? ?? {};
    return CollabOperation(
      opId: json['op_id'] as String,
      deviceId: json['device_id'] as String,
      vectorClock: VectorClock.fromJson(vcJson),
      blockId: json['block_id'] as String,
      opType: CollabOperationType.fromLabel(json['op_type'] as String?),
      payload:
          (json['payload'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      timestamp: (json['timestamp'] as num).toInt(),
    );
  }

  /// 序列化为 JSON（用于 WebSocket 协议传输与 SharedPreferences 持久化）
  Map<String, dynamic> toJson() {
    return {
      'op_id': opId,
      'device_id': deviceId,
      'vector_clock': vectorClock.toJson(),
      'block_id': blockId,
      'op_type': opType.label,
      'payload': payload,
      'timestamp': timestamp,
    };
  }

  CollabOperation copyWith({
    String? opId,
    String? deviceId,
    VectorClock? vectorClock,
    String? blockId,
    CollabOperationType? opType,
    Map<String, dynamic>? payload,
    int? timestamp,
  }) {
    return CollabOperation(
      opId: opId ?? this.opId,
      deviceId: deviceId ?? this.deviceId,
      vectorClock: vectorClock ?? this.vectorClock,
      blockId: blockId ?? this.blockId,
      opType: opType ?? this.opType,
      payload: payload ?? this.payload,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// 操作日志缓冲区（OpLog）
///
/// 借鉴 Anytype any-sync 的 DAG 操作图与 Yjs 的操作历史：
/// - 按 (deviceId, opId) 去重，避免重复应用同一操作
/// - 按向量时钟排序，保证因果顺序应用
/// - 支持合并另一端发来的操作列表
/// - 支持持久化到 SharedPreferences，断网恢复后补发
class OpLog {
  OpLog();

  static const String _tag = 'OpLog';

  /// 内部操作存储（key: "${deviceId}:${opId}"，用于 O(1) 去重判定）
  final Map<String, CollabOperation> _operations = {};

  /// 已记录的操作列表（按向量时钟排序）
  List<CollabOperation> get operations {
    final list = _operations.values.toList();
    list.sort(_compareByVectorClock);
    return list;
  }

  /// 当前 OpLog 中的操作数量
  int get length => _operations.length;

  /// 是否为空
  bool get isEmpty => _operations.isEmpty;

  /// 向量时钟比较器
  ///
  /// 借鉴 Anytype any-sync 的因果排序：
  /// - 若 a 在 b 之前（a.isBefore(b) 且非并发）→ a 排前
  /// - 若 b 在 a 之前 → b 排前
  /// - 并发时按 timestamp 升序，再按 deviceId 字典序保证稳定
  static int _compareByVectorClock(CollabOperation a, CollabOperation b) {
    final aBeforeB =
        a.vectorClock.isBefore(b.vectorClock) &&
        !b.vectorClock.isBefore(a.vectorClock);
    if (aBeforeB) return -1;
    final bBeforeA =
        b.vectorClock.isBefore(a.vectorClock) &&
        !a.vectorClock.isBefore(b.vectorClock);
    if (bBeforeA) return 1;
    // 并发：按时间戳，再按 deviceId 保证稳定排序
    final tsCmp = a.timestamp.compareTo(b.timestamp);
    if (tsCmp != 0) return tsCmp;
    return a.deviceId.compareTo(b.deviceId);
  }

  /// 添加操作（自动去重）
  ///
  /// 返回 true 表示新增，false 表示已存在（重复操作）。
  bool add(CollabOperation op) {
    final key = '${op.deviceId}:${op.opId}';
    if (_operations.containsKey(key)) {
      AppLogger.d(_tag, '操作已存在，跳过: $key');
      return false;
    }
    _operations[key] = op;
    return true;
  }

  /// 批量合并另一端发来的操作列表（自动去重）
  ///
  /// 返回实际新增的操作数量。
  int mergeAll(List<CollabOperation> ops) {
    var added = 0;
    for (final op in ops) {
      if (add(op)) added++;
    }
    return added;
  }

  /// 是否已包含指定操作
  bool contains(String deviceId, String opId) {
    return _operations.containsKey('$deviceId:$opId');
  }

  /// 获取本地设备已发送但未被确认的操作（用于断网恢复后补发）
  ///
  /// 简化实现：返回所有由 [localDeviceId] 发起、且 timestamp > [since] 的操作。
  List<CollabOperation> pendingOperations(
    String localDeviceId, {
    int since = 0,
  }) {
    return _operations.values
        .where((op) =>
            op.deviceId == localDeviceId && op.timestamp > since)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// 清空所有操作
  void clear() {
    _operations.clear();
  }

  /// 序列化为 JSON 列表（用于 SharedPreferences 持久化）
  List<Map<String, dynamic>> toJsonList() {
    return operations.map((op) => op.toJson()).toList();
  }

  /// 从 JSON 列表反序列化
  void fromJsonList(List<dynamic> jsonList) {
    _operations.clear();
    for (final item in jsonList) {
      if (item is Map<String, dynamic>) {
        final op = CollabOperation.fromJson(item);
        _operations['${op.deviceId}:${op.opId}'] = op;
      }
    }
  }
}

/// 协作者在线状态（Presence）
///
/// 借鉴 Yjs y-protocols/awareness 与 Logseq RTC 的 presence 协议：
/// 每个在线协作者携带光标位置、选区、显示颜色与名称，通过心跳维持在线状态。
class PresenceState {
  /// 用户 ID
  final String userId;

  /// 设备 ID
  final String deviceId;

  /// 光标所在 block ID（null 表示未聚焦）
  final String? cursor;

  /// 光标偏移量
  final int? offset;

  /// 选区长度（0 表示纯光标，>0 表示选区高亮）
  final int length;

  /// 协作者显示颜色（ARGB 整数）
  final int color;

  /// 协作者显示名称
  final String name;

  /// 最后一次心跳时间戳（毫秒）
  final int lastSeen;

  const PresenceState({
    required this.userId,
    required this.deviceId,
    this.cursor,
    this.offset,
    this.length = 0,
    required this.color,
    required this.name,
    required this.lastSeen,
  });

  /// 是否在线（最后心跳在 60 秒内视为在线）
  bool get isOnline =>
      DateTime.now().millisecondsSinceEpoch - lastSeen <
      60 * 1000;

  PresenceState copyWith({
    String? userId,
    String? deviceId,
    Object? cursor = _sentinel,
    Object? offset = _sentinel,
    int? length,
    int? color,
    String? name,
    int? lastSeen,
  }) {
    return PresenceState(
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
      cursor: cursor == _sentinel ? this.cursor : cursor as String?,
      offset: offset == _sentinel ? this.offset : offset as int?,
      length: length ?? this.length,
      color: color ?? this.color,
      name: name ?? this.name,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  factory PresenceState.fromJson(Map<String, dynamic> json) {
    return PresenceState(
      userId: json['user_id'] as String,
      deviceId: json['device_id'] as String,
      cursor: json['cursor'] as String?,
      offset: json['offset'] as int?,
      length: (json['length'] as num?)?.toInt() ?? 0,
      color: (json['color'] as num?)?.toInt() ?? 0xFF2196F3,
      name: json['name'] as String? ?? '匿名协作者',
      lastSeen: (json['last_seen'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'device_id': deviceId,
      'cursor': cursor,
      'offset': offset,
      'length': length,
      'color': color,
      'name': name,
      'last_seen': lastSeen,
    };
  }
}

/// Sentinel 值用于区分"未传参"和"显式传 null"
const Object _sentinel = Object();

/// 实时协作服务状态机
///
/// 借鉴 Yjs y-websocket 的连接状态划分，与 RealtimeConnectionStatus 对齐但
/// 增加业务语义（如 `error` 携带错误信息）。
enum RealtimeCollabStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// 实时协作服务
///
/// 整合 RealtimeTransport（WebSocket 传输）+ OpLog（操作日志）+
/// PresenceState（协作者状态）+ ConflictResolver（VectorClock 合并），
/// 为 EditorBloc / RealtimeCollabBloc 提供统一的实时协作 API。
///
/// ## 关键设计
/// - **操作缓冲区持久化**：未发送成功的操作写入 SharedPreferences，断网
///   恢复后自动补发（借鉴 Yjs y-websocket 的 awareness 缓冲区思想）。
/// - **复用现有 VectorClock**：通过 `applyRemoteOperation` 调用
///   `ConflictResolver.mergeWithVectorClocks`，复用现有 CRDT 合并逻辑。
/// - **心跳保活**：复用 RealtimeTransport 的 30 秒心跳。
/// - **自动重连**：复用 RealtimeTransport 的指数退避重连。
class RealtimeCollabService {
  RealtimeCollabService({RealtimeTransport? transport})
      : _transport = transport ?? RealtimeTransport();

  static const String _tag = 'RealtimeCollabService';

  /// SharedPreferences 中持久化操作缓冲区的 key 前缀
  static const String _opBufferKeyPrefix = 'realtime_op_buffer_';

  /// SharedPreferences 中持久化本地设备 ID 的 key
  static const String _deviceIdKey = 'realtime_device_id';

  /// 默认 WebSocket 服务器地址（与 sync-server 对齐）
  static const String _defaultServerUrl = 'wss://sync.devnote.app/realtime';

  final RealtimeTransport _transport;
  final Uuid _uuid = const Uuid();

  /// 本地设备 ID（首次使用时生成并持久化）
  String? _deviceId;
  String get deviceId {
    final id = _deviceId;
    if (id == null) {
      throw StateError('RealtimeCollabService 尚未初始化，请先调用 initialize()');
    }
    return id;
  }

  /// 本地用户显示名称（可由上层设置）
  String _userName = '匿名协作者';
  String get userName => _userName;
  set userName(String value) {
    _userName = value;
  }

  /// 本地用户 ID（可由上层设置，默认与 deviceId 相同）
  String _userId = '';
  String get userId => _userId;
  set userId(String value) {
    _userId = value;
  }

  /// 当前协作会话的 noteId（null 表示未加入任何会话）
  String? _currentNoteId;
  String? get currentNoteId => _currentNoteId;

  /// 本地向量时钟（每次本地操作自增本设备分量）
  final VectorClock _localVectorClock = VectorClock();

  /// 本地向量时钟的只读快照（供 EditorBloc 在 CRDT 合并时使用）
  VectorClock get localVectorClock => _localVectorClock.copy();

  /// 操作日志缓冲区
  final OpLog _opLog = OpLog();
  OpLog get opLog => _opLog;

  /// 当前在线协作者表（key: deviceId）
  final Map<String, PresenceState> _presences = {};
  List<PresenceState> get presences => _presences.values.toList();

  /// 当前服务状态
  RealtimeCollabStatus _status = RealtimeCollabStatus.disconnected;
  RealtimeCollabStatus get status => _status;
  String? _lastError;

  /// 下行操作流控制器（业务层订阅此流应用远端操作）
  final StreamController<CollabOperation> _incomingOpController =
      StreamController<CollabOperation>.broadcast();
  Stream<CollabOperation> get incomingOperations => _incomingOpController.stream;

  /// 协作者状态变更流（光标 / 在线 / 离线）
  final StreamController<PresenceState> _presenceController =
      StreamController<PresenceState>.broadcast();
  Stream<PresenceState> get presenceUpdates => _presenceController.stream;

  /// 服务状态变更流
  final StreamController<RealtimeCollabStatus> _statusController =
      StreamController<RealtimeCollabStatus>.broadcast();
  Stream<RealtimeCollabStatus> get statusStream => _statusController.stream;

  /// 传输层订阅
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;
  StreamSubscription<RealtimeConnectionStatus>? _transportStatusSubscription;

  /// 本地光标状态（用于广播）
  PresenceState? _localPresence;

  /// 初始化服务（加载设备 ID 与未发送的操作缓冲区）
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = _generateDeviceId();
      await prefs.setString(_deviceIdKey, id);
    }
    _deviceId = id;
    if (_userId.isEmpty) {
      _userId = id;
    }

    // 注册重连回调（用于补发缓冲区）
    _transport.onReconnected = _onTransportReconnected;

    // 订阅传输层消息与状态
    _messageSubscription = _transport.messages.listen(_onIncomingMessage);
    _transportStatusSubscription = _transport.statusStream.listen((s) {
      switch (s) {
        case RealtimeConnectionStatus.disconnected:
          _updateStatus(RealtimeCollabStatus.disconnected);
          break;
        case RealtimeConnectionStatus.connecting:
          _updateStatus(RealtimeCollabStatus.connecting);
          break;
        case RealtimeConnectionStatus.connected:
          // 连接已建立，但需等待 join 成功后才算 connected
          // 此处先保持 connecting，由 join 响应或首个消息触发 connected
          break;
        case RealtimeConnectionStatus.reconnecting:
          _updateStatus(RealtimeCollabStatus.reconnecting);
          break;
        case RealtimeConnectionStatus.error:
          _updateStatus(RealtimeCollabStatus.error, error: '传输层错误');
          break;
      }
    });

    AppLogger.i(_tag, 'RealtimeCollabService 初始化完成，deviceId=$id');
  }

  /// 加入笔记协作会话
  ///
  /// 1. 建立 WebSocket 连接
  /// 2. 发送 join 消息
  /// 3. 加载本地未发送的操作缓冲区，准备补发
  Future<void> connect(String noteId) async {
    if (_deviceId == null) {
      await initialize();
    }
    if (_status == RealtimeCollabStatus.connected ||
        _status == RealtimeCollabStatus.connecting) {
      AppLogger.w(_tag, 'connect 被调用但当前状态为 $_status，先断开旧会话');
      await disconnect();
    }

    _currentNoteId = noteId;
    _updateStatus(RealtimeCollabStatus.connecting);

    // 加载该 noteId 的未发送操作缓冲区
    await _loadOpBuffer(noteId);

    // 建立 WebSocket 连接
    final token = await _resolveToken();
    await _transport.connect(_defaultServerUrl, token: token);

    // 发送 join 消息
    final ok = await _transport.send({
      'type': RealtimeMessageType.join.label,
      'noteId': noteId,
      'deviceId': deviceId,
      'userId': _userId,
      'name': _userName,
    });

    if (ok) {
      _updateStatus(RealtimeCollabStatus.connected);
      // 补发缓冲区中的待发送操作
      await _flushPendingOperations();
    } else {
      _updateStatus(RealtimeCollabStatus.reconnecting,
          error: 'join 消息发送失败，等待重连');
    }
  }

  /// 离开当前协作会话
  Future<void> disconnect() async {
    AppLogger.i(_tag, '离开协作会话: $_currentNoteId');
    // 持久化当前缓冲区（防止 disconnect 后丢失未发送操作）
    if (_currentNoteId != null) {
      await _saveOpBuffer(_currentNoteId!);
    }
    _currentNoteId = null;
    _presences.clear();
    _localPresence = null;
    await _transport.disconnect();
    _updateStatus(RealtimeCollabStatus.disconnected);
  }

  /// 广播本地操作
  ///
  /// 1. 自增本地向量时钟的 deviceId 分量
  /// 2. 构造 CollabOperation 并加入 OpLog
  /// 3. 通过 WebSocket 广播；发送失败则入缓冲区（已通过 OpLog 持久化）
  Future<void> broadcastOperation(CollabOperation op) async {
    // 加入 OpLog（去重）
    _opLog.add(op);

    // 持久化缓冲区（断网恢复后补发）
    if (_currentNoteId != null) {
      await _saveOpBuffer(_currentNoteId!);
    }

    // 广播
    final ok = await _transport.send({
      'type': RealtimeMessageType.op.label,
      'operation': op.toJson(),
    });

    if (!ok) {
      AppLogger.w(_tag, '操作广播失败，已保留在缓冲区等待重连补发: ${op.opId}');
    }
  }

  /// 创建并广播本地操作（便捷方法）
  ///
  /// 由 EditorBloc 在本地编辑时调用，自动填充 opId / deviceId /
  /// vectorClock / timestamp。
  Future<CollabOperation> emitLocalOperation({
    required String blockId,
    required CollabOperationType opType,
    required Map<String, dynamic> payload,
  }) async {
    // 自增本地向量时钟
    _localVectorClock.increment(deviceId);

    final op = CollabOperation(
      opId: _uuid.v4(),
      deviceId: deviceId,
      vectorClock: _localVectorClock.copy(),
      blockId: blockId,
      opType: opType,
      payload: payload,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await broadcastOperation(op);
    return op;
  }

  /// 更新本地光标并广播
  ///
  /// [blockId] 光标所在 block，[offset] 偏移量，[length] 选区长度（0=纯光标）
  Future<void> updateCursor({
    String? blockId,
    int? offset,
    int length = 0,
  }) async {
    _localPresence = PresenceState(
      userId: _userId,
      deviceId: deviceId,
      cursor: blockId,
      offset: offset,
      length: length,
      color: _colorForUserId(_userId),
      name: _userName,
      lastSeen: DateTime.now().millisecondsSinceEpoch,
    );

    final ok = await _transport.send({
      'type': RealtimeMessageType.presence.label,
      'state': _localPresence!.toJson(),
    });

    if (!ok) {
      AppLogger.w(_tag, '光标状态广播失败');
    }
  }

  /// 应用远端操作
  ///
  /// 复用现有 ConflictResolver 的 VectorClock 合并逻辑：
  /// 1. 将远端操作加入 OpLog（去重）
  /// 2. 合并本地向量时钟（取各设备最大值）
  /// 3. 通过 resolver 注册块级向量时钟，供后续 CRDT 合并使用
  /// 4. cursor 操作不修改文档，仅更新 presence
  ///
  /// 实际的 block 合并由 EditorBloc._onRemoteOperation 调用
  /// `ConflictResolver.mergeWithVectorClocks` 完成（因为 block 列表存在于
  /// EditorBloc 状态中）。本方法负责 OpLog 与向量时钟维护，确保后续操作
  /// 的因果顺序正确。
  ///
  /// 返回 true 表示操作为新增（应继续应用），false 表示重复操作（已应用过）。
  bool applyRemoteOperation(CollabOperation op, ConflictResolver resolver) {
    // 去重加入 OpLog
    final added = _opLog.add(op);
    if (!added) {
      AppLogger.d(_tag, '远端操作已存在，跳过应用: ${op.opId}');
      return false;
    }

    // 合并向量时钟（取各设备最大值，保证后续本地操作的因果顺序）
    _localVectorClock.merge(op.vectorClock);

    // cursor 操作不修改文档，仅更新 presence
    if (op.opType == CollabOperationType.cursor) {
      return false;
    }

    // 通过 resolver 注册块级向量时钟，供 EditorBloc 在调用
    // mergeWithVectorClocks 时进行因果关系判定
    resolver.setVectorClocks(
      {op.blockId: _localVectorClock},
      {op.blockId: op.vectorClock},
    );

    AppLogger.d(
      _tag,
      'applyRemoteOperation: op=${op.opId}, type=${op.opType.label}, '
      'blockId=${op.blockId}',
    );
    return true;
  }

  /// 请求缺失操作（基于向量时钟）
  ///
  /// 加入会话或重连后调用，向服务器请求本地缺失的操作。
  Future<void> requestSync() async {
    if (_status != RealtimeCollabStatus.connected) {
      AppLogger.w(_tag, 'requestSync 失败：未连接');
      return;
    }
    final ok = await _transport.send({
      'type': RealtimeMessageType.syncRequest.label,
      'since': _localVectorClock.toJson(),
      'deviceId': deviceId,
      'noteId': _currentNoteId,
    });
    if (!ok) {
      AppLogger.w(_tag, 'sync_request 发送失败');
    }
  }

  /// 处理传输层下行消息
  void _onIncomingMessage(Map<String, dynamic> msg) {
    final type = RealtimeMessageType.fromLabel(msg['type'] as String?);
    switch (type) {
      case RealtimeMessageType.op:
        _onRemoteOperation(msg);
        break;
      case RealtimeMessageType.presence:
        _onRemotePresence(msg);
        break;
      case RealtimeMessageType.syncResponse:
        _onSyncResponse(msg);
        break;
      case RealtimeMessageType.heartbeat:
        // 心跳响应，更新连接活跃状态
        AppLogger.d(_tag, '收到心跳响应');
        break;
      case RealtimeMessageType.join:
        // join 确认（服务器可能回送当前在线协作者列表）
        _onJoinAck(msg);
        break;
      case RealtimeMessageType.syncRequest:
        // 其他设备请求同步，本设备可响应（当前简化为忽略，由服务器统一处理）
        AppLogger.d(_tag, '收到其他设备的 sync_request，由服务器处理');
        break;
      case null:
        AppLogger.w(_tag, '未知消息类型: ${msg['type']}');
        break;
    }
  }

  /// 处理远端操作消息
  void _onRemoteOperation(Map<String, dynamic> msg) {
    final opJson = msg['operation'] as Map<String, dynamic>?;
    if (opJson == null) {
      AppLogger.w(_tag, 'op 消息缺少 operation 字段');
      return;
    }
    try {
      final op = CollabOperation.fromJson(opJson);
      // 投递到 incomingOperations 流，由 EditorBloc 应用
      _incomingOpController.add(op);
    } catch (e) {
      AppLogger.e(_tag, '远端操作反序列化失败', error: e);
    }
  }

  /// 处理远端 presence 消息
  void _onRemotePresence(Map<String, dynamic> msg) {
    final stateJson = msg['state'] as Map<String, dynamic>?;
    if (stateJson == null) {
      AppLogger.w(_tag, 'presence 消息缺少 state 字段');
      return;
    }
    try {
      final state = PresenceState.fromJson(stateJson);
      // 忽略自己的 presence 回环
      if (state.deviceId == deviceId) return;
      _presences[state.deviceId] = state;
      _presenceController.add(state);
    } catch (e) {
      AppLogger.e(_tag, 'presence 反序列化失败', error: e);
    }
  }

  /// 处理 sync_response 消息（批量补发缺失操作）
  void _onSyncResponse(Map<String, dynamic> msg) {
    final opsJson = msg['operations'] as List<dynamic>?;
    if (opsJson == null) return;
    for (final item in opsJson) {
      if (item is Map<String, dynamic>) {
        try {
          final op = CollabOperation.fromJson(item);
          _incomingOpController.add(op);
        } catch (e) {
          AppLogger.e(_tag, 'sync_response 操作反序列化失败', error: e);
        }
      }
    }
    AppLogger.i(_tag, '收到 sync_response，共 ${opsJson.length} 条操作');
  }

  /// 处理 join 确认（服务器回送当前在线协作者列表）
  void _onJoinAck(Map<String, dynamic> msg) {
    final peers = msg['peers'] as List<dynamic>?;
    if (peers == null) return;
    for (final p in peers) {
      if (p is Map<String, dynamic>) {
        try {
          final state = PresenceState.fromJson(p);
          if (state.deviceId != deviceId) {
            _presences[state.deviceId] = state;
            _presenceController.add(state);
          }
        } catch (_) {}
      }
    }
    _updateStatus(RealtimeCollabStatus.connected);
  }

  /// 传输层重连成功回调：补发缓冲区操作
  Future<void> _onTransportReconnected() async {
    AppLogger.i(_tag, '传输层重连成功，补发缓冲区操作');
    if (_currentNoteId != null) {
      // 重新发送 join
      await _transport.send({
        'type': RealtimeMessageType.join.label,
        'noteId': _currentNoteId,
        'deviceId': deviceId,
        'userId': _userId,
        'name': _userName,
      });
      // 请求缺失操作
      await requestSync();
      // 补发本地未确认操作
      await _flushPendingOperations();
      _updateStatus(RealtimeCollabStatus.connected);
    }
  }

  /// 补发缓冲区中所有本地操作
  Future<void> _flushPendingOperations() async {
    final pending = _opLog.pendingOperations(deviceId);
    if (pending.isEmpty) return;
    AppLogger.i(_tag, '补发 ${pending.length} 条本地操作');
    for (final op in pending) {
      final ok = await _transport.send({
        'type': RealtimeMessageType.op.label,
        'operation': op.toJson(),
      });
      if (!ok) {
        AppLogger.w(_tag, '补发失败，停止后续补发: ${op.opId}');
        break;
      }
    }
  }

  /// 加载指定 noteId 的操作缓冲区
  Future<void> _loadOpBuffer(String noteId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('$_opBufferKeyPrefix$noteId');
    if (jsonStr != null) {
      try {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        _opLog.fromJsonList(list);
        AppLogger.i(_tag, '加载操作缓冲区: $noteId, ${_opLog.length} 条');
      } catch (e) {
        AppLogger.e(_tag, '加载操作缓冲区失败', error: e);
        _opLog.clear();
      }
    }
  }

  /// 持久化指定 noteId 的操作缓冲区
  Future<void> _saveOpBuffer(String noteId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_opLog.toJsonList());
    await prefs.setString('$_opBufferKeyPrefix$noteId', jsonStr);
  }

  /// 解析认证 token（从 AppConfig 读取，避免循环依赖此处用 SharedPreferences）
  Future<String?> _resolveToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('sync_auth_token');
  }

  /// 生成设备 ID（密码学安全的 32 位十六进制字符串）
  String _generateDeviceId() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      final value = random.nextInt(16);
      buffer.write(value < 10
          ? String.fromCharCode(48 + value)
          : String.fromCharCode(87 + value));
    }
    return buffer.toString();
  }

  /// 基于 userId 生成稳定的显示颜色（ARGB 整数）
  ///
  /// 借鉴 Yjs y-protocols/awareness 的颜色分配策略：对 userId 哈希后
  /// 映射到 HSL 色环，保证同一用户在不同设备上颜色一致。
  static int _colorForUserId(String userId) {
    var hash = 0;
    for (final c in userId.codeUnits) {
      hash = (hash * 31 + c) & 0xFFFFFFFF;
    }
    final hue = hash % 360;
    return _hslToColor(hue, 0.65, 0.55);
  }

  /// HSL → ARGB 整数（简化实现）
  static int _hslToColor(num h, num s, num l) {
    final c = (1 - (2 * l - 1).abs()) * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = l - c / 2;
    num r, g, b;
    if (h < 60) {
      r = c;
      g = x;
      b = 0;
    } else if (h < 120) {
      r = x;
      g = c;
      b = 0;
    } else if (h < 180) {
      r = 0;
      g = c;
      b = x;
    } else if (h < 240) {
      r = 0;
      g = x;
      b = c;
    } else if (h < 300) {
      r = x;
      g = 0;
      b = c;
    } else {
      r = c;
      g = 0;
      b = x;
    }
    final ri = ((r + m) * 255).round();
    final gi = ((g + m) * 255).round();
    final bi = ((b + m) * 255).round();
    return (0xFF << 24) | (ri << 16) | (gi << 8) | bi;
  }

  /// 更新服务状态并广播
  void _updateStatus(RealtimeCollabStatus newStatus, {String? error}) {
    if (_status == newStatus && error == null) return;
    _status = newStatus;
    _lastError = error ?? _lastError;
    AppLogger.d(_tag, '服务状态变更: $newStatus${error != null ? ' ($error)' : ''}');
    _statusController.add(newStatus);
  }

  /// 释放所有资源
  Future<void> dispose() async {
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    await _transportStatusSubscription?.cancel();
    _transportStatusSubscription = null;
    await _transport.dispose();
    await _incomingOpController.close();
    await _presenceController.close();
    await _statusController.close();
    AppLogger.i(_tag, 'RealtimeCollabService disposed');
  }
}
