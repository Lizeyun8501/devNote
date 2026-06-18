import 'package:equatable/equatable.dart';

import 'package:devnote/features/ai/ai_service.dart';

abstract class AIEvent extends Equatable {
  const AIEvent();

  @override
  List<Object?> get props => [];
}

/// 对话
class AIChat extends AIEvent {
  final String prompt;
  final String? context;

  const AIChat({required this.prompt, this.context});

  @override
  List<Object?> get props => [prompt, context];
}

/// 摘要
class AISummarize extends AIEvent {
  final String content;
  final SummaryStyle style;

  const AISummarize({
    required this.content,
    this.style = SummaryStyle.brief,
  });

  @override
  List<Object?> get props => [content, style];
}

/// 改写
class AIRewrite extends AIEvent {
  final String content;
  final RewriteStyle style;

  const AIRewrite({
    required this.content,
    this.style = RewriteStyle.formal,
  });

  @override
  List<Object?> get props => [content, style];
}

/// 自动补全
class AIComplete extends AIEvent {
  final String prefix;

  const AIComplete({required this.prefix});

  @override
  List<Object?> get props => [prefix];
}

/// 标签推荐
class AISuggestTags extends AIEvent {
  final String content;

  const AISuggestTags({required this.content});

  @override
  List<Object?> get props => [content];
}

/// 取消生成
class AICancelGeneration extends AIEvent {
  const AICancelGeneration();
}
