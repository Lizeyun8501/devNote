import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/sync/conflict/conflict_resolver.dart';
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

  // 默认同步服务器地址
  static const String _defaultServerUrl = 'https://sync.devnote.app';

  // SharedPreferences 中存储服务器地址和认证令牌的键名
  static const String _keyServerUrl = 'sync_server_url';
  static const String _keyAuthToken = 'sync_auth_token';

  static const String _keyLastSyncTime = 'sync_last_sync_time';
  static const String _keyPendingChanges = 'sync_pending_changes';

  final E2ECryptoService _cryptoService = getIt<E2ECryptoService>();

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

      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setInt(_keyLastSyncTime, now.millisecondsSinceEpoch);

      _state = _state.copyWith(
        status: SyncServiceStatus.synced,
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
      return null;
    }
  }

  Future<void> resolveConflict(bool useRemote) async {
    _state = _state.copyWith(status: SyncServiceStatus.synced);
    _notifyListeners();
  }

  void markPendingChange() {
    _state = _state.copyWith(
      pendingChanges: _state.pendingChanges + 1,
    );
  }

  /// 获取配置的服务器地址，优先从 SharedPreferences 读取，否则使用默认值
  Future<String> _getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyServerUrl) ?? _defaultServerUrl;
  }

  /// 获取 JWT 认证令牌
  Future<String?> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAuthToken);
  }

  /// 执行推送：将加密后的数据通过 POST 请求发送到同步服务器
  ///
  /// 请求地址: POST /api/v1/sync/push
  /// 请求头: Content-Type: application/octet-stream, Authorization: Bearer {token}
  /// 请求体: 加密后的 Uint8List 数据
  /// 网络异常或服务端非 2xx 响应时抛出异常，由上层 pushChanges 捕获处理
  Future<void> _performPush(Uint8List data) async {
    final serverUrl = await _getServerUrl();
    final token = await _getAuthToken();

    final uri = Uri.parse('$serverUrl/api/v1/sync/push');
    final headers = <String, String>{
      'Content-Type': 'application/octet-stream',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http.post(uri, headers: headers, body: data);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // 推送成功
      return;
    }

    // 服务端返回错误，抛出异常
    throw Exception('推送失败: HTTP ${response.statusCode} - ${response.body}');
  }

  /// 执行拉取：从同步服务器获取数据
  ///
  /// 请求地址: GET /api/v1/sync/pull
  /// 请求头: Authorization: Bearer {token}
  /// 返回: 服务端响应的原始字节数据（Uint8List），无新数据时返回 null
  /// 网络异常或服务端非 2xx 响应时抛出异常，由上层 pullChanges 捕获处理
  Future<Uint8List?> _performPull() async {
    final serverUrl = await _getServerUrl();
    final token = await _getAuthToken();

    final uri = Uri.parse('$serverUrl/api/v1/sync/pull');
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 204) {
      // 无新数据
      return null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // 拉取成功，返回原始字节数据
      return response.bodyBytes;
    }

    // 服务端返回错误，抛出异常
    throw Exception('拉取失败: HTTP ${response.statusCode} - ${response.body}');
  }

  /// 通知所有状态流监听器当前服务状态已变更
  void _notifyListeners() {
    _stateController.add(_state);
  }
}
