import 'dart:developer' as developer;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:devnote/features/notes/bloc/notes_event.dart';
import 'package:devnote/features/notes/bloc/notes_state.dart';
import 'package:devnote/core/persistence/note_repository.dart';
import 'package:devnote/core/persistence/models/note_model.dart';

class NotesBloc extends Bloc<NotesEvent, NotesState> {
  final NoteRepository _noteRepository;
  final _uuid = const Uuid();

  NotesBloc(this._noteRepository) : super(const NotesInitial()) {
    on<LoadNotes>(_onLoadNotes);
    on<CreateNote>(_onCreateNote);
    on<DeleteNote>(_onDeleteNote);
    on<SelectNote>(_onSelectNote);
    on<SearchNotes>(_onSearchNotes);
    on<FilterByTag>(_onFilterByTag);
    on<FilterByFolder>(_onFilterByFolder);
    on<ChangeViewMode>(_onChangeViewMode);
    on<ChangeSortBy>(_onChangeSortBy);
    on<LoadMoreNotes>(_onLoadMoreNotes);
  }

  static const int _pageSize = 20;

  Future<void> _onLoadNotes(LoadNotes event, Emitter<NotesState> emit) async {
    try {
      final notes = await _noteRepository.listNotes(event.folderId);
      final sortedNotes = _sortNotes(notes, NoteSortBy.updatedAt);
      emit(NotesLoaded(
        notes: sortedNotes,
        filterFolderId: event.folderId,
      ));
    } catch (e) {
      emit(NotesError(e.toString()));
    }
  }

  Future<void> _onCreateNote(CreateNote event, Emitter<NotesState> emit) async {
    try {
      final now = DateTime.now();
      final note = NoteModel(
        id: _uuid.v4(),
        title: event.title,
        content: '',
        folderId: event.folderId,
        createdAt: now,
        updatedAt: now,
      );
      await _noteRepository.createNote(note);
      final currentState = state;
      if (currentState is NotesLoadedData) {
        final notes = List<NoteModel>.from(currentState.notes)..insert(0, note);
        emit(currentState.copyWith(notes: notes, selectedNoteId: note.id));
      } else {
        emit(NotesLoaded(notes: [note], selectedNoteId: note.id));
      }
    } catch (e) {
      emit(NotesError(e.toString()));
    }
  }

  Future<void> _onDeleteNote(DeleteNote event, Emitter<NotesState> emit) async {
    try {
      await _noteRepository.deleteNote(event.noteId);
      final currentState = state;
      if (currentState is NotesLoadedData) {
        final notes = currentState.notes.where((n) => n.id != event.noteId).toList();
        emit(currentState.copyWith(
          notes: notes,
          selectedNoteId: currentState.selectedNoteId == event.noteId
              ? null
              : currentState.selectedNoteId,
        ));
      }
    } catch (e) {
      emit(NotesError(e.toString()));
    }
  }

  Future<void> _onSelectNote(SelectNote event, Emitter<NotesState> emit) async {
    final currentState = state;
    if (currentState is NotesLoadedData) {
      emit(currentState.copyWith(selectedNoteId: event.noteId));
    }
  }

  Future<void> _onSearchNotes(SearchNotes event, Emitter<NotesState> emit) async {
    final currentState = state;
    if (currentState is NotesLoadedData) {
      if (event.query.isEmpty) {
        emit(currentState.copyWith(searchQuery: null));
        return;
      }
      final filtered = currentState.notes
          .where((n) =>
              n.title.toLowerCase().contains(event.query.toLowerCase()) ||
              n.content.toLowerCase().contains(event.query.toLowerCase()))
          .toList();
      emit(currentState.copyWith(searchQuery: event.query, notes: filtered));
    }
  }

  Future<void> _onFilterByTag(FilterByTag event, Emitter<NotesState> emit) async {
    final currentState = state;
    if (currentState is NotesLoadedData) {
      emit(currentState.copyWith(filterTagId: event.tagId));
    }
  }

  Future<void> _onFilterByFolder(FilterByFolder event, Emitter<NotesState> emit) async {
    try {
      final notes = await _noteRepository.listNotes(event.folderId);
      final currentState = state;
      if (currentState is NotesLoadedData) {
        emit(currentState.copyWith(
          notes: _sortNotes(notes, currentState.sortBy),
          filterFolderId: event.folderId,
        ));
      } else {
        emit(NotesLoaded(
          notes: _sortNotes(notes, NoteSortBy.updatedAt),
          filterFolderId: event.folderId,
        ));
      }
    } catch (e) {
      emit(NotesError(e.toString()));
    }
  }

  void _onChangeViewMode(ChangeViewMode event, Emitter<NotesState> emit) {
    final currentState = state;
    if (currentState is NotesLoadedData) {
      emit(currentState.copyWith(viewMode: event.viewMode));
    }
  }

  void _onChangeSortBy(ChangeSortBy event, Emitter<NotesState> emit) {
    final currentState = state;
    if (currentState is NotesLoadedData) {
      final sorted = _sortNotes(currentState.notes, event.sortBy);
      emit(currentState.copyWith(sortBy: event.sortBy, notes: sorted));
    }
  }

  List<NoteModel> _sortNotes(List<NoteModel> notes, NoteSortBy sortBy) {
    final sorted = List<NoteModel>.from(notes);
    switch (sortBy) {
      case NoteSortBy.updatedAt:
        sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case NoteSortBy.createdAt:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case NoteSortBy.title:
        sorted.sort((a, b) => a.title.compareTo(b.title));
    }
    return sorted;
  }

  /// 分页加载更多笔记 —— 借鉴 Android Paging Library 的增量加载模式
  Future<void> _onLoadMoreNotes(LoadMoreNotes event, Emitter<NotesState> emit) async {
    final currentState = state;
    if (currentState is NotesLoadedData && currentState.hasMore) {
      try {
        final nextPage = currentState.currentPage + 1;
        final moreNotes = await _noteRepository.listNotesPaged(
          event.folderId,
          limit: _pageSize,
          offset: nextPage * _pageSize,
        );
        final allNotes = List<NoteModel>.from(currentState.notes)..addAll(moreNotes);
        emit(currentState.copyWith(
          notes: _sortNotes(allNotes, currentState.sortBy),
          hasMore: moreNotes.length >= _pageSize,
          currentPage: nextPage,
        ));
      } catch (e) {
        // 加载更多失败时保持当前状态，不切换到错误状态
        developer.log('Failed to load more notes: $e', level: 900);
        emit(currentState.copyWith(loadMoreError: 'Failed to load more notes'));
      }
    }
  }
}
