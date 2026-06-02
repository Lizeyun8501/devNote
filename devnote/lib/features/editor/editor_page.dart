import 'package:flutter/material.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.noteId});

  final String noteId;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final FocusNode _contentFocusNode;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = TextEditingController();
    _contentFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
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
        title: Text(
          widget.noteId.isEmpty ? '新建笔记' : '编辑笔记',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      body: Padding(
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
            Expanded(
              child: TextField(
                controller: _contentController,
                focusNode: _contentFocusNode,
                style: Theme.of(context).textTheme.bodyLarge,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: '开始输入...',
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _EditorToolbar(
        onFormatToggle: (_) {},
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({required this.onFormatToggle});

  final void Function(String format) onFormatToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          _ToolbarButton(
            icon: Icons.format_bold,
            tooltip: '粗体',
            onPressed: () => onFormatToggle('bold'),
          ),
          _ToolbarButton(
            icon: Icons.format_italic,
            tooltip: '斜体',
            onPressed: () => onFormatToggle('italic'),
          ),
          _ToolbarButton(
            icon: Icons.format_underlined,
            tooltip: '下划线',
            onPressed: () => onFormatToggle('underline'),
          ),
          _ToolbarButton(
            icon: Icons.code,
            tooltip: '代码',
            onPressed: () => onFormatToggle('code'),
          ),
          _ToolbarButton(
            icon: Icons.format_list_bulleted,
            tooltip: '列表',
            onPressed: () => onFormatToggle('list'),
          ),
          _ToolbarButton(
            icon: Icons.checklist,
            tooltip: '待办',
            onPressed: () => onFormatToggle('checklist'),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}
