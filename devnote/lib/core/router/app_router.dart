// AppRouter 构建器 —— 从 RouteRegistry 读取已注册路由。
//
// P2-2 路由层改注册表模式：
//   - 本文件不 import 任何 features/* 页面，消除 core → features 反向依赖
//   - 路由配置由 features/feature_routes.dart 注册到 RouteRegistry
//   - main.dart 在所有 feature 模块注册完成后调用 buildAppRouter()
//
// 调用顺序约束：
//   1. setupDependencies()              —— core 层 DI
//   2. register*Dependencies()          —— features 层 DI
//   3. registerFeatureRoutes()          —— features 层路由注册
//   4. buildAppRouter()                 —— 构建路由器
//   5. runApp()                         —— 启动应用

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:devnote/core/router/route_registry.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// 构建 AppRouter。
///
/// 必须在所有 feature 模块完成路由注册（[RouteRegistry.registerShell] /
/// [RouteRegistry.registerRoutes]）后调用，否则抛 [StateError]。
GoRouter buildAppRouter() {
  final shellBuilder = RouteRegistry.shellBuilder;
  if (shellBuilder == null) {
    throw StateError(
      'RouteRegistry.shellBuilder is null. '
      'Call registerFeatureRoutes() before buildAppRouter().',
    );
  }

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/notes',
    // ============================================================
    // 路由导航守卫 —— 借鉴 Vue Router 的 beforeEach 守卫模式
    // 来源: https://router.vuejs.org/guide/advanced/navigation-guards.html
    // 借鉴内容: 全局前置守卫 (global before guard)，用于权限校验和重定向
    // ============================================================
    redirect: (context, state) {
      // 路由守卫已移除 FFI 可用性检查
      // 原实现因 _frbApi 恒为 null 导致 5 条路由永远重定向到 /notes
      // FFI 不可用时各页面自行降级到 sqflite，无需路由层拦截
      return null;
    },
    routes: [
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: shellBuilder,
        routes: RouteRegistry.routes,
      ),
    ],
  );
}
