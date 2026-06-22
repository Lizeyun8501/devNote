// P2-3: Knowledge 模块依赖注册。
// 遵循 notes_module.dart / vault_module.dart 的模块自注册模式：
// core/di 仅注册 core 层服务，features 层各自提供 register/dispose 函数，
// 由 main.dart 在 setupDependencies() 之后顺序调用，消除 core → features 反向依赖。
//
// 修复：原各页面直接 new XxxService() 绕过 DI，导致：
//   1. 每次页面构建创建新实例，Dispatch 重复注入
//   2. 无法在测试中 mock 替换
//   3. KnowledgeService 内部再次 new LearningStatsService/KnowledgeMapService，实例泛滥
// 改为统一注册到 getIt，页面通过 getIt<XxxService>() 获取单例。

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/knowledge/knowledge_service.dart';
import 'package:devnote/features/knowledge/dashboard/dashboard_service.dart';
import 'package:devnote/features/knowledge/knowledge_map/knowledge_map_service.dart';
import 'package:devnote/features/knowledge/learning_stats/learning_stats_service.dart';

/// 注册 Knowledge 模块依赖。
/// 所有服务基于 Dispatch（core 层已注册），无异步初始化需求。
Future<void> registerKnowledgeDependencies() async {
  if (!getIt.isRegistered<KnowledgeService>()) {
    getIt.registerLazySingleton<KnowledgeService>(() => KnowledgeService());
  }
  if (!getIt.isRegistered<DashboardService>()) {
    getIt.registerLazySingleton<DashboardService>(() => DashboardService());
  }
  if (!getIt.isRegistered<KnowledgeMapService>()) {
    getIt.registerLazySingleton<KnowledgeMapService>(() => KnowledgeMapService());
  }
  if (!getIt.isRegistered<LearningStatsService>()) {
    getIt.registerLazySingleton<LearningStatsService>(() => LearningStatsService());
  }
}

/// 释放 Knowledge 模块资源。
/// 各服务基于 Dispatch，无独立句柄需显式释放。
void disposeKnowledgeModule() {
  // Knowledge 服务基于 Dispatch，无独立资源需释放
}
