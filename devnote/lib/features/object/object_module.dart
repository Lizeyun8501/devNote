// P2-3: Object 模块依赖注册。
// 遵循 notes_module.dart / vault_module.dart 的模块自注册模式：
// core/di 仅注册 core 层服务，features 层各自提供 register/dispose 函数，
// 由 main.dart 在 setupDependencies() 之后顺序调用，消除 core → features 反向依赖。
//
// 修复：原 object_graph_page / object_type_manager_page 直接 new ObjectService()，
// 绕过 DI 容器。ObjectService 构造时从 getIt 获取 DatabaseHelper，
// 直接 new 会重复获取同一 DatabaseHelper 单例（虽不致命但违反一致性）。
// 改为统一注册到 getIt，页面通过 getIt<ObjectService>() 获取单例。

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/object/object_service.dart';

/// 注册 Object 模块依赖。
/// ObjectService 依赖 DatabaseHelper（core 层已注册），无异步初始化需求。
Future<void> registerObjectDependencies() async {
  if (!getIt.isRegistered<ObjectService>()) {
    getIt.registerLazySingleton<ObjectService>(() => ObjectService());
  }
}

/// 释放 Object 模块资源。
/// ObjectService 基于 DatabaseHelper（由 disposeCore 统一关闭），无独立句柄。
void disposeObjectModule() {
  // ObjectService 基于 DatabaseHelper，无独立资源需释放
}
