// P1 修复 (P1-4): 补齐 Block Repository 抽象
//
// 将 block 持久化逻辑从 EditorService 抽取到独立的 Repository，
// 遵循现有 NoteRepository/FolderRepository/TagRepository 的抽象模式。
//
// 拆分理由:
// 1. EditorService 混合了缓存管理、SQL 操作、Markdown 解析三重职责，违反 SRP
// 2. block 持久化散落在 Service 层而非 Repository 层，违反分层架构
// 3. FFI 路径（Dispatch.insertBlock 等）已存在但未接入，Repository 化后可统一接入
// 4. 与 NoteRepository 模式对齐，便于未来实现 FFI 优先 + sqflite 兜底双路径
//
// P1 修复 (双源分支移除): 彻底删除 _useFFI 分支与 sqflite 兜底路径。
// 原 _useFFI 双源分支违反 ADR-003/004 单一数据源原则——FFI 可用时写入 Rust DB，
// 不可用时写入 sqflite，切换模式会导致数据分裂与丢失。现统一为 FFI 单一数据源，
// FFI 不可用时错误向上传播，由调用方决定降级策略。

import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/features/editor/models/block_model.dart';

/// Block Repository 抽象接口
///
/// 定义 block 持久化操作的领域契约，与 NoteRepository/FolderRepository 模式一致。
/// 实现方负责具体的 FFI 调用。
abstract class BlockRepository {
  /// 加载指定笔记的所有 block（按 position 升序）
  Future<List<BlockModel>> loadBlocks(String noteId);

  /// 创建新 block，自动将 position >= 新位置的已有 block 后移一格
  Future<BlockModel> createBlock({
    required String noteId,
    required BlockType blockType,
    required String content,
    required int position,
    String? language,
  });

  /// 获取单个 block by ID
  Future<BlockModel?> getBlock(String blockId);

  /// 更新 block 内容
  Future<void> updateBlock({required String blockId, required String content});

  /// 更新 block 类型
  Future<void> updateBlockType({
    required String blockId,
    required BlockType newType,
  });

  /// 删除 block，自动重排剩余 block 的 position
  Future<void> deleteBlock(String blockId);

  /// 移动 block 到新位置，自动重排其他 block 的 position
  Future<void> moveBlock({required String blockId, required int newPosition});

  /// 批量替换指定笔记的所有 block（先清空再批量插入，事务保证原子性）
  ///
  /// 用于 Markdown 解析后批量写入。
  Future<void> replaceBlocks(String noteId, List<BlockModel> blocks);
}

/// FFI 单一数据源的 BlockRepository 实现
///
/// P1 修复 (双源分支移除): 所有 block 操作通过 Dispatch 调用 Rust 端 block API，
/// 数据统一写入 Rust 的 devnote.db，消除双库数据分裂。
class SqliteBlockRepository implements BlockRepository {
  // P1 修复: _dbHelper 保留以维持 DI 构造签名兼容，FFI 为唯一数据源后不再使用 sqflite。
  final DatabaseHelper _dbHelper;
  final Dispatch _dispatch;

  SqliteBlockRepository(this._dbHelper) : _dispatch = Dispatch();

  @override
  Future<List<BlockModel>> loadBlocks(String noteId) async {
    return await _dispatch.getBlocks(noteId);
  }

  @override
  Future<BlockModel> createBlock({
    required String noteId,
    required BlockType blockType,
    required String content,
    required int position,
    String? language,
  }) async {
    // FFI 路径：调用 Rust 端 insert_block
    // Rust 端会自动处理 position 后移逻辑
    return await _dispatch.insertBlock(
      noteId: noteId,
      blockType: blockType.name,
      content: content,
      position: position,
    );
  }

  @override
  Future<BlockModel?> getBlock(String blockId) async {
    // P1 架构修复 (3.3): 通过 FFI 调用 Rust 端 get_block 单查询
    return await _dispatch.getBlock(blockId);
  }

  @override
  Future<void> updateBlock({
    required String blockId,
    required String content,
  }) async {
    await _dispatch.updateBlock(id: blockId, content: content);
  }

  @override
  Future<void> updateBlockType({
    required String blockId,
    required BlockType newType,
  }) async {
    // P1 架构修复 (3.3): 通过 FFI 调用 Rust 端 update_block_type
    await _dispatch.updateBlockType(id: blockId, blockType: newType.name);
  }

  @override
  Future<void> deleteBlock(String blockId) async {
    await _dispatch.deleteBlock(blockId);
  }

  @override
  Future<void> moveBlock({
    required String blockId,
    required int newPosition,
  }) async {
    // P1 架构修复 (3.3): 通过 FFI 调用 Rust 端 move_block
    await _dispatch.moveBlock(id: blockId, newPosition: newPosition);
  }

  @override
  Future<void> replaceBlocks(String noteId, List<BlockModel> blocks) async {
    // P1 架构修复 (3.3): 通过 FFI 调用 Rust 端 replace_blocks
    await _dispatch.replaceBlocks(noteId: noteId, blocks: blocks);
  }
}
