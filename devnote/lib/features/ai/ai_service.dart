// AI 服务主入口
//
// 借鉴 AppFlowy Vault 的本地 AI 集成模式：
// 所有 AI 能力（对话/摘要/改写/补全/标签推荐/问题推荐）统一收敛到 AIService，
// 底层通过 OllamaClient 调用本地 LLM，Dart 端仅负责提示词编排与结果解析。
//
// 重要约束：
// 1. AI 功能默认关闭，需用户在设置页配置 Ollama 后显式启用
// 2. 所有调用带超时与错误处理，失败时返回友好提示而非抛异常
// 3. 流式生成支持取消（通过 CancelToken）

import 'dart:async';

import 'package:devnote/features/ai/ollama_client.dart';
import 'package:devnote/core/observability/app_logger.dart';

/// 摘要风格
enum SummaryStyle {
  /// 简短摘要（1-2 句话）
  brief,

  /// 详细摘要（保留主要论据与细节）
  detailed,

  /// 要点列表（bullet points）
  bulletPoints,

  /// 关键洞察（提炼核心观点）
  keyInsights,
}

/// 改写风格
enum RewriteStyle {
  /// 正式
  formal,

  /// 口语化
  casual,

  /// 简洁
  concise,

  /// 扩展（补充细节）
  expanded,

  /// 学术
  academic,
}

/// AI 服务状态
enum AIServiceStatus {
  /// 未配置（Ollama 不可用或未启用）
  notConfigured,

  /// 可用
  available,

  /// 生成中
  generating,

  /// 错误
  error,
}

/// AI 服务主入口
///
/// 通过 [OllamaClient] 调用本地 LLM，封装常用 AI 能力。
/// UI 层通过 [status] 判断是否展示 AI 入口，通过 [setEnabled] 控制总开关。
class AIService {
  AIService({required OllamaClient ollamaClient})
      : _ollama = ollamaClient;

  final OllamaClient _ollama;

  /// AI 总开关（默认关闭，需用户显式启用）
  bool _enabled = false;
  bool _summarizeEnabled = true;
  bool _rewriteEnabled = true;
  bool _completeEnabled = true;
  bool _tagSuggestEnabled = true;

  /// 当前状态
  AIServiceStatus _status = AIServiceStatus.notConfigured;
  AIServiceStatus get status => _status;

  /// 状态广播流，供 BLoC / UI 监听
  final StreamController<AIServiceStatus> _statusController =
      StreamController<AIServiceStatus>.broadcast();
  Stream<AIServiceStatus> get statusStream => _statusController.stream;

  // ---------- 开关配置 ----------

  bool get enabled => _enabled;
  bool get summarizeEnabled => _summarizeEnabled;
  bool get rewriteEnabled => _rewriteEnabled;
  bool get completeEnabled => _completeEnabled;
  bool get tagSuggestEnabled => _tagSuggestEnabled;

  void setEnabled(bool value) {
    _enabled = value;
    _refreshStatus();
  }

  void setSummarizeEnabled(bool value) => _summarizeEnabled = value;
  void setRewriteEnabled(bool value) => _rewriteEnabled = value;
  void setCompleteEnabled(bool value) => _completeEnabled = value;
  void setTagSuggestEnabled(bool value) => _tagSuggestEnabled = value;

  /// 切换底层生成模型
  void setModel(String model) {
    _ollama.model = model;
  }

  /// 探测 Ollama 可用性并刷新状态
  Future<void> refreshAvailability() async {
    if (!_enabled) {
      _setStatus(AIServiceStatus.notConfigured);
      return;
    }
    final ok = await _ollama.isAvailable();
    _setStatus(ok ? AIServiceStatus.available : AIServiceStatus.notConfigured);
  }

  void _refreshStatus() {
    if (!_enabled) {
      _setStatus(AIServiceStatus.notConfigured);
      return;
    }
    // 火并忘（fire-and-forget）：状态探测异步进行，结果通过 _setStatus 广播
    unawaited(refreshAvailability());
  }

