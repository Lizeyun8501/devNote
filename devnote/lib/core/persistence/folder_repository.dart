// TODO: 迁移到 Rust FFI — 当前临时使用 sqflite 直连
// 注意：此实现为临时方案，后续将通过 Dispatch → FFI → Rust persistence 调用链替换

import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/core/persistence/models/folder_model.dart';

abstract class FolderRepository {
  Future<FolderModel> createFolder(FolderModel folder);
  Future<List<FolderModel>> listFolders(String? parentId);
  Future<void> deleteFolder(String id);
  Future<FolderModel> updateFolder(FolderModel folder);
}

class SqliteFolderRepository implements FolderRepository {
  final DatabaseHelper _dbHelper;

  SqliteFolderRepository(this._dbHelper);

  @override
  Future<FolderModel> createFolder(FolderModel folder) async {
    final db = await _dbHelper.database;
    await db.insert('folders', folder.toJson());
    return folder;
  }

  @override
  Future<List<FolderModel>> listFolders(String? parentId) async {
    final db = await _dbHelper.database;
    final results = parentId != null
        ? await db.query(
            'folders',
            where: 'parent_id = ?',
            whereArgs: [parentId],
            orderBy: 'name',
          )
        : await db.query(
            'folders',
            where: 'parent_id IS NULL',
            orderBy: 'name',
          );
    return results.map((json) => FolderModel.fromJson(json)).toList();
  }

  @override
  Future<void> deleteFolder(String id) async {
    final db = await _dbHelper.database;
    await db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<FolderModel> updateFolder(FolderModel folder) async {
    final db = await _dbHelper.database;
    await db.update(
      'folders',
      folder.toJson(),
      where: 'id = ?',
      whereArgs: [folder.id],
    );
    return folder;
  }
}
