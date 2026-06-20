import '../models/todo_model.dart';

abstract class TodoState {}

class TodoInitial extends TodoState {}
class TodoLoading extends TodoState {}

class TodoLoaded extends TodoState {
  final List<TodoItem> allTodos;
  final List<TodoItem> todayTodos;
  final List<TodoItem> upcomingTodos;
  final List<TodoItem> completedTodos;

  TodoLoaded({
    required this.allTodos,
    required this.todayTodos,
    required this.upcomingTodos,
    required this.completedTodos,
  });
}

class TodoError extends TodoState {
  final String message;
  TodoError(this.message);
}
