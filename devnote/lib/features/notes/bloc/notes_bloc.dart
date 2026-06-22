import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:devnote/core/observability/app_logger.dart';
import 'package:devnote/features/notes/bloc/notes_event.dart';
import 'package:devnote/features/notes/bloc/notes_state.dart';
import 'package:devnote/core/persistence/note_repository.dart';
import 'package:devnote/core/persistence/folder_repository.dart';
import 'package:devnote/core/persistence/models/note_model.dart';
import 'package:devnote/core/persistence/models/folder_model.dart';
// P1 修复 (P1-3): 依赖 NoteBlockCreationPort 抽象接口而非 EditorService 具体类，
// 彻底消除 notes → editor 的 import 依赖，打破循环依赖。
// BlockType 映射逻辑由 EditorService 在接口实现内部处理。
import 'package:devnote/core/services/note_block_creation_port.dart';

class NotesBloc extends Bloc<NotesEvent, NotesState> {
  final NoteRepository _noteRepository;
  final FolderRepository _folderRepository;
  final NoteBlockCreationPort _blockCreationPort;
  final _uuid = const Uuid();

  // P1 修复 (P1-5): 所有依赖通过构造函数注入，替代 getIt Service Locator 反模式
  NotesBloc(
    this._noteRepository,
    this._folderRepository,
    this._blockCreationPort, {
    this._pageSize = 20,
  }) : super(const NotesInitial()) {
    on<LoadNotes>(_onLoadNotes);
    on<CreateNote>(_onCreateNote);
    on<CreateNoteFromTemplate>(_onCreateNoteFromTemplate);
    on<CreateDailyNote>(_onCreateDailyNote);
    on<DeleteNote>(_onDeleteNote);
    on<SelectNote>(_onSelectNote);
    on<SearchNotes>(_onSearchNotes);
    on<FilterByTag>(_onFilterByTag);
    on<FilterByFolder>(_onFilterByFolder);
    on<ChangeViewMode>(_onChangeViewMode);
    on<ChangeSortBy>(_onChangeSortBy);
    on<LoadMoreNotes>(_onLoadMoreNotes);
  }

  final int _pageSize;

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

  /// P1-3: 从模板创建笔记 —— 先创建空笔记，再将模板块逐个持久化到 SQLite。
  /// 块通过 EditorService.createBlock 写入，与编辑器共享同一持久化路径，
  /// 用户打开笔记时 EditorBloc.loadBlocks 可正确回读。
  Future<void> _onCreateNoteFromTemplate(
      CreateNoteFromTemplate event, Emitter<NotesState> emit) async {
    try {
      final now = DateTime.now();
      final note = NoteModel(
        id: _uuid.v4(),
        title: event.template.name,
        content: '',
        folderId: event.folderId,
        createdAt: now,
        updatedAt: now,
      );
      final created = await _noteRepository.createNote(note);
      // 应用模板块：按 position 顺序逐个创建（笔记为空，无需位置重排）
      // P1 修复 (P1-5): 使用构造函数注入的 _blockCreationPort，替代 getIt
      final blocks = event.template.blocks;
      for (var i = 0; i < blocks.length; i++) {
        // P1 修复 (P1-3): 通过抽象接口调用，不依赖 editor 模块
        await _blockCreationPort.createBlockFromString(
          noteId: created.id,
          blockTypeName: blocks[i].type,
          content: blocks[i].content,
          position: i,
        );
      }
      final currentState = state;
      if (currentState is NotesLoaded) {
        final notes = List<NoteModel>.from(currentState.notes)
          ..insert(0, created);
        emit(currentState.copyWith(notes: notes, selectedNoteId: created.id));
      } else {
        emit(NotesLoaded(notes: [created], selectedNoteId: created.id));
      }
    } catch (e) {
      emit(NotesError(e.toString()));
    }
  }

  /// P1 架构修复: _blockTypeFromName 已移至 EditorService.createBlockFromString
  /// 消除 notes ↔ editor 循环依赖（notes_bloc 不再 import BlockType enum）

