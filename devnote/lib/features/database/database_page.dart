import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/database/bloc/database_bloc.dart';
import 'package:devnote/features/database/bloc/database_event.dart';
import 'package:devnote/features/database/bloc/database_state.dart';
import 'package:devnote/features/database/database_service.dart';
import 'package:devnote/features/database/models/comment_model.dart';
import 'package:devnote/features/database/widgets/table_view.dart';
import 'package:devnote/features/database/widgets/kanban_view.dart';
import 'package:devnote/features/database/widgets/calendar_view.dart';
import 'package:devnote/features/database/widgets/gallery_view_widget.dart';
import 'package:devnote/features/database/widgets/comment_panel.dart';
import 'package:devnote/features/database/widgets/filter_panel.dart';
import 'package:devnote/features/database/widgets/sort_panel.dart';

class DatabasePage extends StatelessWidget {
  const DatabasePage({super.key, required this.databaseId});

  final String databaseId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DatabaseBloc(getIt<DatabaseService>())
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
          // P1-6: 行内评论入口
          IconButton(
            icon: const Icon(Icons.comment),
            onPressed: () => _showRecordPickerForComments(context),
          ),
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
              const PopupMenuItem(value: 'Gallery', child: Text('画廊视图')),
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
      case 'Gallery':
        return _buildGalleryView(state);
      default:
        return TableView(
          database: state.database,
          filters: state.activeFilters,
          sorts: state.activeSorts,
        );
    }
  }

  /// P1-6: 构建画廊视图
  /// 自动检测封面字段（URL 类型）和标题字段（Text 类型）
  Widget _buildGalleryView(DatabaseDetailLoaded state) {
    final database = state.database;
    final coverField =
        database.fields.where((f) => f.fieldType == 'URL').firstOrNull;
    final titleField =
        database.fields.where((f) => f.fieldType == 'Text').firstOrNull;

    return GalleryViewWidget(
      records: database.rows,
      fields: database.fields,
      coverFieldId: coverField?.id,
      titleFieldId: titleField?.id,
      onAddRecord: () => _addRow(context),
      onRecordTap: (recordId) => _showCommentPanel(context, recordId),
      onRecordLongPress: (recordId) => _showCommentPanel(context, recordId),
    );
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

  /// P1-6: 显示记录选择器，选择后打开评论面板
  void _showRecordPickerForComments(BuildContext context) {
    final state = context.read<DatabaseBloc>().state;
    if (state is! DatabaseDetailLoaded) return;
    final database = state.database;
    if (database.rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无记录')),
      );
      return;
    }
    final titleField =
        database.fields.where((f) => f.fieldType == 'Text').firstOrNull;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择记录查看评论',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ...database.rows.map((row) {
              String title = '未命名';
              if (titleField != null) {
                final cell = row.cells
                    .where((c) => c.fieldId == titleField.id)
                    .firstOrNull;
                title = cell?.value?.toString() ?? '未命名';
              }
              return ListTile(
                leading: const Icon(Icons.note),
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.comment),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showCommentPanel(context, row.id);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  /// P1-6: 显示评论面板（右侧侧边栏）
  void _showCommentPanel(BuildContext context, String recordId) {
    final commentService = getIt<CommentService>();
    showDialog(
      context: context,
      builder: (ctx) => _CommentPanelDialog(
        commentService: commentService,
        recordId: recordId,
      ),
    );
  }
}

/// P1-6: 评论面板对话框 —— 包装 CommentPanel，管理评论状态的刷新
class _CommentPanelDialog extends StatefulWidget {
  final CommentService commentService;
  final String recordId;

  const _CommentPanelDialog({
    required this.commentService,
    required this.recordId,
  });

  @override
  State<_CommentPanelDialog> createState() => _CommentPanelDialogState();
}

class _CommentPanelDialogState extends State<_CommentPanelDialog> {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        child: SizedBox(
          height: MediaQuery.of(context).size.height,
          child: CommentPanel(
            recordId: widget.recordId,
            comments: widget.commentService.getComments(widget.recordId),
            currentUserId: 'current-user',
            currentUsername: '我',
            onAddComment: (content, replyTo) {
              widget.commentService.addComment(
                recordId: widget.recordId,
                userId: 'current-user',
                username: '我',
                content: content,
                replyToCommentId: replyTo,
              );
              setState(() {});
            },
            onUpdateComment: (commentId, newContent) {
              widget.commentService.updateComment(
                widget.recordId,
                commentId,
                newContent,
              );
              setState(() {});
            },
            onDeleteComment: (commentId) {
              widget.commentService.deleteComment(
                widget.recordId,
                commentId,
              );
              setState(() {});
            },
          ),
        ),
      ),
    );
  }
}
