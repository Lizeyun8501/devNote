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
  // ============================================================
  // 分页状态 —— 借鉴 Android Paging Library 的分页状态管理
  // 来源: https://developer.android.com/topic/libraries/architecture/paging
  // 借鉴内容: hasMore 标记是否还有更多数据，currentPage 追踪当前页码
  // ============================================================
  final bool hasMore;
  final int currentPage;
  final String? loadMoreError;

  const NotesLoaded({
    required this.notes,
    this.selectedNoteId,
    this.searchQuery,
    this.filterTagId,
    this.filterFolderId,
    this.sortBy = NoteSortBy.updatedAt,
    this.viewMode = NoteViewMode.list,
    this.hasMore = true,
    this.currentPage = 0,
    this.loadMoreError,
  });

  NotesLoaded copyWith({
    List<NoteModel>? notes,
    String? selectedNoteId,
    String? searchQuery,
    String? filterTagId,
    String? filterFolderId,
    NoteSortBy? sortBy,
    NoteViewMode? viewMode,
    bool? hasMore,
    int? currentPage,
    String? loadMoreError,
  }) {
    return NotesLoaded(
      notes: notes ?? this.notes,
      selectedNoteId: selectedNoteId ?? this.selectedNoteId,
      searchQuery: searchQuery ?? this.searchQuery,
      filterTagId: filterTagId ?? this.filterTagId,
      filterFolderId: filterFolderId ?? this.filterFolderId,
      sortBy: sortBy ?? this.sortBy,
      viewMode: viewMode ?? this.viewMode,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      loadMoreError: loadMoreError ?? this.loadMoreError,
    );
  }
}

final class NotesError extends NotesState {
  final String message;

  const NotesError(this.message);
}
