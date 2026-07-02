import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/editor/bloc/editor_bloc.dart';
import 'package:devnote/features/editor/bloc/editor_event.dart';
import 'package:devnote/features/editor/bloc/editor_state.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import 'package:devnote/features/editor/services/editor_service.dart';
import 'package:devnote/features/editor/services/timeline_recorder_service.dart';
import 'package:devnote/features/editor/widgets/block_widget.dart';
import 'package:devnote/features/editor/widgets/block_toolbar.dart';
import 'package:devnote/features/editor/widgets/math_ink_dialog.dart';
import 'package:devnote/features/editor/widgets/voice_recorder_widget.dart';
import 'package:devnote/features/editor/widgets/editor_shortcuts.dart';
import 'package:devnote/features/sync/realtime/realtime_collab_service.dart';
import 'package:devnote/core/performance/virtual_scroll_controller.dart';

// P1 修复 (P1-3): 移除对 notes 模块的直接 UI 依赖，
// 改为通过回调注入 VersionHistoryPage 和 ShareNoteDialog 的构造，
// 打破 editor → notes 方向的循环依赖。
// 回调由组合根（feature_routes.dart）提供，该层可合法依赖两个模块。

/// 版本历史展示回调
///
/// 由组合根提供实现，负责构造并展示 VersionHistoryPage。
/// [onRestore] 由 editor 侧提供，用于将恢复的内容写回 EditorBloc。
typedef ShowVersionHistoryCallback = void Function(
  BuildContext context,
  String noteId,
  String currentContent,
  void Function(String) onRestore,
);

/// 分享笔记回调
///
/// 由组合根提供实现，负责构造并展示 ShareNoteDialog。
typedef ShareNoteCallback = void Function(
  BuildContext context,
  String noteId,
  String title,
  String content,
);

class EditorPage extends StatelessWidget {
  const EditorPage({
    super.key,
    required this.noteId,
    this.onShowVersionHistory,
    this.onShareNote,
  });

  final String noteId;

  // P1 修复 (P1-3): 通过回调注入 UI 依赖，打破 editor → notes 循环依赖
  final ShowVersionHistoryCallback? onShowVersionHistory;
  final ShareNoteCallback? onShareNote;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => EditorBloc(
        getIt<EditorService>(),
        collabService: getIt<RealtimeCollabService>(),
        timelineRecorderService: getIt<TimelineRecorderService>(),
      )..add(LoadNote(noteId)),
      child: const _EditorView(),
    );
  }
}

class _EditorView extends StatefulWidget {
  const _EditorView();

