import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:devnote/core/config/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/observability/app_logger.dart';
import 'package:devnote/features/sync/conflict/conflict_resolver.dart';
import 'package:devnote/features/sync/incremental_sync_service.dart';
import 'crypto/e2e_crypto_service.dart';

enum SyncServiceStatus {
  idle,
  syncing,
  synced,
  conflict,
  error,
  offline,
}

class SyncServiceState {
  final SyncServiceStatus status;
  final DateTime? lastSyncedAt;
  final int pendingChanges;
  final bool encryptionEnabled;
  final String? lastError;

  const SyncServiceState({
    required this.status,
    this.lastSyncedAt,
    this.pendingChanges = 0,
    this.encryptionEnabled = false,
    this.lastError,
  });

  SyncServiceState copyWith({
    SyncServiceStatus? status,
    DateTime? lastSyncedAt,
    int? pendingChanges,
    bool? encryptionEnabled,
    String? lastError,
  }) {
    return SyncServiceState(
      status: status ?? this.status,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      pendingChanges: pendingChanges ?? this.pendingChanges,
      encryptionEnabled: encryptionEnabled ?? this.encryptionEnabled,
      lastError: lastError,
    );
  }
}

class SyncService {
  SyncService();

  // SharedPreferences 中存储服务器地址和认证令牌的键名
  static const String _keyServerUrl = syncServerUrlKey;
  static const String _keyAuthToken = syncAuthTokenKey;

  static const String _keyLastSyncTime = 'sync_last_sync_time';
  static const String _keyPendingChanges = 'sync_pending_changes';

  // P0 修复: 新增设备 ID 和同步版本号的持久化键
  static const String _keyDeviceId = 'sync_device_id';
  static const String _keyLastSyncVersion = 'sync_last_version';

  final E2ECryptoService _cryptoService = getIt<E2ECryptoService>();
  final IncrementalSyncService _incrementalSync = getIt<IncrementalSyncService>();

  SyncServiceState _state = const SyncServiceState(
    status: SyncServiceStatus.idle,
  );

  SyncServiceState get state => _state;

  // 状态广播流，用于外部监听服务状态变化
  final StreamController<SyncServiceState> _stateController =
      StreamController<SyncServiceState>.broadcast();

  /// 对外暴露的状态流，供 SyncBloc 等消费者订阅
  Stream<SyncServiceState> get stateStream => _stateController.stream;

  // 冲突解析器，用于在同步过程中检测和记录冲突
  final ConflictResolver conflictResolver = ConflictResolver();

  Future<void> initialize() async {
    await _cryptoService.initialize();
    await _incrementalSync.initialize();

    final prefs = await SharedPreferences.getInstance();
    final lastSyncMs = prefs.getInt(_keyLastSyncTime);
    final pendingChanges = prefs.getInt(_keyPendingChanges) ?? 0;

    _state = _state.copyWith(
      lastSyncedAt: lastSyncMs != null
          ? DateTime.fromMillisecondsSinceEpoch(lastSyncMs)
          : null,
      pendingChanges: pendingChanges,
      encryptionEnabled: _cryptoService.state.status != E2ECryptoStatus.notConfigured,
    );
  }

  bool isEncryptionReady() {
    return _cryptoService.state.status != E2ECryptoStatus.notConfigured;
  }

  Future<SyncServiceState> pushChanges(Map<String, dynamic> data) async {
    _state = _state.copyWith(status: SyncServiceStatus.syncing);
    _notifyListeners();

    try {
      final payload = jsonEncode(data);
      final payloadBytes = Uint8List.fromList(utf8.encode(payload));

      Uint8List dataToPush;

      if (isEncryptionReady()) {
        final encrypted = _cryptoService.encryptSyncData(payloadBytes);
        if (encrypted == null) {
          _state = _state.copyWith(
            status: SyncServiceStatus.error,
            lastError: '加密失败',
          );
          _notifyListeners();
          return _state;
        }
        dataToPush = encrypted;
      } else {
        dataToPush = payloadBytes;
      }

      await _performPush(dataToPush);

      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setInt(_keyLastSyncTime, now.millisecondsSinceEpoch);
      await prefs.setInt(_keyPendingChanges, 0);

      _state = _state.copyWith(
        status: SyncServiceStatus.synced,
        lastSyncedAt: now,
        pendingChanges: 0,
      );
    } catch (e) {
      _state = _state.copyWith(
        status: SyncServiceStatus.error,
        lastError: e.toString(),
      );
      _notifyListeners();
      rethrow;
    }

    _notifyListeners();
    return _state;
  }

