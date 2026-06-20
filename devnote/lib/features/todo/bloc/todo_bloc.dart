import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../models/todo_model.dart';
import '../services/todo_service.dart';
import 'todo_event.dart';
import 'todo_state.dart';

class TodoBloc extends Bloc<TodoEvent, TodoState> {
  final TodoService _todoService = getIt<TodoService>();

  TodoBloc() : super(TodoInitial()) {
    on<LoadTodos>(_onLoad);
    on<AddTodoEvent>(_onAdd);
    on<UpdateTodoEvent>(_onUpdate);
    on<CompleteTodo>(_onComplete);
    on<UncompleteTodo>(_onUncomplete);
    on<DeleteTodo>(_onDelete);
  }

  Future<void> _onLoad(LoadTodos event, Emitter<TodoState> emit) async {
    emit(TodoLoading());
    try {
      final all = await _todoService.getAllTodos();
      final today = await _todoService.getTodayTodos();
      final overdue = await _todoService.getOverdueTodos();
      final completed = await _todoService.getCompletedTodos();

      // 即将到来 = 未完成 + 有到期日 + 未过期 + 非今天
      final upcoming = all
          .where((t) => !t.completed && t.dueDate != null && !t.isDueToday && !t.isOverdue)
          .toList()
        ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

      emit(TodoLoaded(
        allTodos: all.where((t) => !t.completed).toList(),
        todayTodos: [...today, ...overdue],
        upcomingTodos: upcoming,
        completedTodos: completed,
      ));
    } catch (e) {
      emit(TodoError(e.toString()));
    }
  }

  Future<void> _onAdd(AddTodoEvent event, Emitter<TodoState> emit) async {
    await _todoService.addTodo(
      title: event.title,
      description: event.description,
      dueDate: event.dueDate,
      reminderTime: event.reminderTime,
      priority: event.priority,
      repeat: event.repeat,
    );
    add(LoadTodos());
  }

  Future<void> _onUpdate(UpdateTodoEvent event, Emitter<TodoState> emit) async {
    await _todoService.updateTodo(event.todo);
    add(LoadTodos());
  }

  Future<void> _onComplete(CompleteTodo event, Emitter<TodoState> emit) async {
    await _todoService.completeTodo(event.todoId);
    add(LoadTodos());
  }

  Future<void> _onUncomplete(UncompleteTodo event, Emitter<TodoState> emit) async {
    await _todoService.uncompleteTodo(event.todoId);
    add(LoadTodos());
  }

  Future<void> _onDelete(DeleteTodo event, Emitter<TodoState> emit) async {
    await _todoService.deleteTodo(event.todoId);
    add(LoadTodos());
  }
}