  /// P2-4: 创建 Daily Note —— 通过文件夹名称解析 folderId（不存在则创建），
  /// 再创建笔记并应用模板块。与 _onCreateNoteFromTemplate 的区别：
  /// 1. 使用日期标题而非模板名
  /// 2. 通过 folderName 解析 folderId（Daily Notes 配置存名称而非 ID）
  Future<void> _onCreateDailyNote(
      CreateDailyNote event, Emitter<NotesState> emit) async {
    try {
      // 解析文件夹名称到 ID，不存在则创建
      final folderId = await _resolveFolderIdByName(event.folderName);

      final now = DateTime.now();
      final note = NoteModel(
        id: _uuid.v4(),
        title: event.title,
        content: '',
        folderId: folderId,
        createdAt: now,
        updatedAt: now,
      );
      final created = await _noteRepository.createNote(note);

      // 应用模板块（如果配置了模板）
      if (event.templateBlocks.isNotEmpty) {
        // P1 修复 (P1-5): 使用构造函数注入的 _blockCreationPort，替代 getIt
        for (var i = 0; i < event.templateBlocks.length; i++) {
          // P1 修复 (P1-3): 通过抽象接口调用，不依赖 editor 模块
          await _blockCreationPort.createBlockFromString(
            noteId: created.id,
            blockTypeName: event.templateBlocks[i].type,
            content: event.templateBlocks[i].content,
            position: i,
          );
        }
      }

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

  /// 通过文件夹名称解析 folderId。
  /// 在根目录下查找同名文件夹，找不到则创建新文件夹。
  Future<String> _resolveFolderIdByName(String name) async {
    // P1 修复 (P1-5): 使用构造函数注入的 _folderRepository，替代直接 new
    final rootFolders = await _folderRepository.listFolders(null);
    final existing = rootFolders.where((f) => f.name == name).firstOrNull;
    if (existing != null) return existing.id;

    final now = DateTime.now();
    final folder = FolderModel(
      id: _uuid.v4(),
      name: name,
      parentId: null,
      createdAt: now,
      updatedAt: now,
    );
    final created = await _folderRepository.createFolder(folder);
    return created.id;
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
        } catch (e) {
          // P2 修复 (P2-12): 记录查询失败日志，原 catch(_) 静默吞异常
          AppLogger.w('NotesBloc', 'search by folder failed, clearing search', error: e);
          emit(currentState.copyWith(searchQuery: null));
        }
        return;
      }
      // 修复(P2): 原实现用内存 contains 过滤，性能差且不支持中文分词。
      // DatabaseHelper 已实现 FTS5 全文搜索（searchNotesFTS），现改用 FTS5。
      // P1 架构修复: 通过 NoteRepository.searchNotes 调用，避免直接操作 DatabaseHelper
      try {
        final notes = await _noteRepository.searchNotes(event.query);
        emit(currentState.copyWith(searchQuery: event.query, notes: _sortNotes(notes, currentState.sortBy)));
      } catch (e) {
        // FTS5 不可用时回退到内存过滤（兼容旧数据库未迁移到 v6 的场景）
        // P1 修复 (P1-5): 使用 AppLogger 替代 developer.log
        AppLogger.w('NotesBloc', 'searchNotes failed, falling back to in-memory filter: $e');
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
    if (currentState is! NotesLoaded) return;

    // 修复(P1-7): 原实现仅 copyWith(filterTagId) 而不实际过滤 notes 列表，
    // 导致 UI 仍显示全部笔记。现根据 tagId 过滤 notes。
    // P1 架构修复: 通过 NoteRepository.getNoteIdsByTag 调用，
    // 避免直接操作 DatabaseHelper 和 note_tags 表
    if (event.tagId.isEmpty) {
      // 清除标签过滤：从数据库重新加载原始列表（保留 folder 过滤）
      try {
        final folderId = currentState.filterFolderId;
        final allNotes = folderId != null
            ? await _noteRepository.listNotes(folderId)
            : await _noteRepository.listNotes('');
        emit(currentState.copyWith(
          notes: _sortNotes(allNotes, currentState.sortBy),
          filterTagId: null,
        ));
      } catch (e) {
        // P2 修复 (P2-12): 记录查询失败日志，原 catch(_) 静默吞异常
        AppLogger.w('NotesBloc', 'filter by tag failed, clearing filter', error: e);
        emit(currentState.copyWith(filterTagId: null));
      }
      return;
    }

    try {
      final noteIds = (await _noteRepository.getNoteIdsByTag(event.tagId)).toSet();
      final filteredNotes = currentState.notes
          .where((n) => noteIds.contains(n.id))
          .toList();
      emit(currentState.copyWith(
        notes: filteredNotes,
        filterTagId: event.tagId,
      ));
    } catch (e) {
      // P2 修复 (P2-12): 记录查询失败日志，原 catch(_) 静默吞异常
      // 查询失败时仅更新 filterTagId，不改变 notes 列表
      AppLogger.w('NotesBloc', 'filter by tagId failed, keeping notes list', error: e);
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
        // P1 修复 (P1-5): 使用 AppLogger 替代 developer.log
        AppLogger.w('NotesBloc', 'Failed to load more notes: $e');
        emit(currentState.copyWith(loadMoreError: 'Failed to load more notes'));
      }
    }
  }
}
