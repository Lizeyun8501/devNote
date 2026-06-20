// P1-3: 模板系统模块依赖注册。
// 遵循 ai_module.dart / editor_module.dart 的模块自注册模式：
// core/di 仅注册 core 层服务，features 层各自提供 register/dispose 函数，
// 由 main.dart 在 setupDependencies() 之后顺序调用，消除 core → features 反向依赖。
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/templates/services/template_service.dart';

/// 注册 Templates 模块依赖
Future<void> registerTemplatesDependencies() async {
  if (!getIt.isRegistered<TemplateService>()) {
    getIt.registerLazySingleton<TemplateService>(() => TemplateService());
  }
}

/// 释放 Templates 模块资源
/// TemplateService 基于 SharedPreferences，无句柄需显式释放。
void disposeTemplatesModule() {
  // TemplateService 无需显式释放资源
}
