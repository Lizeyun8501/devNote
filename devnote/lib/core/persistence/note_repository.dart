// 持久化仓库 —— 通过 FFI 桥接调用 Rust 持久化引擎
// 借鉴 AppFlowy 的 Repository + FFI 模式：所有持久化操作经 Dispatch → FFI → Rust 完成
// 来源: https://github.com/AppFlowy-IO/AppFlowy
// 借鉴内容: Repository 模式通过 FFI 桥接调 Rust 持久化层

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/bridge/persistence_dispatch.dart';
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
  final DatabaseHelper _dbHelper;
  final PersistenceDispatch _dispatch = PersistenceDispatch();
  final FFIBridge _bridge = getIt<FFIBridge>();

  SqliteNoteRepository(this._dbHelper);

  bool get _useFFI => _bridge.isAvailable;

  /// P0 修复 (双持久层数据分裂): FFI 模式下同步 note 元数据到 Dart sqflite。
  ///
  /// 问题：FFI 模式下 note 写入 Rust DB，但 EditorService 编辑 block 时
  /// 写入 Dart DB，搜索也走 Dart FTS，导致数据分裂。
  ///
  /// 过渡方案：FFI 模式下双写 —— Rust DB 为权威源，Dart sqflite 作为
  /// 搜索索引和 block 编辑的同步镜像。长期应统一到 Rust 端实现 block CRUD
  /// 和 FTS 搜索，消除双写。
  Future<void> _syncToDartSqflite(NoteModel note) async {
    try {
      final db = await _dbHelper.database;
      // P1 修复 (P1-7): 使用 INSERT OR REPLACE 单语句完成 upsert，
      // 消除原 query + insert/update 的 TOCTOU 竞态（查询与写入之间笔记可能被删除）
      final sqfliteJson = note.toSqfliteJson();
      await db.insert('notes', sqfliteJson,
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      // 同步失败不影响主流程（Rust DB 已是权威源）
      AppLogger.w('NoteRepository', 'Failed to sync note to Dart sqflite', error: e);
    }
  }

  @override
  Future<NoteModel> createNote(NoteModel note) async {
    if (_useFFI) {
      final result = await _dispatch.create(entity: 'note', data: note.toJson());
      final saved = NoteModel.fromJson(result);
      // P0 修复: 同步到 Dart sqflite，确保搜索和 block 编辑数据一致
      await _syncToDartSqflite(saved);
      return saved;
    }
    AppLogger.d('NoteRepository', 'FFI not available, falling back to sqflite for createNote');
    final db = await _dbHelper.database;
    await db.insert('notes', note.toSqfliteJson());
    return note;
  }

  @override
  Future<NoteModel?> getNote(String id) async {
    if (_useFFI) {
      // 修复(P0): 原代码调用 _dispatch.list(filter: {'id': id})，
      // 但 PersistenceDispatch.list 对 'note' 实体只读取 filter['folder_id']，
      // 完全忽略 filter['id']，实际调用 listNotes('') 返回所有根目录笔记再取第一个，
      // 返回的是错误的笔记。改用 _dispatch.get() 直接调用 Dispatch.getNote(id)。
      final result = await _dispatch.get(entity: 'note', id: id);
      if (result == null) return null;
      final note = NoteModel.fromJson(result);
      // P0 修复: 同步到 Dart sqflite，确保后续 block 编辑基于最新数据
      await _syncToDartSqflite(note);
      return note;
    }
    AppLogger.d('NoteRepository', 'FFI not available, falling back to sqflite for getNote');
    final db = await _dbHelper.database;
    final results = await db.query(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (results.isEmpty) return null;
    return NoteModel.fromJson(results.first);
  }

  @override
  Future<NoteModel> updateNote(NoteModel note) async {
    if (_useFFI) {
      final result = await _dispatch.update(entity: 'note', id: note.id, data: note.toJson());
      final saved = NoteModel.fromJson(result);
      // P0 修复: 同步到 Dart sqflite，确保搜索索引和 block 编辑数据一致
      await _syncToDartSqflite(saved);
      return saved;
    }
    AppLogger.d('NoteRepository', 'FFI not available, falling back to sqflite for updateNote');
    final db = await _dbHelper.database;
    await db.update(
      'notes',
      note.toSqfliteJson(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
    // 修复：从数据库重新读取，确保返回值与数据库一致
    // 原代码直接返回本地 note 对象，但数据库可能修改了值（如触发器、默认值）
    final results = await db.query('notes', where: 'id = ?', whereArgs: [note.id]);
    if (results.isNotEmpty) {
      return NoteModel.fromJson(results.first);
    }
    return note;
  }

  @override
  Future<void> deleteNote(String id) async {
    if (_useFFI) {
      await _dispatch.delete(entity: 'note', id: id);
      // P1 修复 (P1-7): 同步删除 Dart sqflite 镜像，避免孤儿数据
      // 依赖 ON DELETE CASCADE 清理 note_tags/blocks/attachments
      try {
        final db = await _dbHelper.database;
        await db.delete('notes', where: 'id = ?', whereArgs: [id]);
      } catch (e) {
        AppLogger.w('NoteRepository', 'Failed to sync note deletion to Dart sqflite', error: e);
      }
      return;
    }
    AppLogger.d('NoteRepository', 'FFI not available, falling back to sqflite for deleteNote');
    final db = await _dbHelper.database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<NoteModel>> listNotes(String folderId) async {
    if (_useFFI) {
      final items = await _dispatch.list(entity: 'note', filter: {'folder_id': folderId});
      return items.map((json) => NoteModel.fromJson(json)).toList();
    }
    AppLogger.d('NoteRepository', 'FFI not available, falling back to sqflite for listNotes');
    final db = await _dbHelper.database;
    final results = await db.query(
      'notes',
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'updated_at DESC',
    );
    return results.map((json) => NoteModel.fromJson(json)).toList();
  }

  @override
  Future<List<NoteModel>> listNotesPaged(String folderId, {int limit = 20, int offset = 0}) async {
    if (_useFFI) {
      // 修复(P0): 原代码将 limit/offset 放入 filter 传给 _dispatch.list，
      // 但 PersistenceDispatch.list 对 'note' 实体只读取 filter['folder_id']，
      // 完全忽略 limit/offset，每次"加载更多"都返回全量数据，分页失效。
      // FFI listNotes 不支持原生分页，此处先取全量再客户端分页。
      // TODO: Rust 端 listNotes 应增加 limit/offset 参数以支持服务端分页。
      final items = await _dispatch.list(entity: 'note', filter: {'folder_id': folderId});
      final paged = items.skip(offset).take(limit).toList();
      return paged.map((json) => NoteModel.fromJson(json)).toList();
    }
    AppLogger.d('NoteRepository', 'FFI not available, falling back to sqflite for listNotesPaged');
    final db = await _dbHelper.database;
    final results = await db.query(
      'notes',
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'updated_at DESC',
      limit: limit,
      offset: offset,
    );
    return results.map((json) => NoteModel.fromJson(json)).toList();
  }

  /// P1 架构修复: FTS5 全文搜索，封装到 Repository 避免跨层访问
  /// FTS5 不可用时回退到内存过滤
  @override
  Future<List<NoteModel>> searchNotes(String query) async {
    final db = await _dbHelper.database;
    try {
      final ftsResults = await _dbHelper.searchNotesFTS(query);
      return ftsResults.map((json) => NoteModel.fromJson(json)).toList();
    } catch (e) {
      AppLogger.w('NoteRepository', 'FTS5 search failed, falling back to in-memory filter', error: e);
      // 回退：全量加载后内存过滤
      final all = await db.query('notes', orderBy: 'updated_at DESC');
      final lowerQuery = query.toLowerCase();
      return all
          .where((json) =>
              (json['title'] as String?)?.toLowerCase().contains(lowerQuery) == true ||
              (json['content'] as String?)?.toLowerCase().contains(lowerQuery) == true)
          .map((json) => NoteModel.fromJson(json))
          .toList();
    }
  }

  /// P1 架构修复: 按标签查询笔记 ID，封装到 Repository 避免跨层访问
  @override
  Future<List<String>> getNoteIdsByTag(String tagId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'note_tags',
      columns: ['note_id'],
      where: 'tag_id = ?',
      whereArgs: [tagId],
    );
    return rows.map((r) => r['note_id'] as String).toList();
  }
}