  void _setStatus(AIServiceStatus s) {
    if (_status == s) return;
    _status = s;
    _statusController.add(s);
  }

  /// 检查 AI 是否可用（总开关开启 + Ollama 在线）
  Future<bool> isReady() async {
    if (!_enabled) return false;
    return _ollama.isAvailable();
  }

  // ---------- AI 能力 ----------

  /// 对话
  ///
  /// [prompt] 用户输入；[systemPrompt] 系统提示词；
  /// [context] 可选的上下文（如当前笔记内容），会被拼接到系统提示词中。
  Future<String> chat({
    required String prompt,
    String? systemPrompt,
    String? context,
  }) async {
    if (!await _guard()) return 'AI 未启用或 Ollama 不可用，请先在设置中配置。';
    try {
      final system = _buildSystem(systemPrompt, context);
      return await _ollama.chat(prompt: prompt, system: system);
    } catch (e) {
      AppLogger.w('AIService', '对话失败', error: e);
      return 'AI 对话失败: $e';
    }
  }

  /// 流式对话
  ///
  /// 返回逐 token 输出的 Stream，[cancelToken] 可用于主动取消。
  /// 取消或异常时通过 Stream error 传播，由调用方（如 AIBloc）捕获处理。
  Stream<String> chatStream({
    required String prompt,
    String? systemPrompt,
    String? context,
    CancelToken? cancelToken,
  }) async* {
    if (!await _guard()) {
      yield 'AI 未启用或 Ollama 不可用，请先在设置中配置。';
      return;
    }
    _setStatus(AIServiceStatus.generating);
    try {
      final system = _buildSystem(systemPrompt, context);
      yield* _ollama.generateStream(
        prompt: prompt,
        system: system,
        cancelToken: cancelToken,
      );
      _setStatus(AIServiceStatus.available);
    } catch (e) {
      _setStatus(AIServiceStatus.error);
      AppLogger.w('AIService', '流式对话失败', error: e);
      // 重新抛出，让调用方区分取消与正常结束
      rethrow;
    }
  }

  /// 摘要
  Future<String> summarize({
    required String content,
    SummaryStyle style = SummaryStyle.brief,
  }) async {
    if (!_summarizeEnabled) return '摘要功能已禁用。';
    if (!await _guard()) return 'AI 未启用或 Ollama 不可用，请先在设置中配置。';
    try {
      final prompt = _summarizePrompt(content, style);
      return await _ollama.generate(
        prompt: prompt,
        system: '你是一个专业的笔记摘要助手，请用中文输出。',
      );
    } catch (e) {
      AppLogger.w('AIService', '摘要失败', error: e);
      return '摘要生成失败: $e';
    }
  }

  /// 改写
  Future<String> rewrite({
    required String content,
    RewriteStyle style = RewriteStyle.formal,
  }) async {
    if (!_rewriteEnabled) return '改写功能已禁用。';
    if (!await _guard()) return 'AI 未启用或 Ollama 不可用，请先在设置中配置。';
    try {
      final prompt = _rewritePrompt(content, style);
      return await _ollama.generate(
        prompt: prompt,
        system: '你是一个专业的中文写作助手，请直接输出改写后的文本，不要添加解释。',
      );
    } catch (e) {
      AppLogger.w('AIService', '改写失败', error: e);
      return '改写失败: $e';
    }
  }

  /// 自动补全
  ///
  /// [prefix] 当前光标前的文本，返回 AI 续写内容。
  Future<String> complete({required String prefix}) async {
    if (!_completeEnabled) return '';
    if (!await _guard()) return '';
    try {
      final prompt = '请续写以下文本，仅输出续写部分，不要重复原文：\n\n$prefix';
      final result = await _ollama.generate(
        prompt: prompt,
        system: '你是一个中文笔记补全助手，输出简洁自然的续写内容。',
        maxTokens: 128,
      );
      return result.trim();
    } catch (e) {
      AppLogger.w('AIService', '补全失败', error: e);
      return '';
    }
  }

