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

  /// 修复：copyWith 使用 _Sentinel 模式支持清除 nullable 字段
  /// 原代码 `searchQuery ?? this.searchQuery` 无法传 null 清除字段，
  /// 例如清除搜索时调用 copyWith(searchQuery: null) 实际不会清除，
  /// 因为 null ?? this.searchQuery 仍返回旧值
  NotesLoaded copyWith({
    List<NoteModel>? notes,
    Object? selectedNoteId = _sentinel,
    Object? searchQuery = _sentinel,
    Object? filterTagId = _sentinel,
    Object? filterFolderId = _sentinel,
    NoteSortBy? sortBy,
    NoteViewMode? viewMode,
    bool? hasMore,
    int? currentPage,
    Object? loadMoreError = _sentinel,
  }) {
    return NotesLoaded(
      notes: notes ?? this.notes,
      selectedNoteId: selectedNoteId == _sentinel ? this.selectedNoteId : selectedNoteId as String?,
      searchQuery: searchQuery == _sentinel ? this.searchQuery : searchQuery as String?,
      filterTagId: filterTagId == _sentinel ? this.filterTagId : filterTagId as String?,
      filterFolderId: filterFolderId == _sentinel ? this.filterFolderId : filterFolderId as String?,
      sortBy: sortBy ?? this.sortBy,
      viewMode: viewMode ?? this.viewMode,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      loadMoreError: loadMoreError == _sentinel ? this.loadMoreError : loadMoreError as String?,
    );
  }
}

/// Sentinel 值用于区分"未传参"和"显式传 null"
const _sentinel = Object();

final class NotesError extends NotesState {
  final String message;

  const NotesError(this.message);
}
