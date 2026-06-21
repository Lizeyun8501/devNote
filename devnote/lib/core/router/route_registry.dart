// 路由注册表 —— 消除 core/router → features 的反向依赖。
//
// 设计动机（P2-2 路由层改注册表模式）：
// 原 app_router.dart 直接 import 38 个 features 页面文件，构成 core → features
// 反向依赖，违反分层架构约束。改用注册表模式后：
//   - core/router 仅定义 RouteRegistry 与 buildAppRouter()，不 import 任何 features
//   - features/feature_routes.dart 负责将各页面注册到 RouteRegistry
//   - main.dart 在 setupDependencies() 之后调用 registerFeatureRoutes()，
//     再 buildAppRouter() 构建最终路由器
//
// 借鉴 Go 的 http.Handler 注册模式（http.HandleFunc）与 Vue Router 的
// addRoute() 动态注册：路由配置由各模块自治，路由器仅聚合消费。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shell 容器构建器签名，与 [ShellRoute.builder] 一致。
typedef ShellRouteBuilder = Widget Function(
  BuildContext context,
  GoRouterState state,
  Widget child,
);

/// 全局路由注册表。
///
/// 各 feature 模块在初始化阶段调用 [registerShell] / [registerRoutes]，
/// [buildAppRouter] 在所有注册完成后从注册表读取配置构建 [GoRouter]。
///
/// 线程安全：Flutter 单线程模型，无需加锁。
class RouteRegistry {
  RouteRegistry._();

  static final List<RouteBase> _routes = [];
  static ShellRouteBuilder? _shellBuilder;

  /// 已注册的子路由列表（供 ShellRoute.routes 使用）。
  static List<RouteBase> get routes => List.unmodifiable(_routes);

  /// 已注册的 Shell 容器构建器。
  static ShellRouteBuilder? get shellBuilder => _shellBuilder;

  /// 注册 Shell 容器（应用主框架）。仅可注册一次，重复注册抛 [StateError]。
  static void registerShell(ShellRouteBuilder builder) {
    if (_shellBuilder != null) {
      throw StateError(
        'RouteRegistry: shell builder already registered. '
        'Call reset() before re-registering (e.g. in tests).',
      );
    }
    _shellBuilder = builder;
  }

  /// 注册一批子路由到 Shell 之下。
  static void registerRoutes(Iterable<RouteBase> routes) {
    _routes.addAll(routes);
  }

  /// 清空注册表（测试 tearDown 或热重载场景使用）。
  static void reset() {
    _routes.clear();
    _shellBuilder = null;
  }
}
