import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'bloc/todo_bloc.dart';
import 'bloc/todo_event.dart';
import 'bloc/todo_state.dart';
import 'models/todo_model.dart';
import 'widgets/todo_item_tile.dart';
import 'widgets/add_todo_dialog.dart';

class TodoPage extends StatelessWidget {
  const TodoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TodoBloc()..add(LoadTodos()),
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('待办'),
            bottom: const TabBar(
              tabs: [
                Tab(text: '今天'),
                Tab(text: '即将到来'),
                Tab(text: '全部'),
                Tab(text: '已完成'),
              ],
            ),
          ),
          body: BlocBuilder<TodoBloc, TodoState>(
            builder: (context, state) {
              if (state is TodoLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is TodoError) {
                return Center(child: Text(state.message));
              }
              if (state is TodoLoaded) {
                return TabBarView(
                  children: [
                    _buildTodoList(context, state.todayTodos, '今天没有待办'),
                    _buildTodoList(context, state.upcomingTodos, '没有即将到来的待办'),
                    _buildTodoList(context, state.allTodos, '暂无待办'),
                    _buildTodoList(context, state.completedTodos, '没有已完成的待办'),
                  ],
                );
              }
              return const SizedBox();
            },
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddDialog(context),
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }

  Widget _buildTodoList(BuildContext context, List<TodoItem> todos, String emptyMessage) {
    if (todos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(emptyMessage, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: todos.length,
      itemBuilder: (context, index) {
        final todo = todos[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TodoItemTile(
            todo: todo,
            onToggle: (completed) {
              if (completed) {
                context.read<TodoBloc>().add(CompleteTodo(todo.id));
              } else {
                context.read<TodoBloc>().add(UncompleteTodo(todo.id));
              }
            },
            onTap: () => _showEditDialog(context, todo),
            onDelete: () => context.read<TodoBloc>().add(DeleteTodo(todo.id)),
          ),
        );
      },
    );
  }

  void _showAddDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const AddTodoDialog(),
    );
  }

  void _showEditDialog(BuildContext context, TodoItem todo) {
    showDialog(
      context: context,
      builder: (context) => AddTodoDialog(todo: todo),
    );
  }
}
