import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/notes/bloc/notes_bloc.dart';
import 'package:devnote/features/notes/bloc/notes_event.dart';
import 'package:devnote/features/notes/bloc/notes_state.dart';
import 'package:devnote/features/notes/widgets/note_card.dart';
import 'package:devnote/core/persistence/models/note_model.dart';

class NoteList extends StatelessWidget {
  const NoteList({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotesBloc, NotesState>(
      builder: (context, state) {
        if (state is NotesLoadedData) {
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

  Widget _buildListView(BuildContext context, List<NoteModel> notes, String? selectedNoteId) {
    if (notes.isEmpty) {
      return const Center(child: Text('暂无笔记'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        return NoteCard(
          note: notes[index],
          isSelected: notes[index].id == selectedNoteId,
        );
      },
    );
  }

  Widget _buildGridView(BuildContext context, List<NoteModel> notes, String? selectedNoteId) {
    if (notes.isEmpty) {
      return const Center(child: Text('暂无笔记'));
    }
    return GridView.builder(
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
          IconButton(
            icon: Icon(viewMode == NoteViewMode.list ? Icons.view_list : Icons.grid_view),
            onPressed: () {
              final newMode = viewMode == NoteViewMode.list
                  ? NoteViewMode.grid
                  : NoteViewMode.list;
              context.read<NotesBloc>().add(ChangeViewMode(newMode));
            },
            tooltip: viewMode == NoteViewMode.list ? '网格视图' : '列表视图',
          ),
          const SizedBox(width: 4),
          PopupMenuButton<NoteSortBy>(
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
        ],
      ),
    );
  }
}