  @override
  State<_EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<_EditorView> {
  late final TextEditingController _titleController;
  final VirtualScrollController _virtualScrollController = VirtualScrollController();
  static const double _blockHeight = 80.0;

  /// 时间轴录音计时器（每秒刷新已录时长显示）
  Timer? _recordingTimer;
  Duration _recordingElapsed = Duration.zero;

  /// 各 block 的 GlobalKey，用于点击时间轴标记时滚动定位到对应文本块
  final Map<String, GlobalKey> _blockKeys = {};

  /// P1 修复 (F3): 各 block 的 FocusNode 缓存。
  /// 原实现每次 rebuild 都在 _buildBlockWithKeyboard 中 new FocusNode()，
  /// 旧 FocusNode 永不 dispose，造成内存泄漏。现按 blockId 复用，统一在 dispose 中释放。
  final Map<String, FocusNode> _blockFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _titleController.dispose();
    _virtualScrollController.dispose();
    // P1 修复 (F3): 释放所有缓存的 FocusNode，避免内存泄漏
    for (final node in _blockFocusNodes.values) {
      node.dispose();
    }
    _blockFocusNodes.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<EditorBloc, EditorState>(
      listenWhen: (prev, curr) =>
          prev is EditorLoaded &&
          curr is EditorLoaded &&
          prev.isTimelineRecording != curr.isTimelineRecording,
      listener: (context, state) {
        if (state is EditorLoaded && state.isTimelineRecording) {
          _startRecordingTimer();
        } else {
          _stopRecordingTimer();
        }
      },
      child: EditorShortcuts(
        onSave: () {
          // Save is handled automatically by the bloc on each change
        },
        onUndo: () => context.read<EditorBloc>().add(UndoEvent()),
        onRedo: () => context.read<EditorBloc>().add(RedoEvent()),
        onBold: _applyBold,
        onItalic: _applyItalic,
        onLink: _insertLink,
        onSearch: _searchInNote,
        child: Scaffold(
        appBar: AppBar(
          leading: Semantics(
            label: '返回',
            hint: '返回上一页',
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          title: BlocBuilder<EditorBloc, EditorState>(
            // P2-4: 仅在 state 类型变化时重建标题（EditorLoaded ↔ 其他），
            // 避免 blocks 内容编辑时频繁重建 AppBar 标题。
            buildWhen: (previous, current) =>
                previous.runtimeType != current.runtimeType,
            builder: (context, state) {
              final title = state is EditorLoaded ? '编辑笔记' : '新建笔记';
              return Text(title);
            },
          ),
          actions: [
            BlocBuilder<EditorBloc, EditorState>(
              // P2-4: 仅在 state 类型变化或 blocks 数量变化时重建版本历史按钮，
              // 避免 blocks 内容编辑时频繁重建整个 actions 区域。
              buildWhen: (previous, current) {
                if (previous.runtimeType != current.runtimeType) return true;
                if (previous is EditorLoaded && current is EditorLoaded) {
                  return previous.blocks.length != current.blocks.length;
                }
                return false;
              },
              builder: (context, state) {
                if (state is! EditorLoaded) {
                  return const SizedBox.shrink();
                }
                return Semantics(
                  label: '版本历史',
                  hint: '查看笔记版本历史',
                  child: IconButton(
                    icon: const Icon(Icons.history),
                    tooltip: '版本历史',
                    onPressed: onShowVersionHistory == null
                        ? null
                        : () {
                            final currentContent =
                                state.blocks.map((b) => b.content).join('\n\n');
                            // P1 修复 (P1-3): 通过回调注入而非直接构造 VersionHistoryPage
                            onShowVersionHistory!(
                              context,
                              state.noteId,
                              currentContent,
                              (content) {
                                context
                                    .read<EditorBloc>()
                                    .add(RestoreContent(content));
                              },
                            );
                          },
                  ),
                );
              },
            ),
            Semantics(
              label: '更多选项',
              hint: '显示更多操作',
              child: IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: _showMoreActions,
              ),
            ),
          ],
        ),
        body: BlocBuilder<EditorBloc, EditorState>(
          builder: (context, state) {
            if (state is EditorLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is EditorError) {
              return Center(child: Text('Error: ${state.message}'));
            }

            if (state is EditorLoaded) {
              final blockCount = state.blocks.length;
              final useVirtualScroll = blockCount > 50;

              return Column(
                children: [
                  if (state.isTimelineRecording) _buildRecordingBanner(context),
                  Expanded(
                    child: useVirtualScroll
                        ? _buildVirtualScrollEditor(context, state)
                        : _buildSimpleEditor(context, state),
                  ),
                  BlockToolbar(
                    onInsertParagraph: () => _insertBlock(context, state, BlockType.paragraph),
                    onInsertHeading: () => _insertBlock(context, state, BlockType.heading1),
                    onInsertCodeBlock: () => _insertBlock(context, state, BlockType.codeBlock),
                    onInsertList: () => _insertBlock(context, state, BlockType.list),
                    onInsertQuote: () => _insertBlock(context, state, BlockType.quote),
                    onInsertAudio: () => _showVoiceRecorder(context, state),
                    onInsertPdf: () => _insertPdfBlock(context, state),
                    onInsertWhiteboard: () => _insertWhiteboardBlock(context, state),
                    onInsertMathInk: () => _showMathInkDialog(context, state),
                    onTimelineRecord: () => _toggleTimelineRecording(context, state),
                    isTimelineRecording: state.isTimelineRecording,
                  ),
                ],
              );
            }

            return const SizedBox.shrink();
          },
        ),
      ),
      ),
    );
  }

