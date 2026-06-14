// 持久化仓库 —— 通过 FFI 桥接调用 Rust 持久化引擎
// 借鉴 AppFlowy 的 Repository + FFI 模式：所有持久化操作经 Dispatch → FFI → Rust 完成
// 来源: https://github.com/AppFlowy-IO/AppFlowy
// 借鉴内容: Repository 模式通过 FFI 桥接调 Rust 持久化层

import 'dart:developer' as developer;

import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/bridge/persistence_dispatch.dart';
import 'package:devnote/core/di/injection.dart';
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
  final PersistenceDispatch _dispatch = PersistenceDispatch();
  final FFIBridge _bridge = getIt<FFIBridge>();

  SqliteFolderRepository(this._dbHelper);

  bool get _useFFI => _bridge.isAvailable;

  @override
  Future<FolderModel> createFolder(FolderModel folder) async {
    if (_useFFI) {
      final result = await _dispatch.create(entity: 'folder', data: folder.toJson());
      return FolderModel.fromJson(result);
    }
    developer.log('FFI not available, falling back to sqflite for createFolder', level: 900);
    final db = await _dbHelper.database;
    await db.insert('folders', folder.toJson());
    return folder;
  }

  @override
  Future<List<FolderModel>> listFolders(String? parentId) async {
    if (_useFFI) {
      final filter = <String, dynamic>{};
      if (parentId != null) {
        filter['parent_id'] = parentId;
      } else {
        filter['parent_id'] = null;
      }
      final items = await _dispatch.list(entity: 'folder', filter: filter);
      return items.map((json) => FolderModel.fromJson(json)).toList();
    }
    developer.log('FFI not available, falling back to sqflite for listFolders', level: 900);
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
    // 修复：无论 FFI 是否可用，都先执行级联删除逻辑
    // 原代码 FFI 路径只调用 _dispatch.delete，不收集子文件夹和笔记，
    // 导致 FFI 模式下删除文件夹时子文件夹和笔记成为孤儿数据
    // 现在统一：先递归收集所有子文件夹 → 删除所有关联笔记 → 删除所有文件夹
    final allFolderIds = await _collectSubfolderIds(db, id);
    allFolderIds.add(id);

    // 删除所有关联文件夹中的笔记
    for (final folderId in allFolderIds) {
      await db.delete('notes', where: 'folder_id = ?', whereArgs: [folderId]);
    }

    if (_useFFI) {
      // FFI 路径：逐个删除文件夹（按最深层优先避免 FK 冲突）
      for (final folderId in allFolderIds.reversed) {
        await _dispatch.delete(entity: 'folder', id: folderId);
      }
      return;
    }

    developer.log('FFI not available, falling back to sqflite for deleteFolder', level: 900);
    // SQLite 路径：批量删除所有文件夹
    await db.delete(
      'folders',
      where: 'id IN (${List.filled(allFolderIds.length, '?').join(',')})',
      whereArgs: allFolderIds,
    );
  }

  /// 递归收集指定文件夹的所有子文件夹 ID
  Future<List<String>> _collectSubfolderIds(dynamic db, String parentId) async {
    final children = await db.query(
      'folders',
      columns: ['id'],
      where: 'parent_id = ?',
      whereArgs: [parentId],
    );
    final ids = <String>[];
    for (final row in children) {
      final childId = row['id'] as String;
      ids.add(childId);
      ids.addAll(await _collectSubfolderIds(db, childId));
    }
    return ids;
  }

  @override
  Future<FolderModel> updateFolder(FolderModel folder) async {
    // 修复：更新文件夹前检查循环引用
    // 如果设置 parent_id 为自身或子文件夹，会导致无限递归
    if (folder.parentId != null) {
      if (folder.parentId == folder.id) {
        throw ArgumentError('不能将文件夹的父级设为其自身');
      }
      final db = await _dbHelper.database;
      final childIds = await _collectSubfolderIds(db, folder.id);
      if (childIds.contains(folder.parentId)) {
        throw ArgumentError('不能将文件夹移动到其子文件夹中，这会造成循环引用');
      }
    }

    if (_useFFI) {
      final result = await _dispatch.update(entity: 'folder', id: folder.id, data: folder.toJson());
      return FolderModel.fromJson(result);
    }
    developer.log('FFI not available, falling back to sqflite for updateFolder', level: 900);
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