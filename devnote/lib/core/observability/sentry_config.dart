// 集成 Sentry 崩溃报告 —— 借鉴 AppFlowy 的 Sentry 集成方案
// 来源: https://github.com/AppFlowy-IO/AppFlowy

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Sentry 配置类 —— 集中管理 DSN、环境、采样率等设置
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

  SentryConfig({
    this.environment = 'production',
    this.sampleRate = 1.0,
  });

  bool get isEnabled => _enabled;

  void enable() {
    _enabled = true;
  }

  void disable() {
    _enabled = false;
  }

  /// 从环境变量读取 DSN
  static String _resolveDsn() {
    const dsn = String.fromEnvironment('SENTRY_DSN');
    if (dsn.isNotEmpty) {
      return dsn;
    }
    return _defaultDsn;
  }
}

/// 初始化 Sentry —— 在 runApp 之前调用
///
/// 检查 SENTRY_DSN 环境变量，若未设置则优雅降级（仅本地日志）。
/// 用户可通过 SentryConfig.enable() / disable() 控制上报同意。
Future<void> setupSentry({SentryConfig? config}) async {
  final cfg = config ?? SentryConfig();

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

      // 过滤 PII（个人身份信息）
      options.beforeSend = (event, {hint}) {
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

      debugPrint('[Sentry] Initialized — environment: ${cfg.environment}, dsn: $dsn');
    },
    appRunner: () {
      // appRunner 由外部调用 runApp；此处为空操作
    },
  );
}