  Future<Map<String, dynamic>?> pullChanges() async {
    _state = _state.copyWith(status: SyncServiceStatus.syncing);
    _notifyListeners();

    try {
      final raw = await _performPull();
      if (raw == null) {
        _state = _state.copyWith(status: SyncServiceStatus.synced);
        _notifyListeners();
        return null;
      }

      Uint8List decryptedBytes;

      if (isEncryptionReady()) {
        final decrypted = _cryptoService.decryptSyncData(raw);
        if (decrypted == null) {
          _state = _state.copyWith(
            status: SyncServiceStatus.error,
            lastError: '解密失败',
          );
          _notifyListeners();
          return null;
        }
        decryptedBytes = decrypted;
      } else {
        decryptedBytes = raw;
      }

      final jsonStr = utf8.decode(decryptedBytes);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      // 修复：先更新 lastSyncTime，但不设 synced 状态
      // 原代码在数据返回给调用方应用前就设 synced，如果调用方应用数据失败，
      // 状态显示已同步但实际数据未生效，导致不一致
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setInt(_keyLastSyncTime, now.millisecondsSinceEpoch);

      _state = _state.copyWith(
        status: SyncServiceStatus.syncing,
        lastSyncedAt: now,
      );
      _notifyListeners();

      return data;
    } catch (e) {
      _state = _state.copyWith(
        status: SyncServiceStatus.error,
        lastError: e.toString(),
      );
      _notifyListeners();
      rethrow;
    }
  }

  /// 解决同步冲突
  /// 修复：原代码完全忽略 useRemote 参数，始终设置 synced 状态而不做任何实际解决。
  /// 现在根据 useRemote 参数记录冲突解决方向，并更新状态。
  ///
  /// P1 修复 (INC-07): 原实现仅更新本地状态，不上传服务端，导致其他设备
  /// 拉取时仍看到冲突态。现改为调用服务端 /sync/conflicts/resolve 端点。
  Future<void> resolveConflict(bool useRemote, {String? conflictId}) async {
    if (useRemote) {
      // 使用远程版本：当前本地修改已被远程覆盖
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyPendingChanges, 0);
    }

    // P1 修复 (INC-07): 上报冲突解决结果到服务端
    if (conflictId != null) {
      try {
        final serverUrl = await _getServerUrl();
        final token = await _getAuthToken();
        final uri = Uri.parse('$serverUrl/api/v1/sync/conflicts/resolve');
        final headers = <String, String>{
          'Content-Type': 'application/json',
        };
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
        final body = jsonEncode({
          'conflict_id': conflictId,
          'resolution': useRemote ? 'remote' : 'local',
        });
        await http.post(uri, headers: headers, body: body).timeout(
          const Duration(seconds: 15),
        );
      } catch (e, stack) {
        // P2 修复 (P2-12): 记录上报失败日志，原 catch(_) 静默吞异常导致故障不可见
        // 上报失败不影响本地状态，下次同步会重新检测冲突
        AppLogger.w('SyncService', 'conflict report failed', error: e);
      }
    }

