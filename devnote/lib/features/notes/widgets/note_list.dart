import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:devnote/features/notes/bloc/notes_bloc.dart';
import 'package:devnote/features/notes/bloc/notes_event.dart';
import 'package:devnote/features/notes/bloc/notes_state.dart';
import 'package:devnote/features/notes/widgets/note_card.dart';
import 'package:devnote/features/notes/widgets/swipeable_note_card.dart';
import 'package:devnote/core/persistence/models/note_model.dart';
import 'package:devnote/core/widgets/virtual_list_view.dart';
import 'package:devnote/core/utils/performance_utils.dart';

class NoteList extends StatelessWidget {
  const NoteList({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotesBloc, NotesState>(
      builder: (context, state) {
        if (state is NotesLoaded) {
          return Column(
            children: [
              _NoteListToolbar(viewMode: state.viewMode, sortBy: state.sortBy),
              Expanded(
                child: state.viewMode == NoteViewMode.list
                    ? _buildListView(context, state.notes, state.selectedNoteId)
                    : _buildGridView(context, state.notes, state.selectedNoteId),
              ),
            ],
          );
        }
        if (state is NotesError) {
          return Center(child: Text(state.message));
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  // 使用 scrollable_positioned_list 替代自研 VirtualScrollView
  // 借鉴 Google 官方维护的 ScrollablePositionedList:
  // https://pub.dev/packages/scrollable_positioned_list
  // 优势：支持 scrollToIndex/jumpToIndex，性能经过大规模验证
  //
  // P1-8: 移动端体验打磨 —— 移动设备使用 SwipeableNoteCard + VirtualListView
  // 左滑删除、右滑收藏，虚拟滚动提升长列表性能；桌面端保持原有实现不变
  Widget _buildListView(BuildContext context, List<NoteModel> notes, String? selectedNoteId) {
    if (notes.isEmpty) {
      return Semantics(
        label: '暂无笔记',
        child: const Center(child: Text('暂无笔记')),
      );
    }
    // 移动端：滑动手势 + 虚拟滚动
    if (PerformanceUtils.isMobile(context)) {
      return Semantics(
        label: '笔记列表',
        child: VirtualListView<NoteModel>(
          items: notes,
          itemExtent: 100,
          padding: const EdgeInsets.all(8),
          itemBuilder: (context, note, index) {
            return SwipeableNoteCard(
              isFavorite: false, // NoteModel 暂无 isFavorite 字段，预留接口
              onDelete: () => _confirmDeleteNote(context, note.id),
              onToggleFavorite: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('收藏功能开发中')),
                );
              },
              child: NoteCard(
                note: note,
                isSelected: note.id == selectedNoteId,
              ),
            );
          },
        ),
      );
    }
    // 桌面端：保持原有 ScrollablePositionedList 实现
    return Semantics(
      label: '笔记列表',
      child: ScrollablePositionedList.builder(
        itemCount: notes.length,
        itemBuilder: (context, index) {
          return NoteCard(
            note: notes[index],
            isSelected: notes[index].id == selectedNoteId,
          );
        },
      ),
    );
  }

  /// 移动端左滑删除确认对话框
  void _confirmDeleteNote(BuildContext context, String noteId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除笔记'),
        content: const Text('确定要删除这篇笔记吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              context.read<NotesBloc>().add(DeleteNote(noteId));
              Navigator.pop(dialogContext);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(BuildContext context, List<NoteModel> notes, String? selectedNoteId) {
    if (notes.isEmpty) {
      return Semantics(
        label: '暂无笔记',
        child: const Center(child: Text('暂无笔记')),
      );
    }
    return Semantics(
      label: '笔记网格',
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 280,
          childAspectRatio: 1.4,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: notes.length,
        itemBuilder: (context, index) {
          return NoteCard(
            note: notes[index],
            isSelected: notes[index].id == selectedNoteId,
          );
        },
      ),
    );
  }
}

class _NoteListToolbar extends StatelessWidget {
  const _NoteListToolbar({
    required this.viewMode,
    required this.sortBy,
  });

  final NoteViewMode viewMode;
  final NoteSortBy sortBy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Semantics(
            label: viewMode == NoteViewMode.list ? '切换为网格视图' : '切换为列表视图',
            child: IconButton(
              icon: Icon(viewMode == NoteViewMode.list ? Icons.view_list : Icons.grid_view),
              onPressed: () {
                final newMode = viewMode == NoteViewMode.list
                    ? NoteViewMode.grid
                    : NoteViewMode.list;
                context.read<NotesBloc>().add(ChangeViewMode(newMode));
              },
              tooltip: viewMode == NoteViewMode.list ? '网格视图' : '列表视图',
            ),
          ),
          const SizedBox(width: 4),
          Semantics(
            label: '排序',
            hint: '选择笔记排序方式',
            child: PopupMenuButton<NoteSortBy>(
              icon: const Icon(Icons.sort),
              tooltip: '排序',
              initialValue: sortBy,
              onSelected: (value) {
                context.read<NotesBloc>().add(ChangeSortBy(value));
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: NoteSortBy.updatedAt, child: Text('按修改时间')),
                const PopupMenuItem(value: NoteSortBy.createdAt, child: Text('按创建时间')),
                const PopupMenuItem(value: NoteSortBy.title, child: Text('按标题')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