  /// 标签推荐
  ///
  /// 基于笔记内容推荐 3-8 个标签，返回去重后的标签列表。
  Future<List<String>> suggestTags({required String content}) async {
    if (!_tagSuggestEnabled) return const [];
    if (!await _guard()) return const [];
    try {
      final prompt = '请为以下笔记内容推荐 3-8 个标签，'
          '仅输出标签，用逗号分隔，不要编号和解释：\n\n$content';
      final result = await _ollama.generate(
        prompt: prompt,
        system: '你是一个标签推荐助手，输出简洁的中文或英文标签。',
        maxTokens: 64,
      );
      return _parseTags(result);
    } catch (e) {
      AppLogger.w('AIService', '标签推荐失败', error: e);
      return const [];
    }
  }

  /// 相关问题推荐
  ///
  /// 基于笔记内容生成 3-5 个相关问题，便于用户深入探索。
  Future<List<String>> suggestQuestions({required String content}) async {
    if (!await _guard()) return const [];
    try {
      final prompt = '请基于以下笔记内容生成 3-5 个值得深入思考的相关问题，'
          '每行一个问题，不要编号：\n\n$content';
      final result = await _ollama.generate(
        prompt: prompt,
        system: '你是一个知识探索助手，输出有启发性的中文问题。',
        maxTokens: 256,
      );
      return result
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((l) => l.replaceFirst(RegExp(r'^[\d\.\、\-\*\)]+\s*'), ''))
          .take(5)
          .toList();
    } catch (e) {
      AppLogger.w('AIService', '问题推荐失败', error: e);
      return const [];
    }
  }

  void dispose() {
    _statusController.close();
  }

  // ---------- 内部工具 ----------

  /// 调用前置守卫：检查开关与可用性
  Future<bool> _guard() async {
    if (!_enabled) return false;
    return _ollama.isAvailable();
  }

  /// 构建系统提示词，可选拼接上下文
  String _buildSystem(String? systemPrompt, String? context) {
    final buffer = StringBuffer();
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer.write(systemPrompt);
    }
    if (context != null && context.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write('以下是相关上下文，供参考：\n');
      buffer.write(context);
    }
    return buffer.toString();
  }

  String _summarizePrompt(String content, SummaryStyle style) {
    switch (style) {
      case SummaryStyle.brief:
        return '请用 1-2 句话简短概括以下笔记的核心内容：\n\n$content';
      case SummaryStyle.detailed:
        return '请详细概括以下笔记的主要内容，保留关键论据与细节：\n\n$content';
      case SummaryStyle.bulletPoints:
        return '请用要点列表（bullet points）概括以下笔记，每行一个要点：\n\n$content';
      case SummaryStyle.keyInsights:
        return '请提炼以下笔记的关键洞察，输出 3-5 条核心观点：\n\n$content';
    }
  }

  String _rewritePrompt(String content, RewriteStyle style) {
    switch (style) {
      case RewriteStyle.formal:
        return '请将以下文本改写为正式、严谨的风格：\n\n$content';
      case RewriteStyle.casual:
        return '请将以下文本改写为口语化、轻松的风格：\n\n$content';
      case RewriteStyle.concise:
        return '请将以下文本改写得更简洁，去除冗余：\n\n$content';
      case RewriteStyle.expanded:
        return '请扩展以下文本，补充必要的细节与论据：\n\n$content';
      case RewriteStyle.academic:
        return '请将以下文本改写为学术风格，使用规范术语与严谨表达：\n\n$content';
    }
  }

  /// 解析标签输出：支持逗号、顿号、换行分隔
  List<String> _parseTags(String output) {
    final tags = <String>{};
    for (final raw in output.split(RegExp(r'[,，、\n]'))) {
      final tag = raw.trim().replaceAll(RegExp(r'^[#＃]\s*'), '');
      if (tag.isNotEmpty && tag.length <= 20) {
        tags.add(tag);
      }
    }
    return tags.take(8).toList();
  }
}
