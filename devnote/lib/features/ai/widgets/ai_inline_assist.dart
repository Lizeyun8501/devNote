// 编辑器内联 AI 辅助 Widget
//
// 借鉴 Continue.dev 的内联 AI 辅助设计：
// 1. 选中文字后弹出浮动菜单（改写/扩展/总结/翻译）
// 2. Tab 键接受 AI 补全建议
//
// 来源: https://github.com/continuedev/continue
//
// 设计要点：
// - 通过 [AIInlineAssistController] 与编辑器解耦，编辑器负责文本操作
// - 补全建议以灰色幽灵文本形式展示，Tab 接受、Esc 拒绝
// - 选区菜单通过 Overlay 浮动展示，避免侵入编辑器布局

import 'package:flutter/material.dart';

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/ai/ai_service.dart';

/// 内联 AI 操作类型
enum AIInlineAction {
  /// 改写
  rewrite,

  /// 扩展
  expand,

  /// 总结
  summarize,

  /// 翻译为英文
  translate,
}

/// 内联 AI 辅助控制器
///
/// 编辑器持有此控制器，通过 [requestCompletion] 触发补全，
/// 通过 [acceptCompletion] / [dismissCompletion] 接受/拒绝建议。
class AIInlineAssistController extends ChangeNotifier {
  AIInlineAssistController();

  final AIService _aiService = getIt<AIService>();

  /// 当前补全建议（幽灵文本）
  String _suggestion = '';
  String get suggestion => _suggestion;

  /// 是否正在生成补全
  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  /// 是否有可接受的补全建议
  bool get hasSuggestion => _suggestion.isNotEmpty;

  /// 请求补全
  ///
  /// [prefix] 为光标前的文本，生成结果通过 [suggestion] 暴露。
  Future<void> requestCompletion(String prefix) async {
    if (!_aiService.completeEnabled) return;
    _isGenerating = true;
    _suggestion = '';
    notifyListeners();
    try {
      final result = await _aiService.complete(prefix: prefix);
      _suggestion = result;
    } catch (_) {
      _suggestion = '';
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  /// 接受补全建议，返回建议文本供编辑器插入
  String acceptCompletion() {
    final accepted = _suggestion;
    _suggestion = '';
    notifyListeners();
    return accepted;
  }

  /// 拒绝补全建议
  void dismissCompletion() {
    _suggestion = '';
    notifyListeners();
  }

  /// 对选中文本执行 AI 操作
  ///
  /// 返回处理后的文本，由编辑器替换选区。
  Future<String> processSelection({
    required String selectedText,
    required AIInlineAction action,
  }) async {
    if (selectedText.isEmpty) return '';
    try {
      switch (action) {
        case AIInlineAction.rewrite:
          return await _aiService.rewrite(
            content: selectedText,
            style: RewriteStyle.concise,
          );
        case AIInlineAction.expand:
          return await _aiService.rewrite(
            content: selectedText,
            style: RewriteStyle.expanded,
          );
        case AIInlineAction.summarize:
          return await _aiService.summarize(
            content: selectedText,
            style: SummaryStyle.brief,
          );
        case AIInlineAction.translate:
          return await _aiService.chat(
            prompt: '请将以下文本翻译为英文，仅输出译文：\n\n$selectedText',
          );
      }
    } catch (_) {
      return '';
    }
  }
}

/// 选区 AI 菜单
///
/// 在编辑器选中文本时通过 Overlay 显示，提供改写/扩展/总结/翻译快捷操作。
class AISelectionMenu extends StatelessWidget {
  final VoidCallback onAction;
  final ValueChanged<AIInlineAction> onActionSelected;

  const AISelectionMenu({
    super.key,
    required this.onAction,
    required this.onActionSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MenuButton(
              icon: Icons.edit,
              label: '改写',
              onTap: () => onActionSelected(AIInlineAction.rewrite),
            ),
            _MenuButton(
              icon: Icons.expand,
              label: '扩展',
              onTap: () => onActionSelected(AIInlineAction.expand),
            ),
            _MenuButton(
              icon: Icons.summarize,
              label: '总结',
              onTap: () => onActionSelected(AIInlineAction.summarize),
            ),
            _MenuButton(
              icon: Icons.translate,
              label: '翻译',
              onTap: () => onActionSelected(AIInlineAction.translate),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

/// AI 内联辅助 Widget
///
/// 封装 [AIInlineAssistController] 与幽灵文本渲染逻辑。
/// 编辑器通过 [controller] 驱动补全，通过 [ghostText] 渲染建议。
class AIInlineAssist extends StatefulWidget {
  const AIInlineAssist({
    super.key,
    required this.controller,
    required this.onAcceptSuggestion,
    required this.onDismissSuggestion,
  });

  final AIInlineAssistController controller;

  /// 用户接受补全建议时的回调（编辑器插入建议文本）
  final ValueChanged<String> onAcceptSuggestion;

  /// 用户拒绝补全建议时的回调（编辑器清除幽灵文本）
  final VoidCallback onDismissSuggestion;

  @override
  State<AIInlineAssist> createState() => _AIInlineAssistState();
}

class _AIInlineAssistState extends State<AIInlineAssist> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    // 控制器状态变化时触发重建，由 build 方法渲染当前建议状态
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (!widget.controller.hasSuggestion && !widget.controller.isGenerating) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.controller.isGenerating)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else
                Icon(
                  Icons.auto_awesome,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.controller.isGenerating
                      ? 'AI 补全中...'
                      : '按 Tab 接受补全建议',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (widget.controller.hasSuggestion) ...[
                TextButton(
                  onPressed: () =>
                      widget.onAcceptSuggestion(widget.controller.acceptCompletion()),
                  child: const Text('接受'),
                ),
                TextButton(
                  onPressed: () {
                    widget.controller.dismissCompletion();
                    widget.onDismissSuggestion();
                  },
                  child: const Text('取消'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 显示选区 AI 菜单的 Overlay
///
/// 在编辑器选中文本时调用，[position] 为选区在屏幕中的位置。
OverlayEntry? showAISelectionMenu({
  required BuildContext context,
  required Offset position,
  required ValueChanged<AIInlineAction> onAction,
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => entry.remove(),
          child: const SizedBox.expand(),
        ),
        Positioned(
          left: position.dx,
          top: position.dy,
          child: AISelectionMenu(
            onAction: () => entry.remove(),
            onActionSelected: (action) {
              entry.remove();
              onAction(action);
            },
          ),
        ),
      ],
    ),
  );
  overlay.insert(entry);
  return entry;
}
