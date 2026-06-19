// 修复(P1): 将 features 层的依赖注册从 core/di/injection.dart 迁移至此，
// 消除 core → features 的反向依赖。core/di 仅注册 core 层服务，
// features 层各自提供 register 函数，由 main.dart 顺序调用。
//
// 原问题: injection.dart (core 层) 导入了 13 个 features/* 模块，
// 违反依赖倒置原则，导致 core 层无法独立编译/测试。

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/ai/ai_service.dart';
import 'package:devnote/features/ai/embedding_service.dart';
import 'package:devnote/features/ai/ollama_client.dart';
import 'package:devnote/features/ai/semantic_search_service.dart';
import 'package:devnote/core/persistence/database_helper.dart';

/// 注册 AI 模块依赖
/// 注册顺序：OllamaClient → EmbeddingService → AIService → SemanticSearchService
/// 所有 AI 功能默认关闭，需用户在 AI 设置页配置 Ollama 后显式启用
Future<void> registerAIDependencies() async {
  getIt.registerLazySingleton<OllamaClient>(
    () => OllamaClient(baseUrl: 'http://localhost:11434', model: 'llama3'),
  );
  getIt.registerLazySingleton<EmbeddingService>(
    () => EmbeddingService(ollamaClient: getIt<OllamaClient>()),
  );
  getIt.registerLazySingleton<AIService>(
    () => AIService(ollamaClient: getIt<OllamaClient>()),
  );
  getIt.registerLazySingleton<SemanticSearchService>(
    () => SemanticSearchService(
      databaseHelper: getIt<DatabaseHelper>(),
      embeddingService: getIt<EmbeddingService>(),
    ),
  );
}

/// 释放 AI 模块资源（关闭 Ollama HTTP 客户端、状态流）
void disposeAIModule() {
  if (getIt.isRegistered<AIService>()) {
    getIt<AIService>().dispose();
  }
  if (getIt.isRegistered<OllamaClient>()) {
    getIt<OllamaClient>().dispose();
  }
}
