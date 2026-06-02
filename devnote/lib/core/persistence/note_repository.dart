import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/core/persistence/models/note_model.dart';

abstract class NoteRepository {
  Future<NoteModel> createNote(NoteModel note);
  Future<NoteModel?> getNote(String id);
  Future<NoteModel> updateNote(NoteModel note);
  Future<void> deleteNote(String id);
  Future<List<NoteModel>> listNotes(String folderId);
}

class SqliteNoteRepository implements NoteRepository {
  final DatabaseHelper _dbHelper;

  SqliteNoteRepository(this._dbHelper);

  @override
  Future<NoteModel> createNote(NoteModel note) async {
    final db = await _dbHelper.database;
    await db.insert('notes', note.toJson());
    return note;
  }

  @override
  Future<NoteModel?> getNote(String id) async {
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
    final db = await _dbHelper.database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<NoteModel>> listNotes(String folderId) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'notes',
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'updated_at DESC',
    );
    return results.map((json) => NoteModel.fromJson(json)).toList();
  }
}
