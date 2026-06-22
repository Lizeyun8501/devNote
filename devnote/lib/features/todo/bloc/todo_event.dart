import '../models/todo_model.dart';

abstract class TodoEvent {}

class LoadTodos extends TodoEvent {}
class AddTodoEvent extends TodoEvent {
  final String title;
  final String? description;
  final DateTime? dueDate;
  final DateTime? reminderTime;
  final TodoPriority priority;
  final TodoRepeat repeat;
  AddTodoEvent({
    required this.title,
    this.description,
    this.dueDate,
    this.reminderTime,
    this.priority = TodoPriority.none,
    this.repeat = TodoRepeat.none,
  });
}
class UpdateTodoEvent extends TodoEvent {
  final TodoItem todo;
  UpdateTodoEvent(this.todo);
}
class CompleteTodo extends TodoEvent {
  final String todoId;
  CompleteTodo(this.todoId);
}
class UncompleteTodo extends TodoEvent {
  final String todoId;
  UncompleteTodo(this.todoId);
}
class DeleteTodo extends TodoEvent {
  final String todoId;
  DeleteTodo(this.todoId);
}
