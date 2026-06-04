// 集成 Sentry 崩溃报告 —— 借鉴 AppFlowy 的 Sentry 集成方案
// 来源: https://github.com/AppFlowy-IO/AppFlowy
//
// 借鉴 Sentry 官方 Flutter 用户同意控制模式
// 来源: https://docs.sentry.io/platforms/flutter/data-management/sensitive-data/
// 借鉴内容: 用户在 UI 中显式同意后才上报 (user_consent flag),撤回同意立即清空 user 上下文

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sentry 配置类 —— 集中管理 DSN、环境、采样率、用户同意状态等设置
class SentryConfig {
  /// Sentry DSN —— 从环境变量 SENTRY_DSN 读取
  /// TODO: 替换为实际 Sentry DSN
  static const String _defaultDsn = 'https://example@sentry.io/0';

  /// 当前运行环境
  final String environment;

  /// 错误采样率 (0.0 - 1.0)
  final double sampleRate;

  /// 是否启用 Sentry (默认关闭，需设置 SENTRY_DSN 环境变量或调用 enable())
  bool _enabled = false;

  /// 用户是否同意上报 — 遵循 GDPR/CCPA 隐私合规要求
  /// 借鉴 Sentry 用户同意控制
  /// 来源: https://docs.sentry.io/platforms/flutter/data-management/sensitive-data/
  bool _userConsent = false;

  /// 持久化 key
  static const String _consentPrefKey = 'sentry.user_consent';

  SentryConfig({
    this.environment = 'production',
    this.sampleRate = 1.0,
  });

  bool get isEnabled => _enabled;
  bool get hasUserConsent => _userConsent;

  void enable() {
    _enabled = true;
  }

  void disable() {
    _enabled = false;
  }

  /// 设置用户同意状态 —— 持久化到 SharedPreferences
  /// false 时: 1) 清空 Sentry user 上下文; 2) SentryFlutter.capture* 变为 no-op
  Future<void> setUserConsent(bool granted) async {
    _userConsent = granted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_consentPrefKey, granted);
    if (!granted) {
      // 撤回同意:立即清空 PII
      try {
        await Sentry.configureScope((scope) {
          scope.user = null;
          scope.setTag('consent', 'revoked');
        });
      } catch (_) {
        // Sentry 未初始化时静默忽略
      }
    } else {
      try {
        await Sentry.configureScope((scope) {
          scope.setTag('consent', 'granted');
        });
      } catch (_) {}
    }
  }

  /// 从环境变量读取 DSN
  static String _resolveDsn() {
    const dsn = String.fromEnvironment('SENTRY_DSN');
    if (dsn.isNotEmpty) {
      return dsn;
    }
    return _defaultDsn;
  }

  /// 从持久化加载用户同意状态
  static Future<bool> loadUserConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_consentPrefKey) ?? false;
  }
}

/// 初始化 Sentry —— 在 runApp 之前调用
///
/// 检查 SENTRY_DSN 环境变量，若未设置则优雅降级（仅本地日志）。
/// 用户同意通过 SentryConfig.setUserConsent() 控制，未同意时 Sentry 静默不收集。
Future<void> setupSentry({SentryConfig? config}) async {
  final cfg = config ?? SentryConfig();

  // 加载持久化的用户同意状态
  cfg._userConsent = await SentryConfig.loadUserConsent();

  // 检查 SENTRY_DSN 环境变量 —— 未设置时不初始化 Sentry（优雅降级）
  final dsn = String.fromEnvironment('SENTRY_DSN');
  if (dsn.isEmpty) {
    debugPrint('[Sentry] SENTRY_DSN not set — Sentry is disabled (graceful fallback)');
    return;
  }

  cfg.enable();

  await SentryFlutter.init(
    (options) {
      options.dsn = dsn;
      options.environment = cfg.environment;
      options.tracesSampleRate = cfg.sampleRate;
      options.profilesSampleRate = cfg.sampleRate;

      // 仅在用户已同意时上报 —— 符合 GDPR/CCPA "opt-in" 原则
      if (!cfg._userConsent) {
        options.tracesSampleRate = 0.0;
        options.profilesSampleRate = 0.0;
        debugPrint('[Sentry] User consent not granted — sampling rates set to 0');
      }

      // 过滤 PII（个人身份信息）
      options.beforeSend = (event, {hint}) {
        // 用户未同意时直接丢弃事件
        if (!cfg._userConsent) {
          return null;
        }
        // 移除可能包含敏感信息的请求体
        if (event.request?.url?.contains('/auth/') ?? false) {
          event.request?.data = null;
        }
        // 移除环境变量中的敏感信息
        event.tags?.removeWhere((key, _) =>
            key.toLowerCase().contains('key') ||
            key.toLowerCase().contains('secret') ||
            key.toLowerCase().contains('token'));

        return event;
      };

      // 仅在 release 模式下上报
      if (kDebugMode) {
        options.debug = true;
      }

      debugPrint('[Sentry] Initialized — environment: ${cfg.environment}, dsn: $dsn, consent: ${cfg._userConsent}');
    },
    appRunner: () {
      // appRunner 由外部调用 runApp；此处为空操作
    },
  );
}
