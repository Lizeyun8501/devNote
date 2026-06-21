import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/todo_model.dart';
import '../services/todo_service.dart';
import 'todo_event.dart';
import 'todo_state.dart';

class TodoBloc extends Bloc<TodoEvent, TodoState> {
  final TodoService _todoService;

  // P1 修复 (P1-5): 通过构造函数注入 TodoService，替代 getIt Service Locator 反模式
  TodoBloc(this._todoService) : super(TodoInitial()) {
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
    // P1 架构修复: 添加 try-catch，失败时 emit TodoError 让 UI 感知
    try {
      await _todoService.addTodo(
        title: event.title,
        description: event.description,
        dueDate: event.dueDate,
        reminderTime: event.reminderTime,
        priority: event.priority,
        repeat: event.repeat,
      );
      add(LoadTodos());
    } catch (e) {
      emit(TodoError(e.toString()));
    }
  }

  Future<void> _onUpdate(UpdateTodoEvent event, Emitter<TodoState> emit) async {
    try {
      await _todoService.updateTodo(event.todo);
      add(LoadTodos());
    } catch (e) {
      emit(TodoError(e.toString()));
    }
  }

  Future<void> _onComplete(CompleteTodo event, Emitter<TodoState> emit) async {
    try {
      await _todoService.completeTodo(event.todoId);
      add(LoadTodos());
    } catch (e) {
      emit(TodoError(e.toString()));
    }
  }

  Future<void> _onUncomplete(UncompleteTodo event, Emitter<TodoState> emit) async {
    try {
      await _todoService.uncompleteTodo(event.todoId);
      add(LoadTodos());
    } catch (e) {
      emit(TodoError(e.toString()));
    }
  }

  Future<void> _onDelete(DeleteTodo event, Emitter<TodoState> emit) async {
    try {
      await _todoService.deleteTodo(event.todoId);
      add(LoadTodos());
    } catch (e) {
      emit(TodoError(e.toString()));
    }
  }
}
