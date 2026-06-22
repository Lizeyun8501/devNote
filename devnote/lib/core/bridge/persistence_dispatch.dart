/// 持久化分发层 —— 基于 FRB 的类型安全持久化调用
///
/// ## 替换说明
/// 原实现：通过 Event-Dispatch 字符串路由调用 Rust 持久化引擎
/// 替换为：直接调用 FRB Dispatch 的类型安全方法
///
/// ## 核心变更
/// 1. 消除 _EntityEventMap 字符串路由映射
/// 2. 消除 _call() 的 JSON 编解码
/// 3. 直接调用 dispatch.createNote/listNotes 等方法
/// 4. 保留 list/create/update/delete 通用接口（供 Repository 层使用）
///
/// 来源: https://pub.dev/packages/flutter_rust_bridge
/// 借鉴 AppFlowy 的 Repository + FFI 模式（已升级为 FRB 直接调用）

import 'dispatch.dart';

class PersistenceDispatch {
  static final PersistenceDispatch _instance = PersistenceDispatch._();
  factory PersistenceDispatch() => _instance;
  PersistenceDispatch._();

  final _dispatch = Dispatch();

  /// 列表查询 —— 直接调用 FRB 类型安全方法
  /// 修复: 返回 Map 列表(序列化后的 model),而非 model 列表
  Future<List<Map<String, dynamic>>> list({
    required String entity,
    Map<String, dynamic>? filter,
  }) async {
    switch (entity) {
      case 'note':
        final folderId = filter?['folder_id'] as String? ?? '';
        final list = await _dispatch.listNotes(folderId);
        return list.map((m) => m.toJson()).toList();
      case 'folder':
        final parentId = filter?['parent_id'] as String?;
        final list = await _dispatch.listFolders(parentId: parentId);
        return list.map((m) => m.toJson()).toList();
      case 'tag':
        final list = await _dispatch.listTags();
        return list.map((m) => m.toJson()).toList();
      case 'block':
        final noteId = filter?['note_id'] as String? ?? '';
        final list = await _dispatch.getBlocks(noteId);
        return list.map((m) => m.toJson()).toList();
      default:
        return [];
    }
  }

  /// 创建实体 —— 直接调用 FRB 类型安全方法
  Future<Map<String, dynamic>> create({
    required String entity,
    required Map<String, dynamic> data,
  }) async {
    switch (entity) {
      case 'note':
        final result = await _dispatch.createNote(
          title: data['title'] as String,
          content: data['content'] as String,
          folderId: data['folder_id'] as String,
        );
        return result.toJson();
      case 'folder':
        final result = await _dispatch.createFolder(
          name: data['name'] as String,
          parentId: data['parent_id'] as String?,
        );
        return result.toJson();
      case 'tag':
        final result = await _dispatch.createTag(data['name'] as String);
        return result.toJson();
      case 'block':
        final result = await _dispatch.insertBlock(
          noteId: data['note_id'] as String,
          blockType: data['block_type'] as String,
          content: data['content'] as String,
          position: data['position'] as int?,
        );
        return result.toJson();
      default:
        throw UnimplementedError('Entity not supported: $entity');
    }
  }

  /// 更新实体 —— 直接调用 FRB 类型安全方法
  Future<Map<String, dynamic>> update({
    required String entity,
    required String id,
    required Map<String, dynamic> data,
  }) async {
    switch (entity) {
      case 'note':
        final result = await _dispatch.updateNote(
          id: id,
          title: data['title'] as String,
          content: data['content'] as String,
        );
        return result.toJson();
      case 'folder':
        // 修复: 补全 folder update 路径，原代码缺失此 case 导致 UnimplementedError
        final result = await _dispatch.updateFolder(
          id: id,
          name: data['name'] as String,
          parentId: data['parent_id'] as String?,
        );
        return result.toJson();
      case 'block':
        await _dispatch.updateBlock(id: id, content: data['content'] as String);
        return {'id': id};
      case 'tag':
        // Rust 端无 TagEvent.UpdateTag handler，tag 更新需走 sqflite 路径
        throw UnimplementedError('Tag update not supported via FFI; use sqflite path');
      default:
        throw UnimplementedError('Entity not supported for update: $entity');
    }
  }

  /// 删除实体 —— 直接调用 FRB 类型安全方法
  Future<void> delete({
    required String entity,
    required String id,
  }) async {
    switch (entity) {
      case 'note':
        await _dispatch.deleteNote(id);
      case 'folder':
        await _dispatch.deleteFolder(id);
      case 'tag':
        await _dispatch.deleteTag(id);
      case 'block':
        await _dispatch.deleteBlock(id);
      default:
        throw UnimplementedError('Entity not supported for delete: $entity');
    }
  }

  /// 获取单个实体
  Future<Map<String, dynamic>?> get({
    required String entity,
    required String id,
  }) async {
    switch (entity) {
      case 'note':
        final result = await _dispatch.getNote(id);
        return result?.toJson();
      case 'folder':
        // 修复(P0): 补全 folder get 路径，原缺失导致抛 UnimplementedError
        final result = await _dispatch.getFolder(id);
        return result?.toJson();
      case 'block':
        // Rust 端无 EditorEvent.GetBlock 单个查询 handler，通过 GetBlocks 取全部后过滤
        final noteId = id; // 注意：block 的 get 语义为按 noteId 查询块列表
        final blocks = await _dispatch.getBlocks(noteId);
        return {'blocks': blocks.map((b) => b.toJson()).toList()};
      case 'tag':
        // Rust 端无 TagEvent.GetTag handler，tag 查询需走 sqflite 路径
        throw UnimplementedError('Tag get not supported via FFI; use sqflite path');
      default:
        throw UnimplementedError('Entity not supported for get: $entity');
    }
  }
}
