// 持久化仓库 —— 通过 FFI 桥接调用 Rust 持久化引擎
// 借鉴 AppFlowy 的 Repository + FFI 模式：所有持久化操作经 Dispatch → FFI → Rust 完成
// 来源: https://github.com/AppFlowy-IO/AppFlowy
// 借鉴内容: Repository 模式通过 FFI 桥接调 Rust 持久化层

import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/bridge/persistence_dispatch.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/observability/app_logger.dart';
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
    AppLogger.d('FolderRepository', 'FFI not available, falling back to sqflite for createFolder');
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
    AppLogger.d('FolderRepository', 'FFI not available, falling back to sqflite for listFolders');
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
    // Phase 2 架构修复: 消除跨库操作。
    // 原问题: 无论 FFI 是否可用，都先用 sqflite 收集子文件夹和删除笔记，
    // 再用 FFI 删除文件夹。FFI 模式下文件夹在 Rust DB，sqflite 查不到子文件夹，
    // 导致孤儿数据和关联笔记未被清理。
    // 修复: FFI 模式下全部操作走 Rust 持久层；sqflite 模式下全部走 Dart 持久层。
    if (_useFFI) {
      final allFolderIds = await _collectSubfolderIdsViaFFI(id);
      allFolderIds.add(id);

      // 删除每个文件夹中的笔记（FFI 路径）
      for (final folderId in allFolderIds) {
        final notes = await _dispatch.list(entity: 'note', filter: {'folder_id': folderId});
        for (final note in notes) {
          final noteId = note['id'] as String;
          await _dispatch.delete(entity: 'note', id: noteId);
        }
      }

      // 删除所有文件夹（按最深层优先避免 FK 冲突）
      for (final folderId in allFolderIds.reversed) {
        await _dispatch.delete(entity: 'folder', id: folderId);
      }
      return;
    }

    AppLogger.d('FolderRepository', 'FFI not available, falling back to sqflite for deleteFolder');
    final db = await _dbHelper.database;
    final allFolderIds = await _collectSubfolderIdsViaSqflite(db, id);
    allFolderIds.add(id);

    // P1 修复 (P1-7): 删除笔记 + 删除文件夹包裹在事务中，
    // 确保级联删除原子完成，避免中途失败产生孤儿数据
    await db.transaction((txn) async {
      // 删除所有关联文件夹中的笔记
      for (final folderId in allFolderIds) {
        await txn.delete('notes', where: 'folder_id = ?', whereArgs: [folderId]);
      }

      // 批量删除所有文件夹
      await txn.delete(
        'folders',
        where: 'id IN (${List.filled(allFolderIds.length, '?').join(',')})',
        whereArgs: allFolderIds,
      );
    });
  }

  /// 通过 FFI 递归收集指定文件夹的所有子文件夹 ID
  Future<List<String>> _collectSubfolderIdsViaFFI(String parentId) async {
    final children = await _dispatch.list(entity: 'folder', filter: {'parent_id': parentId});
    final ids = <String>[];
    for (final child in children) {
      final childId = child['id'] as String;
      ids.add(childId);
      ids.addAll(await _collectSubfolderIdsViaFFI(childId));
    }
    return ids;
  }

  /// 通过 sqflite 递归收集指定文件夹的所有子文件夹 ID
  Future<List<String>> _collectSubfolderIdsViaSqflite(dynamic db, String parentId) async {
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
      ids.addAll(await _collectSubfolderIdsViaSqflite(db, childId));
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
      // Phase 2 架构修复: 循环引用检查必须与更新操作使用同一持久层，
      // 否则 FFI 模式下 sqflite 查不到 Rust DB 中的子文件夹，检查失效。
      final childIds = _useFFI
          ? await _collectSubfolderIdsViaFFI(folder.id)
          : await _collectSubfolderIdsViaSqflite(await _dbHelper.database, folder.id);
      if (childIds.contains(folder.parentId)) {
        throw ArgumentError('不能将文件夹移动到其子文件夹中，这会造成循环引用');
      }
    }

    if (_useFFI) {
      final result = await _dispatch.update(entity: 'folder', id: folder.id, data: folder.toJson());
      return FolderModel.fromJson(result);
    }
    AppLogger.d('FolderRepository', 'FFI not available, falling back to sqflite for updateFolder');
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
