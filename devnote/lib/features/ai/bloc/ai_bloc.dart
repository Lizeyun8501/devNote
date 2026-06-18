import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:devnote/features/ai/ai_service.dart';
import 'package:devnote/features/ai/bloc/ai_event.dart';
import 'package:devnote/features/ai/bloc/ai_state.dart';
import 'package:devnote/features/ai/ollama_client.dart';

/// AI 业务逻辑组件
///
/// 管理所有 AI 能力的状态流转：对话/摘要/改写/补全/标签推荐。
/// 流式对话通过 [AIGenerating.partial] 实时回传片段，支持取消生成。
///
/// 取消机制说明：
/// 由于 bloc 事件默认顺序处理，[AICancelGeneration] 事件会排在进行中的
/// 流式事件之后。因此同时提供 [cancelGeneration] 方法供 UI 直接调用，
/// 立即触发 CancelToken 关闭底层 HTTP 连接，使流式事件得以完成。
class AIBloc extends Bloc<AIEvent, AIState> {
  AIBloc(this._aiService) : super(const AIInitial()) {
    on<AIChat>(_onChat);
    on<AISummarize>(_onSummarize);
    on<AIRewrite>(_onRewrite);
    on<AIComplete>(_onComplete);
    on<AISuggestTags>(_onSuggestTags);
    on<AICancelGeneration>(_onCancelGeneration);
  }

  final AIService _aiService;

  /// 当前流式生成的取消令牌
  CancelToken? _activeCancelToken;

  /// 是否已取消当前生成（用于区分取消与异常）
  bool _cancelled = false;

  /// 直接取消当前生成（不经过事件队列）
  ///
  /// UI 层在用户点击"停止生成"时直接调用此方法，
  /// 立即关闭底层 HTTP 连接，使正在进行的流式事件得以完成。
  void cancelGeneration() {
    if (_activeCancelToken != null) {
      _cancelled = true;
      _activeCancelToken?.cancel();
      _activeCancelToken = null;
    }
  }

  /// 对话（流式）
  ///
  /// 实时回传生成片段，完成后切换到 [AIGenerated]。
  Future<void> _onChat(AIChat event, Emitter<AIState> emit) async {
    _cancelled = false;
    _activeCancelToken?.cancel();
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;
    emit(const AIGenerating());
    try {
      final buffer = StringBuffer();
      await emit.forEach(
        _aiService.chatStream(
          prompt: event.prompt,
          context: event.context,
          cancelToken: cancelToken,
        ),
        onData: (chunk) {
          buffer.write(chunk);
          return AIGenerating(partial: buffer.toString());
        },
      );
      emit(AIGenerated(
        result: buffer.toString(),
        kind: AIResultKind.chat,
      ));
    } catch (e) {
      if (_cancelled) {
        emit(AIReady(_aiService.status));
      } else {
        emit(AIError('对话失败: $e'));
      }
    } finally {
      _activeCancelToken = null;
      _cancelled = false;
    }
  }

  /// 摘要
  Future<void> _onSummarize(AISummarize event, Emitter<AIState> emit) async {
    emit(const AIGenerating());
    try {
      final result = await _aiService.summarize(
        content: event.content,
        style: event.style,
      );
      emit(AIGenerated(result: result, kind: AIResultKind.summarize));
    } catch (e) {
      emit(AIError('摘要失败: $e'));
    }
  }

  /// 改写
  Future<void> _onRewrite(AIRewrite event, Emitter<AIState> emit) async {
    emit(const AIGenerating());
    try {
      final result = await _aiService.rewrite(
        content: event.content,
        style: event.style,
      );
      emit(AIGenerated(result: result, kind: AIResultKind.rewrite));
    } catch (e) {
      emit(AIError('改写失败: $e'));
    }
  }

  /// 自动补全
  Future<void> _onComplete(AIComplete event, Emitter<AIState> emit) async {
    emit(const AIGenerating());
    try {
      final result = await _aiService.complete(prefix: event.prefix);
      emit(AIGenerated(result: result, kind: AIResultKind.complete));
    } catch (e) {
      emit(AIError('补全失败: $e'));
    }
  }

  /// 标签推荐
  Future<void> _onSuggestTags(
    AISuggestTags event,
    Emitter<AIState> emit,
  ) async {
    emit(const AIGenerating());
    try {
      final tags = await _aiService.suggestTags(content: event.content);
      emit(AIGenerated(
        result: tags.join(', '),
        tags: tags,
        kind: AIResultKind.tags,
      ));
    } catch (e) {
      emit(AIError('标签推荐失败: $e'));
    }
  }

  /// 取消生成（事件形式）
  ///
  /// 注意：由于 bloc 事件顺序处理，此事件会排在进行中的流式事件之后。
  /// 需要立即取消时，UI 应直接调用 [cancelGeneration]。
  void _onCancelGeneration(
    AICancelGeneration event,
    Emitter<AIState> emit,
  ) {
    cancelGeneration();
    emit(AIReady(_aiService.status));
  }

  @override
  Future<void> close() {
    cancelGeneration();
    return super.close();
  }
}