  Widget _buildVirtualScrollEditor(BuildContext context, EditorLoaded state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Column(
        children: [
          Semantics(
            label: '笔记标题',
            child: TextField(
              controller: _titleController,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              decoration: const InputDecoration(
                hintText: '无标题',
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
          const SizedBox(height: 16),
          VirtualScrollView(
            controller: _virtualScrollController,
            itemCount: state.blocks.length,
            itemHeight: _blockHeight,
            itemBuilder: (context, index) {
              return _buildBlockWithKeyboard(
                context,
                state.blocks[index],
                state,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleEditor(BuildContext context, EditorLoaded state) {
    // P2 修复: 清理已删除 block 对应的 GlobalKey 与 FocusNode 缓存，
    // 否则 _blockKeys / _blockFocusNodes 会随编辑过程无限增长（每个被删除/重建的 block 残留一条）。
    final currentBlockIds = state.blocks.map((b) => b.id).toSet();
    _blockKeys.removeWhere((id, _) => !currentBlockIds.contains(id));
    final staleFocusIds = _blockFocusNodes.keys
        .where((id) => !currentBlockIds.contains(id))
        .toList();
    for (final id in staleFocusIds) {
      _blockFocusNodes.remove(id)?.dispose();
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Column(
        children: [
          Semantics(
            label: '笔记标题',
            child: TextField(
              controller: _titleController,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              decoration: const InputDecoration(
                hintText: '无标题',
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...state.blocks.map((block) => _buildBlockWithKeyboard(
                context,
                block,
                state,
              )),
        ],
      ),
    );
  }

  Widget _buildBlockWithKeyboard(BuildContext context, BlockModel block, EditorLoaded state) {
    // 为每个 block 绑定 GlobalKey，用于点击时间轴标记时滚动定位
    final key = _blockKeys.putIfAbsent(block.id, () => GlobalKey());
    // P1 修复 (F3): 按 blockId 复用 FocusNode，避免每次 rebuild 创建新实例导致泄漏
    final focusNode = _blockFocusNodes.putIfAbsent(block.id, () => FocusNode());
    return KeyedSubtree(
      key: key,
      child: KeyboardListener(
        focusNode: focusNode,
        onKeyEvent: (event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              final position = block.position + 1;
              context.read<EditorBloc>().add(InsertBlock(
                    noteId: state.noteId,
                    blockType: BlockType.paragraph,
                    content: '',
                    position: position,
                  ));
            } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
              if (block.content.isEmpty && state.blocks.length > 1) {
                context.read<EditorBloc>().add(DeleteBlock(block.id));
              }
            }
          }
        },
        child: BlockWidget(
          block: block,
          isActive: state.activeBlockId == block.id,
          onContentChanged: (content) {
            context.read<EditorBloc>().add(UpdateBlock(
                  blockId: block.id,
                  content: content,
                ));
          },
          onDelete: () {
            context.read<EditorBloc>().add(DeleteBlock(block.id));
          },
          onTypeChanged: (type) {
            context.read<EditorBloc>().add(ToggleBlockType(
                  blockId: block.id,
                  newType: type,
                ));
          },
          onEnterPressed: () {
            final position = block.position + 1;
            context.read<EditorBloc>().add(InsertBlock(
                  noteId: state.noteId,
                  blockType: BlockType.paragraph,
                  content: '',
                  position: position,
                ));
          },
          onBackspaceAtStart: () {
            if (block.content.isEmpty && state.blocks.length > 1) {
              context.read<EditorBloc>().add(DeleteBlock(block.id));
            }
          },
          onTimelineMarkerTap: (blockId) => _seekToBlock(context, blockId),
        ),
      ),
    );
  }

  void _insertBlock(BuildContext context, EditorLoaded state, BlockType type) {
    context.read<EditorBloc>().add(InsertBlock(
          noteId: state.noteId,
          blockType: type,
          content: '',
          position: state.blocks.length,
        ));
  }

  /// 显示语音录音底部弹窗，录音完成后插入 audio block
  Future<void> _showVoiceRecorder(BuildContext context, EditorLoaded state) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: VoiceRecorderWidget(
            onRecordingComplete: (content) {
              context.read<EditorBloc>().add(InsertBlock(
                    noteId: state.noteId,
                    blockType: BlockType.audio,
                    content: content,
                    position: state.blocks.length,
                  ));
              Navigator.pop(sheetContext);
            },
          ),
        ),
      ),
    );
  }

  /// 选择 PDF 文件并插入 pdf block
  /// content JSON 结构：{url, page_count, current_page, annotations}
  Future<void> _insertPdfBlock(BuildContext context, EditorLoaded state) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result == null || result.files.single.path == null) return;
      final path = result.files.single.path!;
      final content = jsonEncode({
        'url': path,
        'page_count': 0,
        'current_page': 1,
        'annotations': <Map<String, dynamic>>[],
      });
      if (!context.mounted) return;
      context.read<EditorBloc>().add(InsertBlock(
            noteId: state.noteId,
            blockType: BlockType.pdf,
            content: content,
            position: state.blocks.length,
          ));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('插入 PDF 失败: $e')),
        );
      }
    }
  }

  /// 插入白板块 —— content 初始化为空元素列表的 JSON
  /// 后续在白板页面编辑后通过 WhiteboardService 持久化
  void _insertWhiteboardBlock(BuildContext context, EditorLoaded state) {
    const emptyJson = '{"version":1,"elements":[]}';
    context.read<EditorBloc>().add(InsertBlock(
          noteId: state.noteId,
          blockType: BlockType.whiteboard,
          content: emptyJson,
          position: state.blocks.length,
        ));
  }

  /// P2-9: 弹出手写公式识别对话框，识别完成后创建 latex block
  ///
  /// 识别得到的 LaTeX 用 `$$...$$` 包裹为 display 模式后作为 block content 插入。
  Future<void> _showMathInkDialog(
      BuildContext context, EditorLoaded state) async {
    await MathInkDialog.show(
      context,
      onInsert: (latex) {
        final wrapped = latex.isEmpty ? '' : '\$\$$latex\$\$';
        context.read<EditorBloc>().add(InsertBlock(
              noteId: state.noteId,
              blockType: BlockType.latexBlock,
              content: wrapped,
              position: state.blocks.length,
            ));
      },
    );
  }

  // ============================================================
  // 时间轴录音相关
  // ============================================================

  /// 切换时间轴录音状态（开始/停止）
  void _toggleTimelineRecording(BuildContext context, EditorLoaded state) {
    final bloc = context.read<EditorBloc>();
    if (state.isTimelineRecording) {
      bloc.add(const StopTimelineRecording());
    } else {
      final audioBlockId = const Uuid().v4();
      bloc.add(StartTimelineRecording(audioBlockId));
    }
  }

  /// 启动录音计时器，每秒刷新已录时长
  void _startRecordingTimer() {
    _recordingElapsed = Duration.zero;
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _recordingElapsed = Duration(
          milliseconds: getIt<TimelineRecorderService>().currentDurationMs,
        );
      });
    });
  }

  /// 停止录音计时器
  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    if (mounted) {
      setState(() => _recordingElapsed = Duration.zero);
    }
  }

  /// 录音中顶部横幅：显示已录时长与停止按钮
  Widget _buildRecordingBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.red.withAlpha(30),
      child: Row(
        children: [
          const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '正在时间轴录音... ${_formatElapsed(_recordingElapsed)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: () =>
                context.read<EditorBloc>().add(const StopTimelineRecording()),
            child: const Text('停止'),
          ),
        ],
      ),
    );
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 点击时间轴标记：设置该 block 为 active 并滚动定位到对应文本块
  void _seekToBlock(BuildContext context, String blockId) {
    context.read<EditorBloc>().add(SeekToTimelineMarker(blockId));
    final key = _blockKeys[blockId];
    // 在下一帧（bloc 状态更新触发重建后）再读取 context 并滚动定位
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 300),
        );
      }
    });
  }

  void _applyBold() {
    final bloc = context.read<EditorBloc>();
    final state = bloc.state;
    if (state is EditorLoaded && state.activeBlockId != null) {
      final block = state.blocks.firstWhere((b) => b.id == state.activeBlockId);
      final content = block.content;
      final updated = '**$content**';
      bloc.add(UpdateBlock(blockId: block.id, content: updated));
    }
  }

  void _applyItalic() {
    final bloc = context.read<EditorBloc>();
    final state = bloc.state;
    if (state is EditorLoaded && state.activeBlockId != null) {
      final block = state.blocks.firstWhere((b) => b.id == state.activeBlockId);
      final updated = '_${block.content}_';
      bloc.add(UpdateBlock(blockId: block.id, content: updated));
    }
  }

  Future<void> _insertLink() async {
    final controller = TextEditingController();
    try {
      final url = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('插入链接'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'https://example.com'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('插入')),
          ],
        ),
      );
      // P2 修复: await 后 widget 可能已卸载，使用 context 前必须检查 mounted
      if (!mounted) return;
      if (url != null && url.isNotEmpty) {
        final bloc = context.read<EditorBloc>();
        final state = bloc.state;
        if (state is EditorLoaded && state.activeBlockId != null) {
          final block = state.blocks.firstWhere((b) => b.id == state.activeBlockId);
          final text = block.content.isEmpty ? '链接' : block.content;
          final link = '[$text]($url)';
          bloc.add(UpdateBlock(blockId: block.id, content: link));
        }
      }
    } finally {
      // P2 修复: 方法内创建的 TextEditingController 必须释放，避免监听器/通知链泄漏
      controller.dispose();
    }
  }

  Future<void> _searchInNote() async {
    final controller = TextEditingController();
    try {
      final keyword = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('在笔记中搜索'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: '输入关键词'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('搜索')),
          ],
        ),
      );
      // P2 修复: await 后 widget 可能已卸载
      if (!mounted) return;
      if (keyword != null && keyword.isNotEmpty) {
        final bloc = context.read<EditorBloc>();
        final state = bloc.state;
        if (state is EditorLoaded) {
          final match = state.blocks.indexWhere((b) => b.content.contains(keyword));
          if (match >= 0) {
            bloc.add(SelectBlock(state.blocks[match].id));
          }
        }
      }
    } finally {
      controller.dispose();
    }
  }

  void _showMoreActions() {
    final bloc = context.read<EditorBloc>();
    final state = bloc.state;
    if (state is! EditorLoaded) return;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制笔记ID'),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: state.noteId));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('笔记ID已复制到剪贴板')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('导出笔记'),
              onTap: () {
                Navigator.pop(context);
                _exportNote(state);
              },
            ),
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('分享笔记'),
              onTap: () {
                Navigator.pop(context);
                _shareNote(state);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除笔记', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteNote(state);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportNote(EditorLoaded state) async {
    final content = state.blocks.map((b) => b.content).join('\n\n');
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出笔记'),
        content: SelectableText(
          content.isEmpty ? '（空笔记）' : content,
          maxLines: 20,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('笔记内容已复制到剪贴板')),
              );
            },
            child: const Text('复制内容'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  /// 分享笔记：打开分享对话框，生成公开链接（支持密码保护和有效期）
  /// P1 修复 (P1-3): 通过回调注入而非直接构造 ShareNoteDialog
  Future<void> _shareNote(EditorLoaded state) async {
    final content = state.blocks.map((b) => b.content).join('\n\n');
    final title = _titleController.text.trim().isEmpty
        ? '无标题'
        : _titleController.text.trim();
    if (onShareNote != null) {
      onShareNote!(context, state.noteId, title, content);
    }
  }

  Future<void> _confirmDeleteNote(EditorLoaded state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除笔记'),
        content: const Text('确定要删除这篇笔记吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    // P2 修复: await 后 widget 可能已卸载，统一在操作 context 前检查 mounted
    if (!mounted) return;
    if (confirmed == true) {
      // Delete all blocks in the note through the bloc
      for (final block in state.blocks) {
        context.read<EditorBloc>().add(DeleteBlock(block.id));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('笔记已删除')),
      );
      Navigator.of(context).pop();
    }
  }
}
