import 'package:flutter/material.dart';

class TaskListWidget extends StatefulWidget {
  final String content;
  final ValueChanged<String> onContentChanged;

  const TaskListWidget({
    super.key,
    required this.content,
    required this.onContentChanged,
  });

  @override
  State<TaskListWidget> createState() => _TaskListWidgetState();
}

class _TaskListWidgetState extends State<TaskListWidget> {
  late List<_TaskItem> _items;

  @override
  void initState() {
    super.initState();
    _items = _parseContent(widget.content);
  }

  @override
  void didUpdateWidget(covariant TaskListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _items = _parseContent(widget.content);
    }
  }

  List<_TaskItem> _parseContent(String content) {
    return content.split('\n').where((line) => line.trim().isNotEmpty).map((line) {
      final trimmed = line.replaceFirst(RegExp(r'^\s+'), '');
      final indent = line.length - trimmed.length;
      final indentLevel = indent ~/ 2;

      if (trimmed.startsWith('- [x] ')) {
        return _TaskItem(text: trimmed.substring(6), checked: true, indent: indentLevel);
      }
      if (trimmed.startsWith('- [ ] ')) {
        return _TaskItem(text: trimmed.substring(6), checked: false, indent: indentLevel);
      }
      if (trimmed.startsWith('* [x] ')) {
        return _TaskItem(text: trimmed.substring(6), checked: true, indent: indentLevel);
      }
      if (trimmed.startsWith('* [ ] ')) {
        return _TaskItem(text: trimmed.substring(6), checked: false, indent: indentLevel);
      }
      return _TaskItem(text: trimmed, checked: false, indent: indentLevel);
    }).toList();
  }

  String _serializeItems() {
    return _items.map((item) {
      final prefix = '  ' * item.indent;
      final check = item.checked ? '- [x]' : '- [ ]';
      return '$prefix$check ${item.text}';
    }).join('\n');
  }

  void _toggleItem(int index) {
    setState(() {
      _items[index] = _TaskItem(
        text: _items[index].text,
        checked: !_items[index].checked,
        indent: _items[index].indent,
      );
    });
    widget.onContentChanged(_serializeItems());
  }

  void _addItem() {
    setState(() {
      _items.add(_TaskItem(text: '', checked: false, indent: 0));
    });
    widget.onContentChanged(_serializeItems());
  }

  void _deleteItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
    widget.onContentChanged(_serializeItems());
  }

  void _updateItemText(int index, String text) {
    setState(() {
      _items[index] = _TaskItem(
        text: text,
        checked: _items[index].checked,
        indent: _items[index].indent,
      );
    });
    widget.onContentChanged(_serializeItems());
  }

  void _editItemText(BuildContext context, int index) {
    final controller = TextEditingController(text: _items[index].text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Task'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Task text'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _updateItemText(index, controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _indentItem(int index) {
    setState(() {
      _items[index] = _TaskItem(
        text: _items[index].text,
        checked: _items[index].checked,
        indent: _items[index].indent + 1,
      );
    });
    widget.onContentChanged(_serializeItems());
  }

  void _unindentItem(int index) {
    if (_items[index].indent <= 0) return;
    setState(() {
      _items[index] = _TaskItem(
        text: _items[index].text,
        checked: _items[index].checked,
        indent: _items[index].indent - 1,
      );
    });
    widget.onContentChanged(_serializeItems());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...List.generate(_items.length, (index) => _buildTaskItem(context, index)),
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: InkWell(
              onTap: _addItem,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Add task',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskItem(BuildContext context, int index) {
    final item = _items[index];
    final indent = item.indent * 24.0;

    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: item.checked,
              onChanged: (_) => _toggleItem(index),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              onTap: () => _editItemText(context, index),
              child: Text(
                item.text.isEmpty ? 'Tap to edit...' : item.text,
                style: TextStyle(
                  fontSize: 14,
                  decoration: item.checked ? TextDecoration.lineThrough : TextDecoration.none,
                  color: item.text.isEmpty
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : item.checked
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
          if (item.checked)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 14),
              onPressed: () => _deleteItem(index),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          IconButton(
            icon: const Icon(Icons.format_indent_decrease, size: 14),
            onPressed: item.indent > 0 ? () => _unindentItem(index) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          IconButton(
            icon: const Icon(Icons.format_indent_increase, size: 14),
            onPressed: () => _indentItem(index),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _TaskItem {
  final String text;
  final bool checked;
  final int indent;

  const _TaskItem({
    required this.text,
    required this.checked,
    required this.indent,
  });
}
