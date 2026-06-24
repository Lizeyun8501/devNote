/// 应用全局配置常量与运行时配置管理
///
/// 集中管理服务器地址、SharedPreferences 键名等散落常量的单一来源。
/// P3-2 修复: 消除硬编码服务器地址（sync.devnote.app）的 7 处分散引用。
///
/// P2-4 扩展: 在原有常量基础上新增 [AppConfig] 单例类，封装 SharedPreferences
/// 读写，提供强类型 getter/setter，并通过 ChangeNotifier 支持配置变更通知，
/// 让 UI 通过 ListenableBuilder/AnimatedBuilder 响应配置变化。
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 默认同步服务器地址
const String defaultSyncServerUrl = 'https://sync.devnote.app';

/// 默认业务服务器地址
/// P1-1: DevNoteApiClient 注册时需要 businessServerUrl
const String defaultBusinessServerUrl = 'https://business.devnote.app';

/// 默认实时协作 WebSocket 地址
const String defaultRealtimeServerUrl = 'wss://sync.devnote.app/realtime';

/// SharedPreferences 中存储同步服务器地址的键名
const String syncServerUrlKey = 'sync_server_url';

/// SharedPreferences 中存储认证令牌的键名
const String syncAuthTokenKey = 'sync_auth_token';

/// SharedPreferences 中存储业务服务器地址的键名
const String businessServerUrlKey = 'business_server_url';

/// SharedPreferences 中存储暗黑模式开关的键名
const String darkModeKey = 'settings.dark_mode';

/// SharedPreferences 中存储字体大小的键名
const String fontSizeKey = 'settings.font_size';

/// SharedPreferences 中存储自动保存开关的键名
const String autoSaveKey = 'settings.auto_save';

/// SharedPreferences 中存储 Sentry 用户同意状态的键名
/// 与 sentry_config.dart 中的 _consentPrefKey 保持一致以实现向后兼容
const String sentryUserConsentKey = 'sentry.user_consent';

/// P1 修复 (2-F): S3 兼容存储配置键名
const String s3EndpointKey = 's3_endpoint';
const String s3BucketKey = 's3_bucket';
const String s3AccessKeyKey = 's3_access_key';
const String s3SecretKeyKey = 's3_secret_key';
const String s3UseSSLKey = 's3_use_ssl';

/// 默认字体大小（px）
const double defaultFontSize = 14.0;

/// 应用运行时配置管理类（单例）
///
/// 封装 SharedPreferences 读写，提供强类型 getter/setter，
/// 并通过 [ChangeNotifier] 支持配置变更通知，让 UI 响应配置变化。
///
/// 设计要点：
/// - 单例模式：通过 [instance] 获取唯一实例，并通过 getIt 注入
/// - 内存缓存：[init] 后将所有配置值加载到内存，getter 直接返回缓存值
/// - 持久化：setter 同步写入 SharedPreferences 并通知监听者
/// - 变更通知：继承 [ChangeNotifier]，UI 可通过 ListenableBuilder 监听
///
/// 使用方式：
/// ```dart
/// // 1. 应用启动时初始化（在 setupDependencies 中完成）
/// await AppConfig.instance.init();
///
/// // 2. 通过 getIt 获取单例
/// final config = getIt<AppConfig>();
///
/// // 3. 读取配置
/// final url = config.syncServerUrl;
///
/// // 4. 修改配置（自动持久化 + 通知监听者）
/// config.darkMode = true;
///
/// // 5. UI 监听配置变化
/// ListenableBuilder(
///   listenable: getIt<AppConfig>(),
///   builder: (context, _) => Text('字体: ${config.fontSize}'),
/// )
/// ```
class AppConfig extends ChangeNotifier {
  AppConfig._internal();

  /// 单例实例
  static final AppConfig _instance = AppConfig._internal();

  /// 获取单例实例
  static AppConfig get instance => _instance;

  /// SharedPreferences 实例，由 [init] 初始化
  SharedPreferences? _prefs;

  // 配置值内存缓存，避免每次读取都访问 SharedPreferences
  String _syncServerUrl = defaultSyncServerUrl;
  String _businessServerUrl = defaultBusinessServerUrl;
  bool _darkMode = false;
  double _fontSize = defaultFontSize;
  bool _autoSave = true;
  bool _sentryUserConsent = false;
  String? _syncAuthToken;
  // P1 修复 (2-F): S3 兼容存储配置
  String _s3Endpoint = '';
  String _s3Bucket = '';
  String _s3AccessKey = '';
  String _s3SecretKey = '';
  bool _s3UseSSL = true;

  /// 是否已初始化（[init] 是否已成功执行）
  bool get isInitialized => _prefs != null;

