/// IncrementalSyncService - 增量同步与断点续传
///
/// 在 SyncService 全量同步的基础上，提供基于 rsync 算法的增量传输
/// 和分块上传的断点续传能力，降低网络带宽消耗并支持网络中断恢复。
///
/// 设计要点：
/// 1. 增量计算：使用 RdiffService 计算本地新数据与远端旧数据的差异，
///    仅传输 delta 指令流而非完整数据
/// 2. 断点续传：将 delta 数据分块上传，持久化已上传块索引，
///    网络中断后可从断点恢复，避免重新计算和传输
/// 3. 状态持久化：同步状态（远端签名、上传会话、块进度）写入
///    SharedPreferences，应用重启后可恢复未完成的同步
///
/// 借鉴：
/// - librsync 的 rsync 算法（增量传输）
/// - tus.io 协议（断点续传分块上传）
/// - Git 的对象存储模型（内容寻址）

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:devnote/core/config/app_config.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/sync/crypto/e2e_crypto_service.dart';
import 'package:devnote/features/sync/rdiff_service.dart';

/// 同步会话状态 —— 记录一次增量同步的完整上下文
class SyncSession {
  /// 会话唯一标识（用于服务端关联分块）
  final String sessionId;

  /// 远端数据的块签名（base64 编码的签名表）
  /// 用于本地计算 delta 时的基准
  final String? remoteSignaturesBase64;

  /// 已上传完成的分块索引集合
  final Set<int> completedChunks;

  /// 总分块数（-1 表示尚未计算）
  final int totalChunks;

  /// 会话创建时间
  final DateTime createdAt;

  /// 最后更新时间
  final DateTime updatedAt;

  const SyncSession({
    required this.sessionId,
    this.remoteSignaturesBase64,
    this.completedChunks = const {},
    this.totalChunks = -1,
    required this.createdAt,
    required this.updatedAt,
  });

  SyncSession copyWith({
    String? sessionId,
    String? remoteSignaturesBase64,
    Set<int>? completedChunks,
    int? totalChunks,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SyncSession(
      sessionId: sessionId ?? this.sessionId,
      remoteSignaturesBase64: remoteSignaturesBase64 ?? this.remoteSignaturesBase64,
      completedChunks: completedChunks ?? this.completedChunks,
      totalChunks: totalChunks ?? this.totalChunks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isComplete =>
      totalChunks > 0 && completedChunks.length >= totalChunks;

  double get progress {
    if (totalChunks <= 0) return 0.0;
    return completedChunks.length / totalChunks;
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'remoteSignaturesBase64': remoteSignaturesBase64,
        'completedChunks': completedChunks.toList(),
        'totalChunks': totalChunks,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory SyncSession.fromJson(Map<String, dynamic> json) {
    final completed = (json['completedChunks'] as List?) ?? [];
    return SyncSession(
      sessionId: json['sessionId'] as String,
      remoteSignaturesBase64: json['remoteSignaturesBase64'] as String?,
      completedChunks: completed.cast<int>().toSet(),
      totalChunks: (json['totalChunks'] as num?)?.toInt() ?? -1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num).toInt(),
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['updatedAt'] as num).toInt(),
      ),
    );
  }
}

/// 增量同步结果
class IncrementalSyncResult {
  final bool success;
  final int originalSize;
  final int deltaSize;
  final int uploadedChunks;
  final int totalChunks;
  final String? error;
  final SyncSession? session;

  const IncrementalSyncResult({
    required this.success,
    this.originalSize = 0,
    this.deltaSize = 0,
    this.uploadedChunks = 0,
    this.totalChunks = 0,
    this.error,
    this.session,
  });

  /// 增量压缩率（0.0-1.0，越小越好）
  double get compressionRatio {
    if (originalSize == 0) return 1.0;
    return deltaSize / originalSize;
  }

  bool get isComplete => totalChunks > 0 && uploadedChunks >= totalChunks;
}

class IncrementalSyncService {
  IncrementalSyncService();

  final RdiffService _rdiff = RdiffService();
  final E2ECryptoService _cryptoService = getIt<E2ECryptoService>();

  /// 分块大小（64KB）—— 借鉴 tus.io 协议的默认分块大小
  /// 选择 64KB 的原因：
  /// - 太小：HTTP 请求开销占比过高
  /// - 太大：单块失败重传成本高
  static const int chunkSize = 64 * 1024;

