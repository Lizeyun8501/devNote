import 'dart:convert';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/todo_model.dart';
import 'notification_service.dart';

/// 待办服务
class TodoService {
  static const _todosKey = 'todos_list';
  final _uuid = const Uuid();
  final NotificationService _notificationService = getIt<NotificationService>();

  List<TodoItem> _cache = [];

  /// 获取所有待办
  Future<List<TodoItem>> getAllTodos() async {
    if (_cache.isNotEmpty) return _cache;
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_todosKey);
    if (jsonStr == null) return [];
    final list = jsonDecode(jsonStr) as List;
    _cache = list.map((e) => TodoItem.fromJson(e as Map<String, dynamic>)).toList();
    return _cache;
  }

  /// 获取未完成的待办
  Future<List<TodoItem>> getPendingTodos() async {
    final todos = await getAllTodos();
    return todos.where((t) => !t.completed).toList()
      ..sort((a, b) {
        // 按优先级降序
        final priorityCompare = b.priority.value.compareTo(a.priority.value);
        if (priorityCompare != 0) return priorityCompare;
        // 按到期时间升序
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
  }

  /// 获取今天到期的待办
  Future<List<TodoItem>> getTodayTodos() async {
    final todos = await getAllTodos();
    return todos.where((t) => !t.completed && t.isDueToday).toList();
  }

  /// 获取已过期的待办
  Future<List<TodoItem>> getOverdueTodos() async {
    final todos = await getAllTodos();
    return todos.where((t) => !t.completed && t.isOverdue).toList();
  }

  /// 获取已完成的待办
  Future<List<TodoItem>> getCompletedTodos() async {
    final todos = await getAllTodos();
    return todos.where((t) => t.completed).toList()
      ..sort((a, b) => (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt));
  }

  /// 添加待办
  Future<TodoItem> addTodo({
    required String title,
    String? description,
    String? noteId,
    String? blockId,
    DateTime? dueDate,
    DateTime? reminderTime,
    TodoPriority priority = TodoPriority.none,
    TodoRepeat repeat = TodoRepeat.none,
    List<String> tags = const [],
  }) async {
    final todo = TodoItem(
      id: _uuid.v4(),
      title: title,
      description: description,
      noteId: noteId,
      blockId: blockId,
      dueDate: dueDate,
      reminderTime: reminderTime,
      priority: priority,
      repeat: repeat,
      tags: tags,
    );

    _cache.add(todo);
    await _save();

    // 调度提醒通知
    if (reminderTime != null) {
      await _notificationService.scheduleTodoReminder(todo);
    }

    return todo;
  }

  /// 更新待办
  Future<void> updateTodo(TodoItem todo) async {
    final index = _cache.indexWhere((t) => t.id == todo.id);
    if (index >= 0) {
      // 取消旧提醒
      final oldTodo = _cache[index];
      if (oldTodo.reminderTime != null) {
        await _notificationService.cancelTodoReminder(oldTodo.id);
      }

      _cache[index] = todo;
      await _save();

      // 调度新提醒
      if (todo.reminderTime != null && !todo.completed) {
        await _notificationService.scheduleTodoReminder(todo);
      }
    }
  }

  /// 完成待办
  Future<void> completeTodo(String todoId) async {
    final index = _cache.indexWhere((t) => t.id == todoId);
    if (index >= 0) {
      final todo = _cache[index];
      _cache[index] = todo.copyWith(
        completed: true,
        completedAt: DateTime.now(),
      );
      await _save();

      // 取消提醒
      await _notificationService.cancelTodoReminder(todoId);

      // 如果是重复待办，创建下一次
      if (todo.repeat != TodoRepeat.none && todo.dueDate != null) {
        final nextDate = todo.nextRepeatDate;
        if (nextDate != null) {
          await addTodo(
            title: todo.title,
            description: todo.description,
            noteId: todo.noteId,
            dueDate: nextDate,
            reminderTime: todo.reminderTime != null
                ? DateTime(nextDate.year, nextDate.month, nextDate.day,
                    todo.reminderTime!.hour, todo.reminderTime!.minute)
                : null,
            priority: todo.priority,
            repeat: todo.repeat,
            tags: todo.tags,
          );
        }
      }
    }
  }

  /// 取消完成
  Future<void> uncompleteTodo(String todoId) async {
    final index = _cache.indexWhere((t) => t.id == todoId);
    if (index >= 0) {
      final todo = _cache[index];
      _cache[index] = todo.copyWith(
        completed: false,
        clearCompleted: true,
      );
      await _save();

      // 重新调度提醒
      if (todo.reminderTime != null) {
        await _notificationService.scheduleTodoReminder(_cache[index]);
      }
    }
  }

  /// 删除待办
  Future<void> deleteTodo(String todoId) async {
    _cache.removeWhere((t) => t.id == todoId);
    await _save();
    await _notificationService.cancelTodoReminder(todoId);
  }

  /// 从笔记中的任务块创建待办
  Future<TodoItem?> createFromBlock({
    required String noteId,
    required String blockId,
    required String title,
    DateTime? dueDate,
    TodoPriority priority = TodoPriority.none,
  }) async {
    return addTodo(
      title: title,
      noteId: noteId,
      blockId: blockId,
      dueDate: dueDate,
      priority: priority,
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_cache.map((t) => t.toJson()).toList());
    await prefs.setString(_todosKey, jsonStr);
  }
}