  /// 初始化 SharedPreferences 实例并加载持久化的配置值
  ///
  /// 必须在使用任何 getter/setter 之前调用。通常在 [setupDependencies]
  /// 中调用，确保后续所有消费者拿到的是已加载的配置。
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _syncServerUrl =
        _prefs!.getString(syncServerUrlKey) ?? defaultSyncServerUrl;
    _businessServerUrl =
        _prefs!.getString(businessServerUrlKey) ?? defaultBusinessServerUrl;
    _darkMode = _prefs!.getBool(darkModeKey) ?? false;
    _fontSize = _prefs!.getDouble(fontSizeKey) ?? defaultFontSize;
    _autoSave = _prefs!.getBool(autoSaveKey) ?? true;
    _sentryUserConsent = _prefs!.getBool(sentryUserConsentKey) ?? false;
    _syncAuthToken = _prefs!.getString(syncAuthTokenKey);
    // P1 修复 (2-F): 加载 S3 存储配置
    _s3Endpoint = _prefs!.getString(s3EndpointKey) ?? '';
    _s3Bucket = _prefs!.getString(s3BucketKey) ?? '';
    _s3AccessKey = _prefs!.getString(s3AccessKeyKey) ?? '';
    _s3SecretKey = _prefs!.getString(s3SecretKeyKey) ?? '';
    _s3UseSSL = _prefs!.getBool(s3UseSSLKey) ?? true;
  }

  /// 同步服务器地址（默认 [defaultSyncServerUrl]）
  String get syncServerUrl => _syncServerUrl;

  set syncServerUrl(String value) {
    if (_syncServerUrl == value) return;
    _syncServerUrl = value;
    _prefs?.setString(syncServerUrlKey, value);
    notifyListeners();
  }

  /// 业务服务器地址（默认 [defaultBusinessServerUrl]）
  String get businessServerUrl => _businessServerUrl;

  set businessServerUrl(String value) {
    if (_businessServerUrl == value) return;
    _businessServerUrl = value;
    _prefs?.setString(businessServerUrlKey, value);
    notifyListeners();
  }

  /// 暗黑模式开关（默认 false）
  bool get darkMode => _darkMode;

  set darkMode(bool value) {
    if (_darkMode == value) return;
    _darkMode = value;
    _prefs?.setBool(darkModeKey, value);
    notifyListeners();
  }

  /// 字体大小（默认 [defaultFontSize]，单位 px）
  double get fontSize => _fontSize;

  set fontSize(double value) {
    if (_fontSize == value) return;
    _fontSize = value;
    _prefs?.setDouble(fontSizeKey, value);
    notifyListeners();
  }

  /// 自动保存开关（默认 true）
  bool get autoSave => _autoSave;

  set autoSave(bool value) {
    if (_autoSave == value) return;
    _autoSave = value;
    _prefs?.setBool(autoSaveKey, value);
    notifyListeners();
  }

  /// Sentry 用户同意状态（默认 false）
  ///
  /// 遵循 GDPR/CCPA 隐私合规要求，用户显式同意后才上报。
  /// 与 [sentry_config.dart] 中的持久化键保持一致。
  bool get sentryUserConsent => _sentryUserConsent;

  set sentryUserConsent(bool value) {
    if (_sentryUserConsent == value) return;
    _sentryUserConsent = value;
    _prefs?.setBool(sentryUserConsentKey, value);
    notifyListeners();
  }

  /// 同步认证令牌（可空，未登录时为 null）
  ///
  /// 设为 null 时会从 SharedPreferences 中移除该键。
  String? get syncAuthToken => _syncAuthToken;

  set syncAuthToken(String? value) {
    if (_syncAuthToken == value) return;
    _syncAuthToken = value;
    if (value == null) {
      _prefs?.remove(syncAuthTokenKey);
    } else {
      _prefs?.setString(syncAuthTokenKey, value);
    }
    notifyListeners();
  }

  // ── P1 修复 (2-F): S3 兼容存储配置 ──────────────────────────

  /// S3 是否已配置（endpoint + bucket + accessKey + secretKey 均非空）
  bool get isS3Configured =>
      _s3Endpoint.isNotEmpty &&
      _s3Bucket.isNotEmpty &&
      _s3AccessKey.isNotEmpty &&
      _s3SecretKey.isNotEmpty;

  String get s3Endpoint => _s3Endpoint;
  set s3Endpoint(String value) {
    if (_s3Endpoint == value) return;
    _s3Endpoint = value;
    _prefs?.setString(s3EndpointKey, value);
    notifyListeners();
  }

  String get s3Bucket => _s3Bucket;
  set s3Bucket(String value) {
    if (_s3Bucket == value) return;
    _s3Bucket = value;
    _prefs?.setString(s3BucketKey, value);
    notifyListeners();
  }

  String get s3AccessKey => _s3AccessKey;
  set s3AccessKey(String value) {
    if (_s3AccessKey == value) return;
    _s3AccessKey = value;
    _prefs?.setString(s3AccessKeyKey, value);
    notifyListeners();
  }

  String get s3SecretKey => _s3SecretKey;
  set s3SecretKey(String value) {
    if (_s3SecretKey == value) return;
    _s3SecretKey = value;
    _prefs?.setString(s3SecretKeyKey, value);
    notifyListeners();
  }

  bool get s3UseSSL => _s3UseSSL;
  set s3UseSSL(bool value) {
    if (_s3UseSSL == value) return;
    _s3UseSSL = value;
    _prefs?.setBool(s3UseSSLKey, value);
    notifyListeners();
  }
}
