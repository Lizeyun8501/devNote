import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:devnote/core/di/injection.dart';
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

  static const String _keyLastSyncTime = 'sync_last_sync_time';
  static const String _keyPendingChanges = 'sync_pending_changes';

  final E2ECryptoService _cryptoService = getIt<E2ECryptoService>();

  SyncServiceState _state = const SyncServiceState(
    status: SyncServiceStatus.idle,
  );

  SyncServiceState get state => _state;

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

  Future<void> _performPush(Uint8List data) async {
    await Future.delayed(const Duration(milliseconds: 100));
  }

  Future<Uint8List?> _performPull() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return null;
  }

  void _notifyListeners() {}
}
