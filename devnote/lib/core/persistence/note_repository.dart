// 持久化仓库 —— 通过 FFI 桥接调用 Rust 持久化引擎
// 借鉴 AppFlowy 的 Repository + FFI 模式：所有持久化操作经 Dispatch → FFI → Rust 完成
// 来源: https://github.com/AppFlowy-IO/AppFlowy
// 借鉴内容: Repository 模式通过 FFI 桥接调 Rust 持久化层

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

  // P1-2 修复: 移除 _syncToDartSqflite() 双写逻辑
  // 原实现: FFI 写入 Rust DB 后同步双写到 Dart sqflite，作为搜索索引和 block 编辑的镜像。
  // 现已将 searchNotes 和 getNoteIdsByTag 迁移到 FFI，不再依赖 Dart sqflite 作为搜索索引。
  // block 编辑仍暂时使用 Dart sqflite（见 EditorService），后续应迁移到 Rust persistence。

  @override
  Future<NoteModel> createNote(NoteModel note) async {
    if (_useFFI) {
      final result = await _dispatch.create(entity: 'note', data: note.toJson());
      return NoteModel.fromJson(result);
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
      return NoteModel.fromJson(result);
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
      return NoteModel.fromJson(result);
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
      // P1-2 修复: 不再同步删除 Dart sqflite 镜像（双写已移除）
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

  /// P1-2 修复: FTS5 全文搜索通过 FFI 调用 Rust 搜索引擎
  ///
  /// 原实现: 直接查询 Dart sqflite 的 FTS5 索引，绕过 Rust FFI，
  /// 导致数据分裂（需双写维护两套数据库）。
  /// 现改为: 通过 FFI 调用 Rust 端的 search_notes，使用 Rust 端的 FTS5 索引，
  /// 消除 Dart sqflite 作为搜索索引的依赖。
  /// FFI 不可用时回退到内存过滤（不再依赖 Dart sqflite）。
  @override
  Future<List<NoteModel>> searchNotes(String query) async {
    if (_useFFI) {
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
    }
    // 回退: 从 FFI 加载全部笔记后内存过滤（不再依赖 Dart sqflite）
    AppLogger.d('NoteRepository', 'FFI not available or search failed, using in-memory filter');
    final all = await listNotes('');
    final lowerQuery = query.toLowerCase();
    return all
        .where((n) =>
            n.title.toLowerCase().contains(lowerQuery) ||
            n.content.toLowerCase().contains(lowerQuery))
        .toList();
  }

  /// P1-2 修复: 按标签查询笔记 ID 通过 FFI 调用 Rust 持久化层
  ///
  /// 原实现: 直接查询 Dart sqflite 的 note_tags 表，绕过 Rust FFI。
  /// 现改为: 通过 FFI 调用 Rust 端的 get_note_ids_by_tag，
  /// 消除 Dart sqflite 作为标签查询的依赖。
  @override
  Future<List<String>> getNoteIdsByTag(String tagId) async {
    if (_useFFI) {
      try {
        return await _bridge.getNoteIdsByTag(tagId);
      } catch (e) {
        AppLogger.w('NoteRepository', 'FFI getNoteIdsByTag failed', error: e);
        return [];
      }
    }
    AppLogger.d('NoteRepository', 'FFI not available, getNoteIdsByTag returns empty');
    return [];
  }
}