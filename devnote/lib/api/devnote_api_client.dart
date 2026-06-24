/// DevNote 统一 API 客户端
///
/// P2-9: OpenAPI 契约驱动客户端生成
///
/// 本文件是 Flutter 端访问 Go 服务的统一入口，封装了由 openapi-generator
/// 自动生成的 sync-server 和 business-server 客户端。
///
/// ## 使用方式
///
/// ```dart
/// final apiClient = DevNoteApiClient(
///   syncServerUrl: 'https://sync.devnote.app',
///   businessServerUrl: 'https://business.devnote.app',
///   authToken: 'jwt-token-here',
/// );
///
/// // 同步服务
/// final status = await apiClient.sync.getSyncStatus(deviceId: 'device-1');
///
/// // 业务服务
/// final metadata = await apiClient.metadata.listMetadata();
/// ```
///
/// ## 迁移指南
///
/// 现有手写 HTTP 调用应逐步迁移到本客户端：
/// 1. 将 `http.post(Uri.parse('$serverUrl/api/v1/sync/push'), ...)` 替换为
///    `apiClient.sync.pushSync(pushRequest: ...)`
/// 2. 类型安全的请求/响应模型自动从 OpenAPI 规范生成
/// 3. JWT 认证自动注入，无需手动添加 Authorization header

import 'dart:convert';
import 'dart:typed_data';

import 'package:devnote_sync_api/api.dart';
import 'package:devnote_business_api/api.dart' as devnote_business_api;

/// DevNote 统一 API 客户端
///
/// 封装 sync-server 和 business-server 的生成客户端，
/// 提供统一的认证和服务器地址配置。
///
/// 由于两个生成包都定义了同名类型（ApiClient、HealthApi 等），
/// business-server 包通过 `as devnote_business_api` 前缀导入以消除歧义。
class DevNoteApiClient {
  DevNoteApiClient({
    required String syncServerUrl,
    required String businessServerUrl,
    String? authToken,
  })  : _syncServerUrl = syncServerUrl,
        _businessServerUrl = businessServerUrl,
        _authToken = authToken {
    _initClients();
  }

  final String _syncServerUrl;
  final String _businessServerUrl;
  String? _authToken;

  // 生成的 API 客户端实例
  late ApiClient _syncApiClient;
  late devnote_business_api.ApiClient _businessApiClient;

  // API 接口（延迟初始化，确保认证已配置）
  SyncApi? _sync;
  AuthApi? _auth;
  SrpAuthApi? _srpAuth;
  HealthApi? _syncHealth;

  devnote_business_api.MetadataApi? _metadata;
  devnote_business_api.TagsApi? _tags;
  devnote_business_api.FoldersApi? _folders;
  devnote_business_api.KnowledgeApi? _knowledge;
  devnote_business_api.ValidationApi? _validation;
  devnote_business_api.HealthApi? _businessHealth;

  void _initClients() {
    _syncApiClient = ApiClient(basePath: _syncServerUrl);
    _businessApiClient = devnote_business_api.ApiClient(basePath: _businessServerUrl);

    // 通过 defaultHeader 注入 JWT，避免两个包的 Authentication 类型不兼容
    if (_authToken != null && _authToken!.isNotEmpty) {
      _syncApiClient.addDefaultHeader('Authorization', 'Bearer $_authToken');
      _businessApiClient.addDefaultHeader('Authorization', 'Bearer $_authToken');
    }
  }

  /// 更新认证令牌（登录/刷新 token 后调用）
  void updateAuthToken(String? token) {
    _authToken = token;
    _initClients();
    // 重置延迟初始化的 API 接口
    _sync = null;
    _auth = null;
    _srpAuth = null;
    _syncHealth = null;
    _metadata = null;
    _tags = null;
    _folders = null;
    _knowledge = null;
    _validation = null;
    _businessHealth = null;
  }

