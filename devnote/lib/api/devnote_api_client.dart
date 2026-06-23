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
}
