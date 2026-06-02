import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/editor/bloc/editor_bloc.dart';
import 'package:devnote/features/editor/bloc/editor_event.dart';
import 'package:devnote/features/editor/bloc/editor_state.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import 'package:devnote/features/editor/services/editor_service.dart';
import 'package:devnote/features/editor/widgets/block_widget.dart';
import 'package:devnote/features/editor/widgets/block_toolbar.dart';

class EditorPage extends StatelessWidget {
  const EditorPage({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => EditorBloc(EditorService())
        ..add(LoadNote(noteId)),
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
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: BlocBuilder<EditorBloc, EditorState>(
          builder: (context, state) {
            final title = state is EditorLoaded ? '编辑笔记' : '新建笔记';
            return Text(title);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
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
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    child: Column(
                      children: [
                        TextField(
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
                        const SizedBox(height: 16),
                        ...state.blocks.map((block) => _buildBlockWithKeyboard(
                              context,
                              block,
                              state,
                            )),
                      ],
                    ),
                  ),
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
}
