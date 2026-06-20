import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/todo_model.dart';

class TodoItemTile extends StatelessWidget {
  final TodoItem todo;
  final Function(bool completed) onToggle;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const TodoItemTile({
    super.key,
    required this.todo,
    required this.onToggle,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdue = todo.isOverdue;
    final priorityColor = Color(todo.priority.color);

    return Card(
      child: ListTile(
        leading: Checkbox(
          value: todo.completed,
          onChanged: (value) => onToggle(value ?? false),
          activeColor: priorityColor,
        ),
        title: Row(
          children: [
            if (todo.priority != TodoPriority.none)
              Container(
                width: 4,
                height: 20,
                margin: const EdgeInsets.only(right: 8),
                color: priorityColor,
              ),
            Expanded(
              child: Text(
                todo.title,
                style: TextStyle(
                  decoration: todo.completed ? TextDecoration.lineThrough : null,
                  color: todo.completed ? Colors.grey : null,
                ),
              ),
            ),
          ],
        ),
        subtitle: _buildSubtitle(context, isOverdue),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'delete') onDelete?.call();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Widget? _buildSubtitle(BuildContext context, bool isOverdue) {
    final parts = <Widget>[];

    if (todo.dueDate != null) {
      parts.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event,
            size: 14,
            color: isOverdue ? Colors.red : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            DateFormat('MM/dd HH:mm').format(todo.dueDate!),
            style: TextStyle(
              fontSize: 12,
              color: isOverdue ? Colors.red : Colors.grey,
            ),
          ),
        ],
      ));
    }

    if (todo.repeat != TodoRepeat.none) {
      parts.add(Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Text(
          todo.repeat.label,
          style: const TextStyle(fontSize: 12, color: Colors.blue),
        ),
      ));
    }

    if (todo.tags.isNotEmpty) {
      parts.add(Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Text(
          todo.tags.map((t) => '#$t').join(' '),
          style: const TextStyle(fontSize: 12, color: Colors.purple),
        ),
      ));
    }

    if (parts.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(children: parts),
    );
  }
}
