import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/todo_bloc.dart';
import '../bloc/todo_event.dart';
import '../models/todo_model.dart';

class AddTodoDialog extends StatefulWidget {
  final TodoItem? todo; // 非空时为编辑模式

  const AddTodoDialog({super.key, this.todo});

  @override
  State<AddTodoDialog> createState() => _AddTodoDialogState();
}

class _AddTodoDialogState extends State<AddTodoDialog> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  DateTime? _dueDate;
  DateTime? _reminderTime;
  TodoPriority _priority = TodoPriority.none;
  TodoRepeat _repeat = TodoRepeat.none;

  @override
  void initState() {
    super.initState();
    if (widget.todo != null) {
      _titleController.text = widget.todo!.title;
      _descController.text = widget.todo!.description ?? '';
      _dueDate = widget.todo!.dueDate;
      _reminderTime = widget.todo!.reminderTime;
      _priority = widget.todo!.priority;
      _repeat = widget.todo!.repeat;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    // P2 修复: 两次 await（showDatePicker / showTimePicker）之间及之后，
    // widget 可能已卸载，使用 context 与 setState 前必须检查 mounted。
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueDate ?? DateTime.now()),
    );
    if (!mounted || time == null) return;
    setState(() {
      _dueDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.todo != null ? '编辑待办' : '新建待办'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '标题',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: '描述（可选）',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              // 到期时间
              ListTile(
                leading: const Icon(Icons.event),
                title: Text(_dueDate != null
                    ? '${_dueDate!.month}/${_dueDate!.day} ${_dueDate!.hour}:${_dueDate!.minute.toString().padLeft(2, '0')}'
                    : '设置到期时间'),
                trailing: _dueDate != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _dueDate = null),
                      )
                    : null,
                onTap: _pickDueDate,
                contentPadding: EdgeInsets.zero,
              ),
              // 优先级
              DropdownButtonFormField<TodoPriority>(
                value: _priority,
                decoration: const InputDecoration(
                  labelText: '优先级',
                  border: OutlineInputBorder(),
                ),
                items: TodoPriority.values.map((p) {
                  return DropdownMenuItem(value: p, child: Text(p.label));
                }).toList(),
                onChanged: (v) => setState(() => _priority = v ?? TodoPriority.none),
              ),
              const SizedBox(height: 12),
              // 重复
              DropdownButtonFormField<TodoRepeat>(
                value: _repeat,
                decoration: const InputDecoration(
                  labelText: '重复',
                  border: OutlineInputBorder(),
                ),
                items: TodoRepeat.values.map((r) {
                  return DropdownMenuItem(value: r, child: Text(r.label));
                }).toList(),
                onChanged: (v) => setState(() => _repeat = v ?? TodoRepeat.none),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            if (_titleController.text.isEmpty) return;
            if (widget.todo != null) {
              context.read<TodoBloc>().add(UpdateTodoEvent(
                widget.todo!.copyWith(
                  title: _titleController.text,
                  description: _descController.text.isEmpty ? null : _descController.text,
                  dueDate: _dueDate,
                  priority: _priority,
                  repeat: _repeat,
                ),
              ));
            } else {
              context.read<TodoBloc>().add(AddTodoEvent(
                title: _titleController.text,
                description: _descController.text.isEmpty ? null : _descController.text,
                dueDate: _dueDate,
                priority: _priority,
                repeat: _repeat,
              ));
            }
            Navigator.pop(context);
          },
          child: Text(widget.todo != null ? '保存' : '添加'),
        ),
      ],
    );
  }
}