  /// SharedPreferences 键名前缀
  static const String _keySession = 'incremental_sync_session';
  static const String _keyServerUrl = syncServerUrlKey;
  static const String _keyAuthToken = syncAuthTokenKey;

  /// 当前活跃的同步会话（从持久化存储恢复）
  SyncSession? _activeSession;
  SyncSession? get activeSession => _activeSession;

  /// 初始化：从持久化存储恢复未完成的同步会话
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keySession);
    if (json != null) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        _activeSession = SyncSession.fromJson(map);
      } catch (_) {
        // 损坏的会话数据，清除
        await prefs.remove(_keySession);
        _activeSession = null;
      }
    }
  }

  /// 是否有未完成的同步会话可恢复
  bool get hasResumableSession =>
      _activeSession != null && !_activeSession!.isComplete;

  // ============================================================
  // 增量推送（Push）
  // ============================================================

  /// 增量推送数据
  ///
  /// 流程：
  /// 1. 若无活跃会话：从远端获取签名 → 计算 delta → 创建会话
  /// 2. 若有活跃会话：复用已计算的 delta 和已上传的块进度
  /// 3. 分块上传 delta 数据，跳过已完成的块
  /// 4. 全部块上传完成后，通知服务端合并并清除会话
  Future<IncrementalSyncResult> pushIncremental(
    Uint8List newData, {
    bool encrypt = true,
  }) async {
    // P0 修复: 服务端未实现增量同步端点（/sync/signatures, /delta, /chunk,
    // /commit, /abort），调用必然返回 404。在此明确返回失败，避免误导用户。
    // 后续应在 sync-server 实现这些端点后移除此检查。
    return const IncrementalSyncResult(
      success: false,
      error: '增量同步暂不可用：服务端未实现相关端点，请使用全量同步',
    );
  }

  Future<IncrementalSyncResult> _pushIncrementalImpl(
    Uint8List newData, {
    bool encrypt = true,
  }) async {
    try {
      // 加密数据（在增量计算前加密，确保端到端加密语义）
      Uint8List dataToSync;
      if (encrypt && _isCryptoReady()) {
        final encrypted = _cryptoService.encryptSyncData(newData);
        if (encrypted == null) {
          return const IncrementalSyncResult(
            success: false,
            error: '加密失败',
          );
        }
        dataToSync = encrypted;
      } else {
        dataToSync = newData;
      }

      // 获取或创建同步会话
      SyncSession session;
      Uint8List deltaBytes;

      if (_activeSession != null && !_activeSession!.isComplete) {
        // 恢复未完成的会话
        session = _activeSession!;
        // 重新计算 delta（本地数据可能已变化）
        deltaBytes = await _computeDelta(dataToSync, session);
      } else {
        // 创建新会话
        final sessionId = _generateSessionId();
        final remoteSignatures = await _fetchRemoteSignatures();
        final sigsBase64 = remoteSignatures != null
            ? base64Encode(_rdiff.encodeSignatures(remoteSignatures))
            : null;

        deltaBytes = await _computeDelta(dataToSync, null);
        session = SyncSession(
          sessionId: sessionId,
          remoteSignaturesBase64: sigsBase64,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }

      // 分块上传
      final chunks = _splitIntoChunks(deltaBytes);
      session = session.copyWith(
        totalChunks: chunks.length,
        updatedAt: DateTime.now(),
      );

      int uploadedThisRound = 0;
      for (int i = 0; i < chunks.length; i++) {
        if (session.completedChunks.contains(i)) continue;

        final success = await _uploadChunk(
          sessionId: session.sessionId,
          chunkIndex: i,
          totalChunks: chunks.length,
          data: chunks[i],
        );

        if (success) {
          session = session.copyWith(
            completedChunks: {...session.completedChunks, i},
            updatedAt: DateTime.now(),
          );
          uploadedThisRound++;
          await _persistSession(session);
        } else {
          // 上传失败，保存当前进度并返回
          _activeSession = session;
          await _persistSession(session);
          return IncrementalSyncResult(
            success: false,
            originalSize: dataToSync.length,
            deltaSize: deltaBytes.length,
            uploadedChunks: session.completedChunks.length,
            totalChunks: chunks.length,
            error: '分块上传失败，已保存进度可断点续传',
            session: session,
          );
        }
      }

      // 所有块上传完成，通知服务端合并
      final committed = await _commitSession(session.sessionId);
      if (!committed) {
        _activeSession = session;
        return IncrementalSyncResult(
          success: false,
          originalSize: dataToSync.length,
          deltaSize: deltaBytes.length,
          uploadedChunks: session.completedChunks.length,
          totalChunks: chunks.length,
          error: '服务端合并失败',
          session: session,
        );
      }

      // 更新远端签名（供下次增量计算使用）
      final newSignatures = _rdiff.calculateSignatures(dataToSync);
      await _updateRemoteSignatures(newSignatures);

      // 清除会话
      await _clearSession();
      _activeSession = null;

      return IncrementalSyncResult(
        success: true,
        originalSize: dataToSync.length,
        deltaSize: deltaBytes.length,
        uploadedChunks: uploadedThisRound,
        totalChunks: chunks.length,
      );
    } catch (e) {
      return IncrementalSyncResult(
        success: false,
        error: e.toString(),
        session: _activeSession,
      );
    }
  }

  // ============================================================
  // 增量拉取（Pull）
  // ============================================================

  /// 增量拉取数据
  ///
  /// 流程：
  /// 1. 发送本地数据的签名到远端
  /// 2. 远端计算 delta 并返回
  /// 3. 本地应用 patch 重建新数据
  Future<IncrementalSyncResult> pullIncremental(
    Uint8List localData, {
    bool decrypt = true,
  }) async {
    try {
      // 计算本地签名并发送到远端
      final localSignatures = _rdiff.calculateSignatures(localData);
      final sigsEncoded = _rdiff.encodeSignatures(localSignatures);

      // 请求远端 delta
      final deltaBytes = await _fetchRemoteDelta(sigsEncoded);
      if (deltaBytes == null || deltaBytes.isEmpty) {
        // 无新数据
        return IncrementalSyncResult(
          success: true,
          originalSize: localData.length,
          deltaSize: 0,
        );
      }

      // 应用 patch 重建数据
      final patchedData = _rdiff.applyPatch(localData, deltaBytes);

      // 解密
      Uint8List resultData;
      if (decrypt && _isCryptoReady()) {
        final decrypted = _cryptoService.decryptSyncData(patchedData);
        if (decrypted == null) {
          return const IncrementalSyncResult(
            success: false,
            error: '解密失败',
          );
        }
        resultData = decrypted;
      } else {
        resultData = patchedData;
      }

      return IncrementalSyncResult(
        success: true,
        originalSize: localData.length,
        deltaSize: deltaBytes.length,
      );
    } catch (e) {
      return IncrementalSyncResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // 会话管理
  // ============================================================

  /// 放弃当前会话（清除所有进度）
  Future<void> abortSession() async {
    if (_activeSession != null) {
      await _abortRemoteSession(_activeSession!.sessionId);
    }
    await _clearSession();
    _activeSession = null;
  }

  /// 获取当前同步进度
  double get currentProgress {
    if (_activeSession == null) return 0.0;
    return _activeSession!.progress;
  }

  // ============================================================
  // 内部方法 —— 增量计算
  // ============================================================

  Future<Uint8List> _computeDelta(
    Uint8List newData,
    SyncSession? session,
  ) async {
    // 若会话中保存了远端签名，使用增量计算
    if (session?.remoteSignaturesBase64 != null) {
      try {
        final sigsBytes = base64Decode(session!.remoteSignaturesBase64!);
        final signatures = _rdiff.decodeSignatures(sigsBytes);
        if (signatures.isNotEmpty) {
          return _rdiff.calculateDelta(newData, signatures);
        }
      } catch (_) {
        // 签名解码失败，降级为全量传输
      }
    }

    // 无可用签名 → 尝试从远端获取
    final remoteSignatures = await _fetchRemoteSignatures();
    if (remoteSignatures != null && remoteSignatures.isNotEmpty) {
      return _rdiff.calculateDelta(newData, remoteSignatures);
    }

    // 远端无签名（首次同步）→ 全量作为 literal 传输
    return _rdiff.calculateDelta(newData, []);
  }

  // ============================================================
  // 内部方法 —— 分块
  // ============================================================

  List<Uint8List> _splitIntoChunks(Uint8List data) {
    if (data.isEmpty) return [Uint8List(0)];
    final chunks = <Uint8List>[];
    for (int i = 0; i < data.length; i += chunkSize) {
      final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
      chunks.add(Uint8List.sublistView(data, i, end));
    }
    return chunks;
  }

  // ============================================================
  // 内部方法 —— 网络通信
  // ============================================================

  Future<String> _getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyServerUrl) ?? defaultSyncServerUrl;
  }

  Future<String?> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAuthToken);
  }

  Map<String, String> _buildHeaders({bool octetStream = false}) {
    final headers = <String, String>{};
    if (octetStream) {
      headers['Content-Type'] = 'application/octet-stream';
    }
    return headers;
  }

  Future<void> _addAuthHeader(Map<String, String> headers) async {
    final token = await _getAuthToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
  }

  /// 从远端获取数据签名（用于增量计算基准）
  Future<List<RdiffBlockSignature>?> _fetchRemoteSignatures() async {
    try {
      final serverUrl = await _getServerUrl();
      final headers = _buildHeaders();
      await _addAuthHeader(headers);

      final uri = Uri.parse('$serverUrl/api/v1/sync/signatures');
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 204 || response.statusCode == 404) {
        return null; // 远端无数据（首次同步）
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _rdiff.decodeSignatures(response.bodyBytes);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 上传远端签名（供下次增量计算使用）
  Future<void> _updateRemoteSignatures(
    List<RdiffBlockSignature> signatures,
  ) async {
    try {
      final serverUrl = await _getServerUrl();
      final headers = _buildHeaders(octetStream: true);
      await _addAuthHeader(headers);

      final uri = Uri.parse('$serverUrl/api/v1/sync/signatures');
      final body = _rdiff.encodeSignatures(signatures);
      await http.put(uri, headers: headers, body: body);
    } catch (_) {
      // 签名更新失败不影响同步正确性（下次降级为全量）
    }
  }

  /// 请求远端计算并返回 delta
  Future<Uint8List?> _fetchRemoteDelta(Uint8List localSignatures) async {
    try {
      final serverUrl = await _getServerUrl();
      final headers = _buildHeaders(octetStream: true);
      await _addAuthHeader(headers);

      final uri = Uri.parse('$serverUrl/api/v1/sync/delta');
      final response = await http.post(uri, headers: headers, body: localSignatures);

      if (response.statusCode == 204) return null;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 上传单个分块
  Future<bool> _uploadChunk({
    required String sessionId,
    required int chunkIndex,
    required int totalChunks,
    required Uint8List data,
  }) async {
    try {
      final serverUrl = await _getServerUrl();
      final headers = _buildHeaders(octetStream: true);
      await _addAuthHeader(headers);

      // 借鉴 tus.io 协议的 Upload-Offset / Upload-Length 头部
      headers['X-Session-Id'] = sessionId;
      headers['X-Chunk-Index'] = chunkIndex.toString();
      headers['X-Total-Chunks'] = totalChunks.toString();

      final uri = Uri.parse('$serverUrl/api/v1/sync/chunk');
      final response = await http.post(uri, headers: headers, body: data);

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// 通知服务端合并所有分块并完成同步
  Future<bool> _commitSession(String sessionId) async {
    try {
      final serverUrl = await _getServerUrl();
      final headers = _buildHeaders();
      await _addAuthHeader(headers);

      final uri = Uri.parse('$serverUrl/api/v1/sync/commit?session=$sessionId');
      final response = await http.post(uri, headers: headers);

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// 通知服务端放弃会话
  Future<void> _abortRemoteSession(String sessionId) async {
    try {
      final serverUrl = await _getServerUrl();
      final headers = _buildHeaders();
      await _addAuthHeader(headers);

      final uri = Uri.parse('$serverUrl/api/v1/sync/abort?session=$sessionId');
      await http.delete(uri, headers: headers);
    } catch (_) {
      // 忽略放弃失败
    }
  }

  // ============================================================
  // 内部方法 —— 会话持久化
  // ============================================================

  Future<void> _persistSession(SyncSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySession, jsonEncode(session.toJson()));
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySession);
  }

  // ============================================================
  // 内部方法 —— 辅助
  // ============================================================

  bool _isCryptoReady() {
    return _cryptoService.state.status != E2ECryptoStatus.notConfigured;
  }

  String _generateSessionId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch;
    return 'sync_${now}_${random.toRadixString(16)}';
  }

  /// 释放资源
  void dispose() {
    _activeSession = null;
  }
}
