// 统一配置管理模块 —— 借鉴 1Password 的集中配置管理思想
// 来源: https://1password.com/
// 借鉴内容: 将所有分散在代码各处的用户配置（主题、字体、同步、加密、Sentry 同意等）
// 统一收敛到一个强类型的中心化管理类中，避免"配置散落"导致的维护困难与不一致。
//
// 设计要点:
// 1. 单例模式: 全局仅一个配置实例，通过 getIt 注册，便于在任意位置访问。
// 2. SharedPreferences 持久化: 所有写入操作立即落盘，重启后状态保持一致。
// 3. 强类型 getter/setter: 编译期即可发现配置访问错误，避免字符串 key 散落。
// 4. 集中键名管理: 所有 SharedPreferences key 在类内集中声明，杜绝拼写错误。

import 'package:shared_preferences/shared_preferences.dart';

/// 应用统一配置管理类
///
/// 提供所有用户级配置的强类型访问入口，支持从 SharedPreferences 读取/写入。
/// 设计灵感来自 1Password —— 集中、可审计、类型安全。
class AppConfig {
  AppConfig._();

  // ---------- 单例 ----------
  static final AppConfig _instance = AppConfig._();

  /// 获取全局唯一实例
  static AppConfig get instance => _instance;

  // ---------- SharedPreferences key 集中管理 ----------
  // 借鉴 1Password 集中化管理配置项的设计，避免字符串 key 散落在代码各处。
  static const String _kDarkMode = 'app.darkMode';
  static const String _kFontSize = 'app.fontSize';
  static const String _kAutoSave = 'app.autoSave';
  static const String _kDefaultEditMode = 'app.defaultEditMode';
  static const String _kSyncServerUrl = 'sync.serverUrl';
  static const String _kSyncAuthToken = 'sync.authToken';
  static const String _kLastSyncTime = 'sync.lastSyncTime';
  static const String _kPendingChanges = 'sync.pendingChanges';
  static const String _kSentryUserConsent = 'sentry.userConsent';
  static const String _kLanguage = 'app.language';
  static const String _kFirstLaunch = 'app.firstLaunch';
  static const String _kEncryptionEnabled = 'security.encryptionEnabled';

  // ---------- 默认值 ----------
  static const bool _defaultDarkMode = false;
  static const double _defaultFontSize = 14.0;
  static const bool _defaultAutoSave = true;
  static const String _defaultEditMode = 'wysiwyg';
  static const String _defaultSyncServerUrl = '';
  static const String _defaultSyncAuthToken = '';
  static const bool _defaultSentryUserConsent = false;
  static const String _defaultLanguage = 'system';
  static const bool _defaultFirstLaunch = true;
  static const bool _defaultEncryptionEnabled = false;

  SharedPreferences? _prefs;

  /// 初始化 —— 在应用启动阶段调用一次
  ///
  /// 必须在 runApp 之前调用 setupDependencies() 时执行，确保后续访问共享配置可用。
  Future<void> init({SharedPreferences? prefs}) async {
    _prefs = prefs ?? await SharedPreferences.getInstance();
  }

  SharedPreferences get _p {
    final p = _prefs;
    if (p == null) {
      throw StateError(
        'AppConfig 尚未初始化，请先在 main() 中调用 AppConfig.instance.init()',
      );
    }
    return p;
  }

  // ==================== 主题外观 ====================

  /// 是否启用深色模式
  bool get darkMode => _p.getBool(_kDarkMode) ?? _defaultDarkMode;
  set darkMode(bool value) => _p.setBool(_kDarkMode, value);

  /// 笔记正文字号（单位：pt）
  double get fontSize => _p.getDouble(_kFontSize) ?? _defaultFontSize;
  set fontSize(double value) => _p.setDouble(_kFontSize, value);

  // ==================== 编辑器行为 ====================

  /// 是否开启自动保存
  bool get autoSave => _p.getBool(_kAutoSave) ?? _defaultAutoSave;
  set autoSave(bool value) => _p.setBool(_kAutoSave, value);

  /// 默认编辑模式: "wysiwyg" | "markdown" | "raw"
  String get defaultEditMode =>
      _p.getString(_kDefaultEditMode) ?? _defaultEditMode;
  set defaultEditMode(String value) => _p.setString(_kDefaultEditMode, value);

  // ==================== 同步相关 ====================

  /// 同步服务器 URL
  String get syncServerUrl =>
      _p.getString(_kSyncServerUrl) ?? _defaultSyncServerUrl;
  set syncServerUrl(String value) => _p.setString(_kSyncServerUrl, value);

  /// 同步服务认证 Token —— 敏感字段，写入时需谨慎
  String get syncAuthToken =>
      _p.getString(_kSyncAuthToken) ?? _defaultSyncAuthToken;
  set syncAuthToken(String value) => _p.setString(_kSyncAuthToken, value);

  /// 上次同步时间（毫秒时间戳，0 表示从未同步）
  int get lastSyncTime => _p.getInt(_kLastSyncTime) ?? 0;
  set lastSyncTime(int value) => _p.setInt(_kLastSyncTime, value);

  /// 待同步变更条数
  int get pendingChanges => _p.getInt(_kPendingChanges) ?? 0;
  set pendingChanges(int value) => _p.setInt(_kPendingChanges, value);

  // ==================== 隐私 / 监控 ====================

  /// Sentry 用户同意状态 —— 遵循 GDPR/CCPA opt-in 原则
  bool get sentryUserConsent =>
      _p.getBool(_kSentryUserConsent) ?? _defaultSentryUserConsent;
  set sentryUserConsent(bool value) =>
      _p.setBool(_kSentryUserConsent, value);

  // ==================== 本地化 / 通用 ====================

  /// 语言: "system" | "zh" | "en"
  String get language => _p.getString(_kLanguage) ?? _defaultLanguage;
  set language(String value) => _p.setString(_kLanguage, value);

  /// 是否首次启动（用于 onboarding 流程判断）
  bool get isFirstLaunch =>
      _p.getBool(_kFirstLaunch) ?? _defaultFirstLaunch;
  set isFirstLaunch(bool value) => _p.setBool(_kFirstLaunch, value);

  /// 是否启用端到端加密
  bool get encryptionEnabled =>
      _p.getBool(_kEncryptionEnabled) ?? _defaultEncryptionEnabled;
  set encryptionEnabled(bool value) =>
      _p.setBool(_kEncryptionEnabled, value);

  // ==================== 维护方法 ====================

  /// 重置全部配置到默认值 —— 主要用于登出/切换账号场景
  Future<void> resetAll() async {
    await _p.remove(_kDarkMode);
    await _p.remove(_kFontSize);
    await _p.remove(_kAutoSave);
    await _p.remove(_kDefaultEditMode);
    await _p.remove(_kSyncServerUrl);
    await _p.remove(_kSyncAuthToken);
    await _p.remove(_kLastSyncTime);
    await _p.remove(_kPendingChanges);
    await _p.remove(_kSentryUserConsent);
    await _p.remove(_kLanguage);
    await _p.remove(_kFirstLaunch);
    await _p.remove(_kEncryptionEnabled);
  }
}
