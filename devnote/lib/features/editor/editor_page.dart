import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:devnote/features/editor/bloc/editor_bloc.dart';
import 'package:devnote/features/editor/bloc/editor_event.dart';
import 'package:devnote/features/editor/bloc/editor_state.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import 'package:devnote/features/editor/services/editor_service.dart';
import 'package:devnote/features/editor/widgets/block_widget.dart';
import 'package:devnote/features/editor/widgets/block_toolbar.dart';
import 'package:devnote/features/editor/widgets/editor_shortcuts.dart';
import 'package:devnote/features/sync/realtime/realtime_collab_service.dart';
import 'package:devnote/core/performance/virtual_scroll_controller.dart';

class EditorPage extends StatelessWidget {
  const EditorPage({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => EditorBloc(
        EditorService(),
        collabService: getIt<RealtimeCollabService>(),
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

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _virtualScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return EditorShortcuts(
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
            builder: (context, state) {
              final title = state is EditorLoaded ? '编辑笔记' : '新建笔记';
              return Text(title);
            },
          ),
          actions: [
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
                  ),
                ],
              );
            }

            return const SizedBox.shrink();
          },
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
    return KeyboardListener(
      focusNode: FocusNode(),
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
  }

  Future<void> _searchInNote() async {
    final controller = TextEditingController();
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
    if (confirmed == true) {
      // Delete all blocks in the note through the bloc
      for (final block in state.blocks) {
        context.read<EditorBloc>().add(DeleteBlock(block.id));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('笔记已删除')),
        );
        Navigator.of(context).pop();
      }
    }
  }
}