  /// 轻量级设置认证令牌（不重建 ApiClient，仅更新默认请求头）
  ///
  /// P1-1: 在每次同步 API 调用前调用，确保 token 最新。
  /// 与 [updateAuthToken] 不同，此方法不重建 ApiClient 实例，
  /// 仅更新默认请求头中的 Authorization 字段，性能更优。
  void setAuthToken(String? token) {
    _authToken = token;
    if (token != null && token.isNotEmpty) {
      _syncApiClient.addDefaultHeader('Authorization', 'Bearer $token');
      _businessApiClient.addDefaultHeader('Authorization', 'Bearer $token');
    } else {
      _syncApiClient.defaultHeaderMap.remove('Authorization');
      _businessApiClient.defaultHeaderMap.remove('Authorization');
    }
  }

  // ── Sync Server API ──────────────────────────────────────────

  /// 同步操作 API（push/pull/status/conflict）
  SyncApi get sync => _sync ??= SyncApi(_syncApiClient);

  /// 标准认证 API（register/login/refresh/logout）
  AuthApi get auth => _auth ??= AuthApi(_syncApiClient);

  /// SRP 零知识认证 API
  SrpAuthApi get srpAuth => _srpAuth ??= SrpAuthApi(_syncApiClient);

  /// Sync Server 健康检查
  HealthApi get syncHealth => _syncHealth ??= HealthApi(_syncApiClient);

  // ── Business Server API ──────────────────────────────────────

  /// 笔记元数据 API（CRUD/搜索/批量操作）
  devnote_business_api.MetadataApi get metadata =>
      _metadata ??= devnote_business_api.MetadataApi(_businessApiClient);

  /// 标签 API（层级/合并/拆分/统计）
  devnote_business_api.TagsApi get tags =>
      _tags ??= devnote_business_api.TagsApi(_businessApiClient);

  /// 文件夹 API（树形/移动/复制/路径解析）
  devnote_business_api.FoldersApi get folders =>
      _folders ??= devnote_business_api.FoldersApi(_businessApiClient);

  /// 知识图谱 API（关系/图计算/推荐/最短路径）
  devnote_business_api.KnowledgeApi get knowledge =>
      _knowledge ??= devnote_business_api.KnowledgeApi(_businessApiClient);

  /// 校验规则 API（规则 CRUD/实体校验）
  devnote_business_api.ValidationApi get validation =>
      _validation ??= devnote_business_api.ValidationApi(_businessApiClient);

  /// Business Server 健康检查
  devnote_business_api.HealthApi get businessHealth =>
      _businessHealth ??= devnote_business_api.HealthApi(_businessApiClient);

  // ============================================================
  // P1-1: Sync 包装方法
  // ------------------------------------------------------------
  // 适配现有手写 HTTP 调用与生成 API 之间的差异，
  // 提供 Service 层可直接使用的简化接口。
  // ============================================================

  /// 推送同步变更到服务端
  ///
  /// 包装生成的 [SyncApi.pushChanges]，构造类型安全的 [PushRequest]。
  /// 成功时返回 [PushResponse]，失败时抛出 [ApiException]。
  Future<PushResponse?> pushSync({
    required String deviceId,
    required List<SyncRecordInput> records,
  }) async {
    final request = PushRequest(deviceId: deviceId, records: records);
    return sync.pushChanges(request);
  }

  /// 拉取同步变更
  ///
  /// 包装生成的 [SyncApi.pullChanges]，构造类型安全的 [PullRequest]。
  /// 成功时返回 [PullResponse]，失败时抛出 [ApiException]。
  /// 无新数据时返回 null（服务端返回 204）。
  Future<PullResponse?> pullSync({
    required String deviceId,
    int? sinceVersion,
    int? limit,
  }) async {
    final request = PullRequest(
      deviceId: deviceId,
      sinceVersion: sinceVersion,
    );
    return sync.pullChanges(request, limit: limit);
  }

