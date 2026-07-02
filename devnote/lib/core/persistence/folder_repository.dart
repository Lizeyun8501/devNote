// 持久化仓库 —— 通过 FFI 桥接调用 Rust 持久化引擎
// 借鉴 AppFlowy 的 Repository + FFI 模式：所有持久化操作经 Dispatch → FFI → Rust 完成
// 来源: https://github.com/AppFlowy-IO/AppFlowy
// 借鉴内容: Repository 模式通过 FFI 桥接调 Rust 持久化层
//
// P1 修复 (双源分支移除): 彻底删除 _useFFI 分支与 sqflite 兜底路径。
// 原 _useFFI 双源分支违反 ADR-003/004 单一数据源原则——FFI 可用时写入 Rust DB，
// 不可用时写入 sqflite，切换模式会导致数据分裂与丢失。现统一为 FFI 单一数据源。

import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/core/persistence/models/folder_model.dart';

abstract class FolderRepository {
  Future<FolderModel> createFolder(FolderModel folder);
  Future<List<FolderModel>> listFolders(String? parentId);
  Future<void> deleteFolder(String id);
  Future<FolderModel> updateFolder(FolderModel folder);
}

class SqliteFolderRepository implements FolderRepository {
  // P1 修复: _dbHelper 保留以维持 DI 构造签名兼容，FFI 为唯一数据源后不再使用 sqflite。
  final DatabaseHelper _dbHelper;
  // P1 修复 (2-E): 直接使用 Dispatch 类型安全方法，消除 PersistenceDispatch 冗余转换层
  final Dispatch _dispatch = Dispatch();

  SqliteFolderRepository(this._dbHelper);

  @override
  Future<FolderModel> createFolder(FolderModel folder) async {
    return await _dispatch.createFolder(
      name: folder.name,
      parentId: folder.parentId,
    );
  }

  @override
  Future<List<FolderModel>> listFolders(String? parentId) async {
    return await _dispatch.listFolders(parentId: parentId);
  }

  @override
  Future<void> deleteFolder(String id) async {
    // Phase 2 架构修复: 级联删除全部走 Rust 持久层，消除跨库操作。
    final allFolderIds = await _collectSubfolderIdsViaFFI(id);
    allFolderIds.add(id);

    // 删除每个文件夹中的笔记（FFI 路径）
    for (final folderId in allFolderIds) {
      final notes = await _dispatch.listNotes(folderId);
      for (final note in notes) {
        await _dispatch.deleteNote(note.id);
      }
    }

    // 删除所有文件夹（按最深层优先避免 FK 冲突）
    for (final folderId in allFolderIds.reversed) {
      await _dispatch.deleteFolder(folderId);
    }
  }

  /// 通过 FFI 递归收集指定文件夹的所有子文件夹 ID
  Future<List<String>> _collectSubfolderIdsViaFFI(String parentId) async {
    final children = await _dispatch.listFolders(parentId: parentId);
    final ids = <String>[];
    for (final child in children) {
      ids.add(child.id);
      ids.addAll(await _collectSubfolderIdsViaFFI(child.id));
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
      // 循环引用检查走 FFI（Rust DB），与更新操作使用同一持久层
      final childIds = await _collectSubfolderIdsViaFFI(folder.id);
      if (childIds.contains(folder.parentId)) {
        throw ArgumentError('不能将文件夹移动到其子文件夹中，这会造成循环引用');
      }
    }

    return await _dispatch.updateFolder(
      id: folder.id,
      name: folder.name,
      parentId: folder.parentId,
    );
  }
}
