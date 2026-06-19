// 修复(P1): 将 features 层的依赖注册从 core/di/injection.dart 迁移至此，
// 消除 core → features 的反向依赖。

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/settings/crypto/crypto_service.dart';

/// 注册 Settings 模块依赖
Future<void> registerSettingsDependencies() async {
  getIt.registerLazySingleton<CryptoService>(() => CryptoService());
}
