import 'package:equatable/equatable.dart';
import 'package:devnote/features/notes/bloc/notes_state.dart';

abstract class NotesEvent extends Equatable {
  const NotesEvent();

  @override
  List<Object?> get props => [];
}

class LoadNotes extends NotesEvent {
  final String folderId;

  const LoadNotes(this.folderId);

  @override
  List<Object?> get props => [folderId];
}

class CreateNote extends NotesEvent {
  final String title;
  final String folderId;

  const CreateNote({required this.title, required this.folderId});

  @override
  List<Object?> get props => [title, folderId];
}

class DeleteNote extends NotesEvent {
  final String noteId;

  const DeleteNote(this.noteId);

  @override
  List<Object?> get props => [noteId];
}

class SelectNote extends NotesEvent {
  final String noteId;

  const SelectNote(this.noteId);

  @override
  List<Object?> get props => [noteId];
}

class SearchNotes extends NotesEvent {
  final String query;

  const SearchNotes(this.query);

  @override
  List<Object?> get props => [query];
}

class FilterByTag extends NotesEvent {
  final String tagId;

  const FilterByTag(this.tagId);

  @override
  List<Object?> get props => [tagId];
}

class FilterByFolder extends NotesEvent {
  final String folderId;

  const FilterByFolder(this.folderId);

  @override
  List<Object?> get props => [folderId];
}

class ChangeViewMode extends NotesEvent {
  final NoteViewMode viewMode;

  const ChangeViewMode(this.viewMode);

  @override
  List<Object?> get props => [viewMode];
}

class ChangeSortBy extends NotesEvent {
  final NoteSortBy sortBy;

  const ChangeSortBy(this.sortBy);

  @override
  List<Object?> get props => [sortBy];
}
