import 'package:equatable/equatable.dart';
import 'package:devnote/core/persistence/models/note_model.dart';

enum NoteSortBy { updatedAt, createdAt, title }

enum NoteViewMode { list, grid }

abstract class NotesState extends Equatable {
  const NotesState();

  @override
  List<Object?> get props => [];
}

class NotesInitial extends NotesState {
  const NotesInitial();
}

class NotesLoaded extends NotesLoadedData {
  const NotesLoaded({
    required super.notes,
    super.selectedNoteId,
    super.searchQuery,
    super.filterTagId,
    super.filterFolderId,
    super.sortBy,
    super.viewMode,
  });
}

abstract class NotesLoadedData extends NotesState {
  final List<NoteModel> notes;
  final String? selectedNoteId;
  final String? searchQuery;
  final String? filterTagId;
  final String? filterFolderId;
  final NoteSortBy sortBy;
  final NoteViewMode viewMode;

  const NotesLoadedData({
    required this.notes,
    this.selectedNoteId,
    this.searchQuery,
    this.filterTagId,
    this.filterFolderId,
    this.sortBy = NoteSortBy.updatedAt,
    this.viewMode = NoteViewMode.list,
  });

  NotesLoadedData copyWith({
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

  @override
  List<Object?> get props => [
        notes,
        selectedNoteId,
        searchQuery,
        filterTagId,
        filterFolderId,
        sortBy,
        viewMode,
      ];
}

class NotesError extends NotesState {
  final String message;

  const NotesError(this.message);

  @override
  List<Object?> get props => [message];
}
