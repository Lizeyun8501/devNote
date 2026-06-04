// 持久化仓库 —— 通过 FFI 桥接调用 Rust 持久化引擎
// 借鉴 AppFlowy 的 Repository + FFI 模式：所有持久化操作经 Dispatch → FFI → Rust 完成
// 来源: https://github.com/AppFlowy-IO/AppFlowy
// 借鉴内容: Repository 模式通过 FFI 桥接调 Rust 持久化层

import 'dart:developer' as developer;

import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/bridge/persistence_dispatch.dart';
import 'package:devnote/core/di/injection.dart';
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
}

class SqliteNoteRepository implements NoteRepository {
  final DatabaseHelper _dbHelper;
  final PersistenceDispatch _dispatch = PersistenceDispatch();
  final FFIBridge _bridge = getIt<FFIBridge>();

  SqliteNoteRepository(this._dbHelper);

  bool get _useFFI => _bridge.isAvailable;

  @override
  Future<NoteModel> createNote(NoteModel note) async {
    if (_useFFI) {
      final result = await _dispatch.create(entity: 'note', data: note.toJson());
      return NoteModel.fromJson(result);
    }
    developer.log('FFI not available, falling back to sqflite for createNote', level: 900);
    final db = await _dbHelper.database;
    await db.insert('notes', note.toJson());
    return note;
  }

  @override
  Future<NoteModel?> getNote(String id) async {
    if (_useFFI) {
      final items = await _dispatch.list(entity: 'note', filter: {'id': id});
      if (items.isEmpty) return null;
      return NoteModel.fromJson(items.first);
    }
    developer.log('FFI not available, falling back to sqflite for getNote', level: 900);
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
    developer.log('FFI not available, falling back to sqflite for updateNote', level: 900);
    final db = await _dbHelper.database;
    await db.update(
      'notes',
      note.toJson(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
    return note;
  }

  @override
  Future<void> deleteNote(String id) async {
    if (_useFFI) {
      await _dispatch.delete(entity: 'note', id: id);
      return;
    }
    developer.log('FFI not available, falling back to sqflite for deleteNote', level: 900);
    final db = await _dbHelper.database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<NoteModel>> listNotes(String folderId) async {
    if (_useFFI) {
      final items = await _dispatch.list(entity: 'note', filter: {'folder_id': folderId});
      return items.map((json) => NoteModel.fromJson(json)).toList();
    }
    developer.log('FFI not available, falling back to sqflite for listNotes', level: 900);
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
      final items = await _dispatch.list(entity: 'note', filter: {
        'folder_id': folderId,
        'limit': limit,
        'offset': offset,
      });
      return items.map((json) => NoteModel.fromJson(json)).toList();
    }
    developer.log('FFI not available, falling back to sqflite for listNotesPaged', level: 900);
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
}