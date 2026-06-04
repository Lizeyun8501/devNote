import 'package:devnote/core/persistence/models/note_model.dart';

enum NoteSortBy { updatedAt, createdAt, title }

enum NoteViewMode { list, grid }

sealed class NotesState {
  const NotesState();
}

final class NotesInitial extends NotesState {
  const NotesInitial();
}

final class NotesLoaded extends NotesState {
  final List<NoteModel> notes;
  final String? selectedNoteId;
  final String? searchQuery;
  final String? filterTagId;
  final String? filterFolderId;
  final NoteSortBy sortBy;
  final NoteViewMode viewMode;

  const NotesLoaded({
    required this.notes,
    this.selectedNoteId,
    this.searchQuery,
    this.filterTagId,
    this.filterFolderId,
    this.sortBy = NoteSortBy.updatedAt,
    this.viewMode = NoteViewMode.list,
  });

  NotesLoaded copyWith({
    List<NoteModel>? notes,
    String? selectedNoteId,
    String? searchQuery,
    String? filterTagId,
    String? filterFolderId,
    NoteSortBy? sortBy,
    NoteViewMode? viewMode,
  }) {
    return NotesLoaded(
      notes: notes ?? this.notes,
      selectedNoteId: selectedNoteId ?? this.selectedNoteId,
      searchQuery: searchQuery ?? this.searchQuery,
      filterTagId: filterTagId ?? this.filterTagId,
      filterFolderId: filterFolderId ?? this.filterFolderId,
      sortBy: sortBy ?? this.sortBy,
      viewMode: viewMode ?? this.viewMode,
    );
  }
}

final class NotesError extends NotesState {
  final String message;

  const NotesError(this.message);
}