  /// 上报冲突解决结果（best-effort）
  ///
  /// P1-1: 该端点 `/api/v1/sync/conflicts/resolve` 未在 OpenAPI 规范中定义，
  /// 故直接使用底层 http Client 调用，而非生成的 [SyncApi.resolveConflict]
  /// （后者对应 `/api/v1/sync/resolve-conflict`，语义不同）。
  /// 失败时抛出异常，由调用方捕获并记录日志。
  Future<void> reportConflictResolution({
    required String conflictId,
    required String resolution,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = Uri.parse('$_syncServerUrl/api/v1/sync/conflicts/resolve');
    final headers = _buildRawHeaders(jsonBody: true);
    final body = jsonEncode({
      'conflict_id': conflictId,
      'resolution': resolution,
    });
    await _syncApiClient.client
        .post(uri, headers: headers, body: body)
        .timeout(timeout);
  }

  // ============================================================
  // P1-1: 增量同步端点（未在 OpenAPI 规范中生成）
  // ------------------------------------------------------------
  // 以下端点用于增量同步（rsync 算法 + 断点续传），
  // 服务端尚未实现，但客户端保留调用接口。
  // 直接使用底层 http Client，因为生成的 SyncApi 不包含这些端点。
  // ============================================================

  /// 获取远端数据签名（用于增量计算基准）
  ///
  /// 返回签名字节数据；远端无数据（204/404）或非 2xx 时返回 null。
  Future<Uint8List?> fetchRemoteSignatures() async {
    final uri = Uri.parse('$_syncServerUrl/api/v1/sync/signatures');
    final headers = _buildRawHeaders();
    final response = await _syncApiClient.client.get(uri, headers: headers);
    if (response.statusCode == 204 || response.statusCode == 404) {
      return null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    return null;
  }

  /// 上传远端签名（供下次增量计算使用）
  Future<void> updateRemoteSignatures(Uint8List body) async {
    final uri = Uri.parse('$_syncServerUrl/api/v1/sync/signatures');
    final headers = _buildRawHeaders(octetStream: true);
    await _syncApiClient.client.put(uri, headers: headers, body: body);
  }

  /// 请求远端计算并返回 delta
  ///
  /// 返回 delta 字节数据；远端无新数据（204）或非 2xx 时返回 null。
  Future<Uint8List?> fetchRemoteDelta(Uint8List localSignatures) async {
    final uri = Uri.parse('$_syncServerUrl/api/v1/sync/delta');
    final headers = _buildRawHeaders(octetStream: true);
    final response = await _syncApiClient.client
        .post(uri, headers: headers, body: localSignatures);
    if (response.statusCode == 204) return null;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    return null;
  }

  /// 上传单个分块
  ///
  /// 借鉴 tus.io 协议的 Upload-Offset / Upload-Length 头部。
  /// 返回是否上传成功（2xx 状态码）。
  Future<bool> uploadChunk({
    required String sessionId,
    required int chunkIndex,
    required int totalChunks,
    required Uint8List data,
  }) async {
    final uri = Uri.parse('$_syncServerUrl/api/v1/sync/chunk');
    final headers = _buildRawHeaders(octetStream: true);
    headers['X-Session-Id'] = sessionId;
    headers['X-Chunk-Index'] = chunkIndex.toString();
    headers['X-Total-Chunks'] = totalChunks.toString();
    final response =
        await _syncApiClient.client.post(uri, headers: headers, body: data);
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  /// 通知服务端合并所有分块并完成同步
  ///
  /// 返回是否合并成功（2xx 状态码）。
  Future<bool> commitSession(String sessionId) async {
    final uri =
        Uri.parse('$_syncServerUrl/api/v1/sync/commit?session=$sessionId');
    final headers = _buildRawHeaders();
    final response = await _syncApiClient.client.post(uri, headers: headers);
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  /// 通知服务端放弃会话
  Future<void> abortRemoteSession(String sessionId) async {
    final uri =
        Uri.parse('$_syncServerUrl/api/v1/sync/abort?session=$sessionId');
    final headers = _buildRawHeaders();
    await _syncApiClient.client.delete(uri, headers: headers);
  }

  /// 构建原始 HTTP 请求头（含认证）
  ///
  /// 用于未在 OpenAPI 规范中生成的端点，手动构建请求头。
  Map<String, String> _buildRawHeaders({
    bool octetStream = false,
    bool jsonBody = false,
  }) {
    final headers = <String, String>{};
    if (octetStream) {
      headers['Content-Type'] = 'application/octet-stream';
    } else if (jsonBody) {
      headers['Content-Type'] = 'application/json';
    }
    if (_authToken != null && _authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }
}
