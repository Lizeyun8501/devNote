import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/database/bloc/database_bloc.dart';
import 'package:devnote/features/database/bloc/database_event.dart';
import 'package:devnote/features/database/bloc/database_state.dart';
import 'package:devnote/features/database/database_service.dart';
import 'package:devnote/features/database/widgets/table_view.dart';
import 'package:devnote/features/database/widgets/kanban_view.dart';
import 'package:devnote/features/database/widgets/calendar_view.dart';
import 'package:devnote/features/database/widgets/filter_panel.dart';
import 'package:devnote/features/database/widgets/sort_panel.dart';

class DatabasePage extends StatelessWidget {
  const DatabasePage({super.key, required this.databaseId});

  final String databaseId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DatabaseBloc(DatabaseService())
        ..add(LoadDatabaseDetail(databaseId)),
      child: const _DatabaseView(),
    );
  }
}

class _DatabaseView extends StatefulWidget {
  const _DatabaseView();

  @override
  State<_DatabaseView> createState() => _DatabaseViewState();
}

class _DatabaseViewState extends State<_DatabaseView> {
  String _currentViewType = 'Table';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: BlocBuilder<DatabaseBloc, DatabaseState>(
          builder: (context, state) {
            if (state is DatabaseDetailLoaded) {
              return Text(state.database.name);
            }
            return const Text('数据库');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterPanel(context),
          ),
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => _showSortPanel(context),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _currentViewType = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'Table', child: Text('表格视图')),
              const PopupMenuItem(value: 'Kanban', child: Text('看板视图')),
              const PopupMenuItem(value: 'Calendar', child: Text('日历视图')),
            ],
          ),
        ],
      ),
      body: BlocBuilder<DatabaseBloc, DatabaseState>(
        builder: (context, state) {
          if (state is DatabaseLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is DatabaseError) {
            return Center(child: Text('Error: ${state.message}'));
          }
          if (state is DatabaseDetailLoaded) {
            return _buildView(state);
          }
          return const SizedBox.shrink();
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addRow(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildView(DatabaseDetailLoaded state) {
    switch (_currentViewType) {
      case 'Kanban':
        return KanbanView(
          database: state.database,
          filters: state.activeFilters,
        );
      case 'Calendar':
        return CalendarView(
          database: state.database,
          filters: state.activeFilters,
        );
      default:
        return TableView(
          database: state.database,
          filters: state.activeFilters,
          sorts: state.activeSorts,
        );
    }
  }

  void _addRow(BuildContext context) {
    final state = context.read<DatabaseBloc>().state;
    if (state is DatabaseDetailLoaded) {
      context.read<DatabaseBloc>().add(AddRow(databaseId: state.database.id));
    }
  }

  void _showFilterPanel(BuildContext context) {
    final state = context.read<DatabaseBloc>().state;
    if (state is! DatabaseDetailLoaded) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FilterPanel(
        fields: state.database.fields,
        activeFilters: state.activeFilters,
        onApply: (filters) {
          context.read<DatabaseBloc>().add(ApplyFilters(
                databaseId: state.database.id,
                filters: filters
                    .map((f) => {
                          'fieldId': f.fieldId,
                          'operator': f.operator,
                          'value': f.value,
                        })
                    .toList(),
              ));
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  void _showSortPanel(BuildContext context) {
    final state = context.read<DatabaseBloc>().state;
    if (state is! DatabaseDetailLoaded) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SortPanel(
        fields: state.database.fields,
        activeSorts: state.activeSorts,
        onApply: (sorts) {
          context.read<DatabaseBloc>().add(ApplySorts(
                databaseId: state.database.id,
                sorts: sorts
                    .map((s) => {
                          'fieldId': s.fieldId,
                          'direction': s.direction,
                        })
                    .toList(),
              ));
          Navigator.of(ctx).pop();
        },
      ),
    );
  }
}
