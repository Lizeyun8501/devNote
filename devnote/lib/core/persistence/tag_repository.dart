// 持久化仓库 —— 通过 FFI 桥接调用 Rust 持久化引擎
// 借鉴 AppFlowy 的 Repository + FFI 模式：所有持久化操作经 Dispatch → FFI → Rust 完成
// 来源: https://github.com/AppFlowy-IO/AppFlowy
// 借鉴内容: Repository 模式通过 FFI 桥接调 Rust 持久化层

import 'dart:developer' as developer;

import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/bridge/persistence_dispatch.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/core/persistence/models/tag_model.dart';

abstract class TagRepository {
  Future<TagModel> createTag(TagModel tag);
  Future<void> addTagToNote(String noteId, String tagId);
  Future<void> removeTagFromNote(String noteId, String tagId);
  Future<List<TagModel>> getTagsForNote(String noteId);
  Future<List<TagModel>> getAllTags();
}

class SqliteTagRepository implements TagRepository {
  final DatabaseHelper _dbHelper;
  final PersistenceDispatch _dispatch = PersistenceDispatch();
  final FFIBridge _bridge = getIt<FFIBridge>();

  SqliteTagRepository(this._dbHelper);

  bool get _useFFI => _bridge.isAvailable;

  @override
  Future<TagModel> createTag(TagModel tag) async {
    if (_useFFI) {
      final result = await _dispatch.create(entity: 'tag', data: tag.toJson());
      return TagModel.fromJson(result);
    }
    developer.log('FFI not available, falling back to sqflite for createTag', level: 900);
    final db = await _dbHelper.database;
    await db.insert('tags', tag.toJson());
    return tag;
  }

  @override
  Future<void> addTagToNote(String noteId, String tagId) async {
    if (_useFFI) {
      await _dispatch.create(entity: 'note_tag', data: {
        'note_id': noteId,
        'tag_id': tagId,
      });
      return;
    }
    developer.log('FFI not available, falling back to sqflite for addTagToNote', level: 900);
    final db = await _dbHelper.database;
    await db.insert('note_tags', {
      'note_id': noteId,
      'tag_id': tagId,
    });
  }

  @override
  Future<void> removeTagFromNote(String noteId, String tagId) async {
    if (_useFFI) {
      await _dispatch.delete(entity: 'note_tag', id: '${noteId}_${tagId}');
      return;
    }
    developer.log('FFI not available, falling back to sqflite for removeTagFromNote', level: 900);
    final db = await _dbHelper.database;
    await db.delete(
      'note_tags',
      where: 'note_id = ? AND tag_id = ?',
      whereArgs: [noteId, tagId],
    );
  }

  @override
  Future<List<TagModel>> getTagsForNote(String noteId) async {
    // 修复：FFI 路径下 PersistenceDispatch.list 不支持 tag 的 note_id 过滤，
    // getTagsForNote 需要 JOIN note_tags 表，FFI 桥接层未实现此查询。
    // 因此始终使用 sqflite 路径执行 JOIN 查询，确保返回正确的标签。
    if (_useFFI) {
      developer.log('FFI 模式下 getTagsForNote 降级到 sqflite（FFI 不支持 note_id 过滤）', level: 900);
    }
    final db = await _dbHelper.database;
    final results = await db.rawQuery('''
      SELECT t.id, t.name, t.created_at
      FROM tags t
      INNER JOIN note_tags nt ON t.id = nt.tag_id
      WHERE nt.note_id = ?
      ORDER BY t.name
    ''', [noteId]);
    return results.map((json) => TagModel.fromJson(json)).toList();
  }

  @override
  Future<List<TagModel>> getAllTags() async {
    if (_useFFI) {
      final items = await _dispatch.list(entity: 'tag');
      return items.map((json) => TagModel.fromJson(json)).toList();
    }
    developer.log('FFI not available, falling back to sqflite for getAllTags', level: 900);
    final db = await _dbHelper.database;
    final results = await db.query('tags', orderBy: 'name');
    return results.map((json) => TagModel.fromJson(json)).toList();
  }
}