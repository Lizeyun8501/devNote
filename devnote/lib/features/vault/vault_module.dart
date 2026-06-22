// P1-7: Vault 保险库模块依赖注册。
// 遵循 ai_module.dart / templates_module.dart 的模块自注册模式：
// core/di 仅注册 core 层服务，features 层各自提供 register/dispose 函数，
// 由 main.dart 在 setupDependencies() 之后顺序调用，消除 core → features 反向依赖。

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/vault/services/vault_service.dart';

/// 注册 Vault 模块依赖
Future<void> registerVaultDependencies() async {
  if (!getIt.isRegistered<VaultService>()) {
    getIt.registerLazySingleton<VaultService>(() => VaultService());
  }
}

/// 释放 Vault 模块资源
/// 锁定保险库以清除内存中的密码，然后注销单例。
void disposeVaultModule() {
  if (getIt.isRegistered<VaultService>()) {
    getIt<VaultService>().lock();
    getIt.resetLazySingleton<VaultService>();
  }
}
