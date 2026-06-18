import 'package:devnote/features/ai/ai_service.dart';

/// AI BLoC 状态
///
/// 借鉴项目现有 BLoC 模式（如 EditorBloc），使用 sealed class 表达状态机。
sealed class AIState {
  const AIState();
}

/// 初始状态
final class AIInitial extends AIState {
  const AIInitial();
}

/// 就绪状态（AI 可用，等待用户操作）
final class AIReady extends AIState {
  final AIServiceStatus status;

  const AIReady(this.status);
}

/// 生成中状态
///
/// [partial] 用于流式生成时实时回传已生成的片段。
final class AIGenerating extends AIState {
  final String? partial;

  const AIGenerating({this.partial});
}

/// 生成完成状态
final class AIGenerated extends AIState {
  /// 生成结果文本（对话/摘要/改写/补全）
  final String result;

  /// 标签推荐结果（仅 AISuggestTags 事件填充）
  final List<String> tags;

  /// 触发本次结果的 AI 能力类型，便于 UI 区分展示
  final AIResultKind kind;

  const AIGenerated({
    required this.result,
    this.tags = const [],
    required this.kind,
  });
}

/// 错误状态
final class AIError extends AIState {
  final String message;

  const AIError(this.message);
}

/// AI 结果类型，用于 UI 区分展示
enum AIResultKind { chat, summarize, rewrite, complete, tags }
