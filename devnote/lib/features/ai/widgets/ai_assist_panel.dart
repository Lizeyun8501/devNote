// AI 助手面板 Widget
//
// 借鉴 Continue.dev 的侧边 AI 助手设计：
// 提供对话/摘要/改写/标签推荐四种模式，可引用当前笔记内容作为上下文。
// 通过 AIBloc 驱动状态，支持流式输出与取消生成。
//
// 来源: https://github.com/continuedev/continue

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:devnote/features/ai/ai_service.dart';
import 'package:devnote/features/ai/bloc/ai_bloc.dart';
import 'package:devnote/features/ai/bloc/ai_event.dart';
import 'package:devnote/features/ai/bloc/ai_state.dart';

/// AI 助手面板模式
enum AIAssistMode {
  /// 对话模式：与 AI 对话，可引用当前笔记内容
  chat,

  /// 摘要模式：一键生成当前笔记摘要
  summarize,

  /// 改写模式：选中文本后改写
  rewrite,

  /// 标签推荐：基于内容推荐标签
  tags,
}

/// AI 助手面板
///
/// 作为侧边面板嵌入编辑器页面，提供 AI 写作辅助能力。
/// [noteContent] 为当前笔记内容，作为 AI 上下文；
/// [selectedText] 为编辑器中选中的文本，用于改写模式。
class AIAssistPanel extends StatefulWidget {
  const AIAssistPanel({
    super.key,
    required this.noteContent,
    this.selectedText = '',
    this.onApplyResult,
  });

  /// 当前笔记内容（作为 AI 上下文）
  final String noteContent;

  /// 编辑器中选中的文本
  final String selectedText;

  /// 用户点击"应用结果"时的回调（如将改写结果替换回编辑器）
  final void Function(String result)? onApplyResult;

  @override
  State<AIAssistPanel> createState() => _AIAssistPanelState();
}

class _AIAssistPanelState extends State<AIAssistPanel> {
  AIAssistMode _mode = AIAssistMode.chat;
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// 对话历史（本地维护，简单展示）
  final List<_ChatMessage> _chatHistory = [];

  /// 改写风格选择
  RewriteStyle _rewriteStyle = RewriteStyle.formal;

  /// 摘要风格选择
  SummaryStyle _summaryStyle = SummaryStyle.brief;

