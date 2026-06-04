// 统一日志模块 —— 借鉴 Apache log4j 的日志级别设计
// 来源: https://logging.apache.org/log4j/2.x/
// 借鉴内容: TRACE < DEBUG < INFO < WARN < ERROR < FATAL 的分层日志级别，
// 通过级别过滤控制输出量；底层使用 dart:developer 的 log 方法，
// 在 DevTools 中可按 level/name/time 过滤显示，便于调试与生产问题定位。
//
// 设计要点:
// 1. 单例模式: 全局唯一实例，可通过 getIt<AppLogger>() 注入使用，
//    也可经静态门面 AppLogger.i/w/e 直接调用。
// 2. 分级输出: 仅 error 级别会触发 Sentry 上报，避免噪音淹没告警。
// 3. 自动识别 Sentry: 若已启用（enableSentry()），error 自动 captureException。
// 4. 错误对象透传: 支持 error + stackTrace 透传，便于 Sentry 完整上报。

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// 日志级别 —— 借鉴 log4j 级别体系
///
/// 数值越大，级别越高。过滤时只输出 >= 当前级别的事件。
enum AppLogLevel {
  /// 细粒度调试信息（生产环境默认关闭）
  debug(500, 'DEBUG'),

  /// 关键流程节点信息（默认输出级别）
  info(800, 'INFO'),

  /// 警告信息 —— 不会导致失败，但需要关注
  warn(900, 'WARN'),

  /// 错误信息 —— 业务失败/异常，会自动上报 Sentry
  error(1000, 'ERROR');

  final int value;
  final String label;

  const AppLogLevel(this.value, this.label);
}

/// 统一日志门面
///
/// 使用方式（注入）:
/// ```dart
/// final logger = getIt<AppLogger>();
/// logger.d('Tag', 'debug message');
/// logger.i('Tag', 'info message');
/// logger.w('Tag', 'warn message', error: e);
/// logger.e('Tag', 'error message', error: e, stackTrace: st);
/// ```
///
/// 使用方式（静态门面，无需 DI 上下文）:
/// ```dart
/// AppLogger.d('Tag', 'debug message');
/// AppLogger.i('Tag', 'info message');
/// AppLogger.w('Tag', 'warn message', error: e);
/// AppLogger.e('Tag', 'error message', error: e, stackTrace: st);
/// ```
class AppLogger {
  // ---------- 单例 ----------
  static final AppLogger _instance = AppLogger._();

  /// 静态门面: 直接访问全局唯一实例
  static AppLogger get instance => _instance;

  AppLogger._();

  /// 静态门面快捷方法
  static void d(String tag, String message) => _instance.debug(tag, message);

  static void i(String tag, String message) => _instance.info(tag, message);

  static void w(String tag, String message, {Object? error}) =>
      _instance.warn(tag, message, error: error);

  static void e(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _instance.error(tag, message, error: error, stackTrace: stackTrace);

  /// 全局最低输出级别 —— debug 模式下默认 debug，release 模式下默认 info
  AppLogLevel _minLevel =
      kDebugMode ? AppLogLevel.debug : AppLogLevel.info;

  /// 是否启用 Sentry 上报（默认 false，setupSentry 完成后置为 true）
  bool _sentryEnabled = false;

  /// 设置全局最低输出级别
  void setMinLevel(AppLogLevel level) {
    _minLevel = level;
  }

  /// 标记 Sentry 已启用
  ///
  /// 应在 SentryFlutter.init 成功之后调用，使 error 级别日志自动上报。
  void enableSentry() {
    _sentryEnabled = true;
  }

  /// 标记 Sentry 已关闭（同时清空 Sentry 内部缓冲区可选）
  void disableSentry() {
    _sentryEnabled = false;
  }

  /// 调试日志
  void debug(String tag, String message) {
    _log(AppLogLevel.debug, tag, message, null, null);
  }

  /// 信息日志
  void info(String tag, String message) {
    _log(AppLogLevel.info, tag, message, null, null);
  }

  /// 警告日志
  void warn(String tag, String message, {Object? error}) {
    _log(AppLogLevel.warn, tag, message, error, null);
  }

  /// 错误日志 —— 当 Sentry 启用时自动上报
  void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(AppLogLevel.error, tag, message, error, stackTrace);
  }

  // ---------- 内部实现 ----------

  void _log(
    AppLogLevel level,
    String tag,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    // 级别过滤
    if (level.value < _minLevel.value) return;

    // 构造完整消息，便于一次性查看
    final buffer = StringBuffer(message);
    if (error != null) {
      buffer.write(' | error=$error');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    final fullMessage = buffer.toString();

    // 输出到 dart:developer（DevTools 可见，按 name/level 过滤）
    developer.log(
      fullMessage,
      name: tag,
      level: level.value,
      error: error,
      stackTrace: stackTrace,
    );

    // Release 模式补充: 同步输出到 print，方便 adb logcat 抓取
    if (!kDebugMode) {
      // ignore: avoid_print
      print('[${level.label}/$tag] $fullMessage');
    }

    // error 级别自动上报 Sentry
    if (level == AppLogLevel.error && _sentryEnabled) {
      _reportToSentry(tag, message, error, stackTrace);
    }
  }

  /// 异步上报 Sentry —— 避免阻塞主线程
  Future<void> _reportToSentry(
    String tag,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) async {
    try {
      if (error != null) {
        await Sentry.captureException(
          error,
          stackTrace: stackTrace,
          hint: Hint.withMap({'logger.tag': tag, 'logger.message': message}),
        );
      } else {
        await Sentry.captureMessage(
          '[$tag] $message',
          level: SentryLevel.error,
        );
      }
    } catch (_) {
      // Sentry 未初始化或上报失败时静默忽略，避免日志引发二次异常
    }
  }
}
