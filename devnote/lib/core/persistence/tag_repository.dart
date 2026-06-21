// 持久化仓库 —— Tag 实体的持久化操作
//
// Phase 2 架构修复: 统一所有 tag 操作走 sqflite。
//
// 原问题: createTag/getAllTags 在 FFI 可用时走 Rust rusqlite，但 addTagToNote/
// removeTagFromNote/getTagsForNote 始终走 Dart sqflite（Rust 端无 note_tags
// C ABI handler）。getTagsForNote 通过 JOIN 查询 tags + note_tags 两张表，
// 但这两张表可能分属不同数据库，导致 JOIN 查询返回空结果。
//
// 修复: 因 FFI 对 tag 的支持不完整（无 update/get/note_tags handler），
// 所有 tag 操作统一走 sqflite，消除混合持久化导致的数据不一致。
// TODO: 待 Rust 端补全 note_tags handler 后，可将全部 tag 操作迁移至 FFI。

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

  SqliteTagRepository(this._dbHelper);

  @override
  Future<TagModel> createTag(TagModel tag) async {
    final db = await _dbHelper.database;
    await db.insert('tags', tag.toJson());
    return tag;
  }

  @override
  Future<void> addTagToNote(String noteId, String tagId) async {
    final db = await _dbHelper.database;
    await db.insert('note_tags', {
      'note_id': noteId,
      'tag_id': tagId,
    });
  }

  @override
  Future<void> removeTagFromNote(String noteId, String tagId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'note_tags',
      where: 'note_id = ? AND tag_id = ?',
      whereArgs: [noteId, tagId],
    );
  }

  @override
  Future<List<TagModel>> getTagsForNote(String noteId) async {
    final db = await _dbHelper.database;
    final results = await db.rawQuery(
      '''
      SELECT t.id, t.name, t.created_at
      FROM tags t
      INNER JOIN note_tags nt ON t.id = nt.tag_id
      WHERE nt.note_id = ?
      ORDER BY t.name
      ''',
      [noteId],
    );
    return results.map((json) => TagModel.fromJson(json)).toList();
  }

  @override
  Future<List<TagModel>> getAllTags() async {
    final db = await _dbHelper.database;
    final results = await db.query('tags', orderBy: 'name');
    return results.map((json) => TagModel.fromJson(json)).toList();
  }
}
