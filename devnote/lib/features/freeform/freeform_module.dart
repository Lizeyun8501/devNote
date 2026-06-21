// P2-3: Freeform 模块依赖注册。
// 遵循 notes_module.dart / vault_module.dart 的模块自注册模式：
// core/di 仅注册 core 层服务，features 层各自提供 register/dispose 函数，
// 由 main.dart 在 setupDependencies() 之后顺序调用，消除 core → features 反向依赖。
//
// FreeformBloc 为 per-page 实例（需 pageId 参数），不注册到 DI 容器，
// 由 FreeformPage 内部 BlocProvider 创建。本模块仅占位以保持模块结构一致性。

/// 注册 Freeform 模块依赖。
/// 当前无全局单例服务需要注册（FreeformBloc 为 per-page 实例）。
Future<void> registerFreeformDependencies() async {
  // 预留：未来若引入 FreeformPersistenceService 等全局服务，在此注册。
}

/// 释放 Freeform 模块资源。
/// 当前无全局资源需要释放。
void disposeFreeformModule() {
  // 预留：未来若引入全局服务，在此释放。
}
