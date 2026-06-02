import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/core/persistence/models/tag_model.dart';

abstract class TagRepository {
  Future<TagModel> createTag(TagModel tag);
  Future<void> addTagToNote(String noteId, String tagId);
  Future<void> removeTagFromNote(String noteId, String tagId);
  Future<List<TagModel>> getTagsForNote(String noteId);
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
    final results = await db.rawQuery('''
      SELECT t.id, t.name, t.created_at
      FROM tags t
      INNER JOIN note_tags nt ON t.id = nt.tag_id
      WHERE nt.note_id = ?
      ORDER BY t.name
    ''', [noteId]);
    return results.map((json) => TagModel.fromJson(json)).toList();
  }
}
