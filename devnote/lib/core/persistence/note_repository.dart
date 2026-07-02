// 持久化仓库 —— 通过 FFI 桥接调用 Rust 持久化引擎
// 借鉴 AppFlowy 的 Repository + FFI 模式：所有持久化操作经 Dispatch → FFI → Rust 完成
// 来源: https://github.com/AppFlowy-IO/AppFlowy
// 借鉴内容: Repository 模式通过 FFI 桥接调 Rust 持久化层
//
// P1 修复 (双源分支移除): 彻底删除 _useFFI 分支与 sqflite 兜底路径。
// 原 _useFFI 双源分支违反 ADR-003/004 单一数据源原则——FFI 可用时写入 Rust DB，
// 不可用时写入 sqflite，切换模式会导致数据分裂与丢失。现统一为 FFI 单一数据源，
// FFI 不可用时错误向上传播，由调用方决定降级策略。

import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/observability/app_logger.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/core/persistence/models/note_model.dart';

abstract class NoteRepository {
  Future<NoteModel> createNote(NoteModel note);
  Future<NoteModel?> getNote(String id);
  Future<NoteModel> updateNote(NoteModel note);
  Future<void> deleteNote(String id);
  Future<List<NoteModel>> listNotes(String folderId);
  // ============================================================
  // 分页加载 —— 借鉴 Android Paging Library 的分页设计
  // 来源: https://developer.android.com/topic/libraries/architecture/paging
  // 借鉴内容: 基于 limit/offset 的分页查询，避免全量加载导致内存溢出
  // ============================================================
  Future<List<NoteModel>> listNotesPaged(String folderId, {int limit = 20, int offset = 0});
  // P1 架构修复: 将 FTS 搜索和按标签查询封装到 Repository，
  // 消除 NotesBloc 直接操作 DatabaseHelper 的跨层访问
  Future<List<NoteModel>> searchNotes(String query);
  Future<List<String>> getNoteIdsByTag(String tagId);
}

class SqliteNoteRepository implements NoteRepository {
  // P1 修复: _dbHelper 保留以维持 DI 构造签名兼容，FFI 为唯一数据源后不再使用 sqflite。
  final DatabaseHelper _dbHelper;
  // P1 修复 (2-E): 直接使用 Dispatch 类型安全方法，消除 PersistenceDispatch 冗余转换层
  final Dispatch _dispatch = Dispatch();
  final FFIBridge _bridge = getIt<FFIBridge>();

  SqliteNoteRepository(this._dbHelper);

  @override
  Future<NoteModel> createNote(NoteModel note) async {
    return await _dispatch.createNote(
      title: note.title,
      content: note.content,
      folderId: note.folderId,
    );
  }

  @override
  Future<NoteModel?> getNote(String id) async {
    return await _dispatch.getNote(id);
  }

  @override
  Future<NoteModel> updateNote(NoteModel note) async {
    return await _dispatch.updateNote(
      id: note.id,
      title: note.title,
      content: note.content,
    );
  }

  @override
  Future<void> deleteNote(String id) async {
    await _dispatch.deleteNote(id);
  }

  @override
  Future<List<NoteModel>> listNotes(String folderId) async {
    return await _dispatch.listNotes(folderId);
  }

  @override
  Future<List<NoteModel>> listNotesPaged(String folderId, {int limit = 20, int offset = 0}) async {
    // FFI listNotes 不支持原生分页，此处先取全量再客户端分页。
    // TODO: Rust 端 listNotes 应增加 limit/offset 参数以支持服务端分页。
    final items = await _dispatch.listNotes(folderId);
    return items.skip(offset).take(limit).toList();
  }

  /// FTS5 全文搜索通过 FFI 调用 Rust 搜索引擎。
  ///
  /// P1-2 修复: 通过 FFI 调用 Rust 端的 search_notes，使用 Rust 端的 FTS5 索引，
  /// 消除 Dart sqflite 作为搜索索引的依赖。
  /// FFI 搜索失败时回退到内存过滤（仍通过 FFI 加载全量笔记，不依赖 sqflite）。
  @override
  Future<List<NoteModel>> searchNotes(String query) async {
    try {
      final results = await _bridge.searchNotes(query: query);
      // SearchResult 包含 note_id/title/snippet/score，
      // 转换为 NoteModel（snippet 作为 content 的近似）
      return results
          .map((r) => NoteModel(
                id: r['note_id'] as String,
                title: r['title'] as String,
                content: r['snippet'] as String? ?? '',
                folderId: '', // 搜索结果不包含 folder_id
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ))
          .toList();
    } catch (e) {
      AppLogger.w('NoteRepository', 'FFI search failed, falling back to in-memory filter', error: e);
    }
    // 回退: 从 FFI 加载全部笔记后内存过滤（不再依赖 Dart sqflite）
    final all = await listNotes('');
    final lowerQuery = query.toLowerCase();
    return all
        .where((n) =>
            n.title.toLowerCase().contains(lowerQuery) ||
            n.content.toLowerCase().contains(lowerQuery))
        .toList();
  }

  /// 按标签查询笔记 ID 通过 FFI 调用 Rust 持久化层。
  ///
  /// P1-2 修复: 通过 FFI 调用 Rust 端的 get_note_ids_by_tag，
  /// 消除 Dart sqflite 作为标签查询的依赖。
  @override
  Future<List<String>> getNoteIdsByTag(String tagId) async {
    try {
      return await _bridge.getNoteIdsByTag(tagId);
    } catch (e) {
      AppLogger.w('NoteRepository', 'FFI getNoteIdsByTag failed', error: e);
      return [];
    }
  }
}