  @override
  void dispose() {
    _chatInputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _switchMode(AIAssistMode mode) {
    setState(() => _mode = mode);
  }

  void _sendChat() {
    final text = _chatInputController.text.trim();
    if (text.isEmpty) return;
    _chatInputController.clear();
    setState(() {
      _chatHistory.add(_ChatMessage(role: _Role.user, text: text));
    });
    context.read<AIBloc>().add(
          AIChat(prompt: text, context: widget.noteContent),
        );
  }

  void _summarize() {
    final content = widget.selectedText.isNotEmpty
        ? widget.selectedText
        : widget.noteContent;
    if (content.isEmpty) return;
    context
        .read<AIBloc>()
        .add(AISummarize(content: content, style: _summaryStyle));
  }

  void _rewrite() {
    final content = widget.selectedText.isNotEmpty
        ? widget.selectedText
        : widget.noteContent;
    if (content.isEmpty) return;
    context
        .read<AIBloc>()
        .add(AIRewrite(content: content, style: _rewriteStyle));
  }

  void _suggestTags() {
    final content = widget.noteContent;
    if (content.isEmpty) return;
    context.read<AIBloc>().add(AISuggestTags(content: content));
  }

  void _cancelGeneration() {
    context.read<AIBloc>().cancelGeneration();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildModeSelector(),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
        _buildInputArea(),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SegmentedButton<AIAssistMode>(
        segments: const [
          ButtonSegment(
            value: AIAssistMode.chat,
            icon: Icon(Icons.chat, size: 18),
            label: Text('对话'),
          ),
          ButtonSegment(
            value: AIAssistMode.summarize,
            icon: Icon(Icons.summarize, size: 18),
            label: Text('摘要'),
          ),
          ButtonSegment(
            value: AIAssistMode.rewrite,
            icon: Icon(Icons.edit_note, size: 18),
            label: Text('改写'),
          ),
          ButtonSegment(
            value: AIAssistMode.tags,
            icon: Icon(Icons.label, size: 18),
            label: Text('标签'),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (set) => _switchMode(set.first),
      ),
    );
  }

  Widget _buildBody() {
    return BlocConsumer<AIBloc, AIState>(
      listener: (context, state) {
        if (state is AIGenerated && _mode == AIAssistMode.chat) {
          _chatHistory.add(_ChatMessage(
            role: _Role.assistant,
            text: state.result,
          ));
          _scrollToBottom();
        }
      },
      builder: (context, state) {
        switch (_mode) {
          case AIAssistMode.chat:
            return _buildChatView(state);
          case AIAssistMode.summarize:
            return _buildSummarizeView(state);
          case AIAssistMode.rewrite:
            return _buildRewriteView(state);
          case AIAssistMode.tags:
            return _buildTagsView(state);
        }
      },
    );
  }

  Widget _buildChatView(AIState state) {
    final isGenerating = state is AIGenerating;
    final partial = isGenerating ? (state.partial ?? '') : '';
    return Column(
      children: [
        Expanded(
          child: _chatHistory.isEmpty && !isGenerating
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '与 AI 对话，可引用当前笔记作为上下文',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _chatHistory.length + (isGenerating ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index < _chatHistory.length) {
                      return _ChatBubble(message: _chatHistory[index]);
                    }
                    return _ChatBubble(
                      message: _ChatMessage(
                        role: _Role.assistant,
                        text: partial,
                      ),
                      isGenerating: true,
                    );
                  },
                ),
        ),
        if (isGenerating)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: TextButton.icon(
              onPressed: _cancelGeneration,
              icon: const Icon(Icons.stop_circle, size: 18),
              label: const Text('停止生成'),
            ),
          ),
      ],
    );
  }

  Widget _buildSummarizeView(AIState state) {
    return _buildActionView(
      state: state,
      kind: AIResultKind.summarize,
      actionLabel: '生成摘要',
      styleSelector: _buildSummaryStyleSelector(),
      onAction: _summarize,
      emptyHint: '点击"生成摘要"为当前笔记生成摘要',
      useSelectedText: widget.selectedText.isNotEmpty,
    );
  }

  Widget _buildRewriteView(AIState state) {
    return _buildActionView(
      state: state,
      kind: AIResultKind.rewrite,
      actionLabel: '改写文本',
      styleSelector: _buildRewriteStyleSelector(),
      onAction: _rewrite,
      emptyHint: widget.selectedText.isNotEmpty
          ? '将改写选中的文本'
          : '将改写整篇笔记内容',
      useSelectedText: widget.selectedText.isNotEmpty,
    );
  }

  Widget _buildTagsView(AIState state) {
    return _buildActionView(
      state: state,
      kind: AIResultKind.tags,
      actionLabel: '推荐标签',
      styleSelector: const SizedBox.shrink(),
      onAction: _suggestTags,
      emptyHint: '基于笔记内容推荐标签',
      useSelectedText: false,
      isTags: true,
    );
  }

  Widget _buildActionView({
    required AIState state,
    required AIResultKind kind,
    required String actionLabel,
    required Widget styleSelector,
    required VoidCallback onAction,
    required String emptyHint,
    required bool useSelectedText,
    bool isTags = false,
  }) {
    final isGenerating = state is AIGenerating;
    final hasResult = state is AIGenerated && state.kind == kind;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (useSelectedText)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '已选中文本：${widget.selectedText.length} 字',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
          styleSelector,
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: isGenerating ? null : onAction,
            icon: isGenerating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(actionLabel),
          ),
          if (isGenerating)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: _cancelGeneration,
                icon: const Icon(Icons.stop_circle, size: 18),
                label: const Text('停止生成'),
              ),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: _buildResultArea(state, hasResult, isGenerating, emptyHint, isTags),
          ),
        ],
      ),
    );
  }

  Widget _buildResultArea(
    AIState state,
    bool hasResult,
    bool isGenerating,
    String emptyHint,
    bool isTags,
  ) {
    if (state is AIError) {
      return Center(
        child: Text(
          state.message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    if (isGenerating) {
      final partial = (state as AIGenerating).partial ?? '';
      if (partial.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      return SingleChildScrollView(child: Text(partial));
    }
    if (hasResult) {
      final generated = state as AIGenerated;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: isTags
                  ? Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: generated.tags
                          .map((tag) => Chip(label: Text(tag)))
                          .toList(),
                    )
                  : Text(generated.result),
            ),
          ),
          if (widget.onApplyResult != null && !isTags)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.tonalIcon(
                onPressed: () => widget.onApplyResult!(generated.result),
                icon: const Icon(Icons.check),
                label: const Text('应用结果'),
              ),
            ),
        ],
      );
    }
    return Center(
      child: Text(
        emptyHint,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSummaryStyleSelector() {
    return Wrap(
      spacing: 8,
      children: SummaryStyle.values.map((style) {
        return ChoiceChip(
          label: Text(_summaryStyleLabel(style)),
          selected: _summaryStyle == style,
          onSelected: (_) => setState(() => _summaryStyle = style),
        );
      }).toList(),
    );
  }

  Widget _buildRewriteStyleSelector() {
    return Wrap(
      spacing: 8,
      children: RewriteStyle.values.map((style) {
        return ChoiceChip(
          label: Text(_rewriteStyleLabel(style)),
          selected: _rewriteStyle == style,
          onSelected: (_) => setState(() => _rewriteStyle = style),
        );
      }).toList(),
    );
  }

  Widget _buildInputArea() {
    if (_mode != AIAssistMode.chat) return const SizedBox.shrink();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chatInputController,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: '输入问题...',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _sendChat(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.send),
              onPressed: _sendChat,
            ),
          ],
        ),
      ),
    );
  }

  String _summaryStyleLabel(SummaryStyle style) {
    switch (style) {
      case SummaryStyle.brief:
        return '简短';
      case SummaryStyle.detailed:
        return '详细';
      case SummaryStyle.bulletPoints:
        return '要点';
      case SummaryStyle.keyInsights:
        return '洞察';
    }
  }

  String _rewriteStyleLabel(RewriteStyle style) {
    switch (style) {
      case RewriteStyle.formal:
        return '正式';
      case RewriteStyle.casual:
        return '口语';
      case RewriteStyle.concise:
        return '简洁';
      case RewriteStyle.expanded:
        return '扩展';
      case RewriteStyle.academic:
        return '学术';
    }
  }
}

/// 对话消息角色
enum _Role { user, assistant }

/// 对话消息
class _ChatMessage {
  final _Role role;
  final String text;

  const _ChatMessage({required this.role, required this.text});
}

/// 对话气泡
class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;
  final bool isGenerating;

  const _ChatBubble({required this.message, this.isGenerating = false});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == _Role.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.smart_toy,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'AI',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (isGenerating) ...[
                      const SizedBox(width: 6),
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    ],
                  ],
                ),
              ),
            Text(message.text),
          ],
        ),
      ),
    );
  }
}