    _state = _state.copyWith(
      status: SyncServiceStatus.synced,
      pendingChanges: useRemote ? 0 : _state.pendingChanges,
      lastError: null,
    );
    _notifyListeners();
  }

  void markPendingChange() {
    _state = _state.copyWith(
      pendingChanges: _state.pendingChanges + 1,
    );
  }

  /// 增量推送 —— 使用 RdiffService 仅传输差异部分，支持断点续传
  ///
  /// 适用于大文档的小范围修改场景，可大幅减少网络带宽消耗。
  /// 网络中断后可调用 [resumeIncrementalPush] 从断点恢复。
  Future<IncrementalSyncResult> pushIncremental(
    Map<String, dynamic> data, {
    bool encrypt = true,
  }) async {
    _state = _state.copyWith(status: SyncServiceStatus.syncing);
    _notifyListeners();

    final payloadBytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    final result = await _incrementalSync.pushIncremental(
      payloadBytes,
      encrypt: encrypt,
    );

    if (result.success) {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setInt(_keyLastSyncTime, now.millisecondsSinceEpoch);
      await prefs.setInt(_keyPendingChanges, 0);

      _state = _state.copyWith(
        status: SyncServiceStatus.synced,
        lastSyncedAt: now,
        pendingChanges: 0,
      );
    } else {
      _state = _state.copyWith(
        status: SyncServiceStatus.error,
        lastError: result.error ?? '增量推送失败',
      );
    }

    _notifyListeners();
    return result;
  }

  /// 恢复未完成的增量推送（断点续传）
  ///
  /// 若有未完成的同步会话，重新传入最新数据继续上传。
  /// 已上传的块会被跳过，仅传输剩余部分。
  Future<IncrementalSyncResult> resumeIncrementalPush(
    Map<String, dynamic> data, {
    bool encrypt = true,
  }) async {
    if (!_incrementalSync.hasResumableSession) {
      return const IncrementalSyncResult(
        success: false,
        error: '无可恢复的同步会话',
      );
    }

    _state = _state.copyWith(status: SyncServiceStatus.syncing);
    _notifyListeners();

    final payloadBytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    final result = await _incrementalSync.pushIncremental(
      payloadBytes,
      encrypt: encrypt,
    );

    if (result.success) {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setInt(_keyLastSyncTime, now.millisecondsSinceEpoch);
      await prefs.setInt(_keyPendingChanges, 0);

      _state = _state.copyWith(
        status: SyncServiceStatus.synced,
        lastSyncedAt: now,
        pendingChanges: 0,
      );
    } else {
      _state = _state.copyWith(
        status: SyncServiceStatus.error,
        lastError: result.error ?? '断点续传失败',
      );
    }

    _notifyListeners();
    return result;
  }

  /// 放弃当前增量同步会话
  Future<void> abortIncrementalSession() async {
    await _incrementalSync.abortSession();
    _state = _state.copyWith(status: SyncServiceStatus.idle);
    _notifyListeners();
  }

  /// 获取增量同步进度（0.0-1.0）
  double get incrementalSyncProgress => _incrementalSync.currentProgress;

  /// 是否有可恢复的增量同步会话
  bool get hasResumableSession => _incrementalSync.hasResumableSession;

  /// 获取配置的服务器地址，优先从 SharedPreferences 读取，否则使用默认值
  Future<String> _getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyServerUrl) ?? defaultSyncServerUrl;
  }

  /// 获取 JWT 认证令牌
  Future<String?> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAuthToken);
  }

  /// 获取设备 ID，首次调用时生成并持久化
  /// P0 修复: 服务端 PushRequest/PullRequest 要求 device_id 字段
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_keyDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      // 生成 UUID v4 作为设备标识
      deviceId = _generateUuid();
      await prefs.setString(_keyDeviceId, deviceId);
    }
    return deviceId;
  }

  /// 获取上次同步的服务端版本号
  Future<int> _getLastSyncVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyLastSyncVersion) ?? 0;
  }

  /// 更新上次同步的服务端版本号
  Future<void> _setLastSyncVersion(int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastSyncVersion, version);
  }

  /// 简单 UUID v4 生成（避免引入额外依赖）
  String _generateUuid() {
    final random = DateTime.now().microsecondsSinceEpoch;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${timestamp.toRadixString(16)}-${random.toRadixString(16)}-${(random ^ timestamp).toRadixString(16)}';
  }

  /// 执行推送：将加密后的数据通过 POST 请求发送到同步服务器
  ///
  /// P0 修复: 原实现发送 `application/octet-stream` 原始字节，但服务端
  /// `SyncHandler.Push` 期望 JSON 结构 `{device_id, records: [{note_id, action, version, payload}]}`。
  /// 两端协议完全不匹配，任何 Push 都会 400 失败。
  /// 现改为发送 JSON 结构化请求，加密后的数据作为 records[].payload 字段。
  ///
  /// 请求地址: POST /api/v1/sync/push
  /// 请求头: Content-Type: application/json, Authorization: Bearer {token}
  /// 请求体: PushRequest JSON（加密 payload 作为 base64 字符串）
  Future<void> _performPush(Uint8List data) async {
    final serverUrl = await _getServerUrl();
    final token = await _getAuthToken();
    final deviceId = await _getDeviceId();

    final uri = Uri.parse('$serverUrl/api/v1/sync/push');
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    // P1 修复 (INC-01): 原实现把所有笔记塞进单条 record（note_id='sync-batch'），
    // 服务端 Push handler 按 per-note 语义处理，无法正确建立 per-note 版本链。
    // 改为：解析 data 为 notes 列表，每条 note 生成独立 record。
    final List<Map<String, dynamic>> records;
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is List) {
        records = decoded.map((note) => {
          'note_id': note['id'] ?? 'unknown',
          'action': 'update',
          'version': note['version'] ?? 0,
          'payload': base64Encode(utf8.encode(jsonEncode(note))),
        }).toList();
      } else if (decoded is Map) {
        // 单条 note 包装为列表
        records = [
          {
            'note_id': decoded['id'] ?? 'single',
            'action': 'update',
            'version': decoded['version'] ?? 0,
            'payload': base64Encode(data),
          }
        ];
      } else {
        // 无法解析，回退到批量模式
        records = [
          {
            'note_id': 'sync-batch',
            'action': 'update',
            'version': 0,
            'payload': base64Encode(data),
          }
        ];
      }
    } catch (_) {
      // 非 JSON 数据（如加密二进制），使用批量模式
      records = [
        {
          'note_id': 'sync-batch',
          'action': 'update',
          'version': 0,
          'payload': base64Encode(data),
        }
      ];
    }

    final body = jsonEncode({
      'device_id': deviceId,
      'records': records,
    });

    final response = await http
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // 推送成功
      return;
    }

    // 服务端返回错误，抛出异常
    throw Exception('推送失败: HTTP ${response.statusCode} - ${response.body}');
  }

  /// 执行拉取：从同步服务器获取数据
  ///
  /// P0 修复: 原实现用 GET 请求期望 octet-stream 响应，但服务端
  /// `SyncHandler.Pull` 期望 POST + JSON PullRequest `{device_id, since_version}`，
  /// 返回 PullResponse JSON `{records, latest_version, has_more, limit}`。
  /// 现改为 POST JSON 请求，从 records 中提取 payload 解密。
  ///
  /// 请求地址: POST /api/v1/sync/pull
  /// 请求头: Content-Type: application/json, Authorization: Bearer {token}
  /// 返回: 服务端响应中聚合后的原始字节数据（Uint8List），无新数据时返回 null
  Future<Uint8List?> _performPull() async {
    final serverUrl = await _getServerUrl();
    final token = await _getAuthToken();
    final deviceId = await _getDeviceId();

    final uri = Uri.parse('$serverUrl/api/v1/sync/pull');
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final sinceVersion = await _getLastSyncVersion();
    final body = jsonEncode({
      'device_id': deviceId,
      'since_version': sinceVersion,
    });

    final response = await http
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 204) {
      // 无新数据
      return null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // 拉取成功，解析 PullResponse JSON
      final resp = jsonDecode(response.body) as Map<String, dynamic>;
      final records = (resp['records'] as List?) ?? [];
      if (records.isEmpty) {
        return null;
      }
      // 聚合所有 record 的 payload（base64 编码的加密数据）
      final payloadBytes = <int>[];
      for (final record in records) {
        final payload = record['payload'] as String?;
        if (payload != null && payload.isNotEmpty) {
          payloadBytes.addAll(base64Decode(payload));
        }
      }
      // 更新本地最新版本号
      final latestVersion = resp['latest_version'];
      if (latestVersion != null) {
        await _setLastSyncVersion((latestVersion as num).toInt());
      }
      if (payloadBytes.isEmpty) {
        return null;
      }
      return Uint8List.fromList(payloadBytes);
    }

    // 服务端返回错误，抛出异常
    throw Exception('拉取失败: HTTP ${response.statusCode} - ${response.body}');
  }

  /// 通知所有状态流监听器当前服务状态已变更
  void _notifyListeners() {
    _stateController.add(_state);
  }

  /// 释放资源：关闭状态流控制器
  void dispose() {
    _stateController.close();
  }
}
