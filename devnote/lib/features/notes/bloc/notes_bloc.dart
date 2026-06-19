import 'dart:developer' as developer;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:devnote/features/notes/bloc/notes_event.dart';
import 'package:devnote/features/notes/bloc/notes_state.dart';
import 'package:devnote/core/persistence/note_repository.dart';
import 'package:devnote/core/persistence/models/note_model.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/core/di/injection.dart';

class NotesBloc extends Bloc<NotesEvent, NotesState> {
  final NoteRepository _noteRepository;
  final DatabaseHelper _dbHelper;
  final _uuid = const Uuid();

  NotesBloc(this._noteRepository) : _dbHelper = getIt<DatabaseHelper>(), super(const NotesInitial()) {
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
      // 修复：使用 repository 返回的模型，而非本地创建的对象
      // FFI 模式下 Rust 端可能返回不同的时间戳，使用本地对象会导致数据不一致
      final created = await _noteRepository.createNote(note);
      final currentState = state;
      if (currentState is NotesLoaded) {
        final notes = List<NoteModel>.from(currentState.notes)..insert(0, created);
        emit(currentState.copyWith(notes: notes, selectedNoteId: created.id));
      } else {
        emit(NotesLoaded(notes: [created], selectedNoteId: created.id));
      }
    } catch (e) {
      emit(NotesError(e.toString()));
    }
  }

  Future<void> _onDeleteNote(DeleteNote event, Emitter<NotesState> emit) async {
    try {
      await _noteRepository.deleteNote(event.noteId);
      final currentState = state;
      if (currentState is NotesLoaded) {
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
    if (currentState is NotesLoaded) {
      emit(currentState.copyWith(selectedNoteId: event.noteId));
    }
  }

  Future<void> _onSearchNotes(SearchNotes event, Emitter<NotesState> emit) async {
    final currentState = state;
    if (currentState is NotesLoaded) {
      if (event.query.isEmpty) {
        // 清空搜索时，从数据库重新加载原始列表
        try {
          final folderId = currentState.filterFolderId;
          final allNotes = folderId != null
              ? await _noteRepository.listNotes(folderId)
              : await _noteRepository.listNotes('');
          emit(currentState.copyWith(
            searchQuery: null,
            notes: _sortNotes(allNotes, currentState.sortBy),
          ));
        } catch (_) {
          emit(currentState.copyWith(searchQuery: null));
        }
        return;
      }
      // 修复(P2): 原实现用内存 contains 过滤，性能差且不支持中文分词。
      // DatabaseHelper 已实现 FTS5 全文搜索（searchNotesFTS），现改用 FTS5。
      // FTS5 支持 MATCH 语法、unicode61 分词、按相关性排序（rank）。
      try {
        final ftsResults = await _dbHelper.searchNotesFTS(event.query);
        final notes = ftsResults.map((json) => NoteModel.fromJson(json)).toList();
        emit(currentState.copyWith(searchQuery: event.query, notes: _sortNotes(notes, currentState.sortBy)));
      } catch (e) {
        // FTS5 不可用时回退到内存过滤（兼容旧数据库未迁移到 v6 的场景）
        developer.log('FTS5 search failed, falling back to in-memory filter: $e', level: 900);
        try {
          final folderId = currentState.filterFolderId;
          final allNotes = folderId != null
              ? await _noteRepository.listNotes(folderId)
              : await _noteRepository.listNotes('');
          final filtered = allNotes
              .where((n) =>
                  n.title.toLowerCase().contains(event.query.toLowerCase()) ||
                  n.content.toLowerCase().contains(event.query.toLowerCase()))
              .toList();
          emit(currentState.copyWith(searchQuery: event.query, notes: _sortNotes(filtered, currentState.sortBy)));
        } catch (e2) {
          emit(NotesError(e2.toString()));
        }
      }
    }
  }

  Future<void> _onFilterByTag(FilterByTag event, Emitter<NotesState> emit) async {
    final currentState = state;
    if (currentState is NotesLoaded) {
      emit(currentState.copyWith(filterTagId: event.tagId));
    }
  }

  Future<void> _onFilterByFolder(FilterByFolder event, Emitter<NotesState> emit) async {
    try {
      final notes = await _noteRepository.listNotes(event.folderId);
      final currentState = state;
      if (currentState is NotesLoaded) {
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
    if (currentState is NotesLoaded) {
      emit(currentState.copyWith(viewMode: event.viewMode));
    }
  }

  void _onChangeSortBy(ChangeSortBy event, Emitter<NotesState> emit) {
    final currentState = state;
    if (currentState is NotesLoaded) {
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
    if (currentState is NotesLoaded && currentState.hasMore) {
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
