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
// P0 修复（双持久化统一）: BlockRepository 现已支持 FFI 优先路径，
// 与 NoteRepository 模式对齐。block 数据统一写入 Rust 的 devnote.db，
// 消除双库数据分裂。FFI 不可用时回退到 sqflite 兜底。

import 'package:uuid/uuid.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/observability/app_logger.dart';
import 'package:devnote/features/editor/models/block_model.dart';

/// Block Repository 抽象接口
///
/// 定义 block 持久化操作的领域契约，与 NoteRepository/FolderRepository 模式一致。
/// 实现方负责具体的 SQL 操作或 FFI 调用。
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

/// FFI 优先 + sqflite 兜底的 BlockRepository 实现
///
/// P0 修复（双持久化统一）:
/// - FFI 可用时：通过 Dispatch 调用 Rust 端 block API，数据写入 Rust 的 devnote.db
/// - FFI 不可用时：回退到 sqflite，保证应用仍可用
/// - 与 NoteRepository 模式完全对齐，消除双库数据分裂
class SqliteBlockRepository implements BlockRepository {
  final DatabaseHelper _dbHelper;
  final FFIBridge _bridge;
  final Dispatch _dispatch;
  final _uuid = const Uuid();

  SqliteBlockRepository(this._dbHelper)
      : _bridge = getIt<FFIBridge>(),
        _dispatch = Dispatch();

  bool get _useFFI => _bridge.isAvailable;

  @override
  Future<List<BlockModel>> loadBlocks(String noteId) async {
    if (_useFFI) {
      try {
        return await _dispatch.getBlocks(noteId);
      } catch (e) {
        AppLogger.w('BlockRepository', 'FFI loadBlocks failed, falling back to sqflite', error: e);
      }
    }
    AppLogger.d('BlockRepository', 'FFI not available, using sqflite for loadBlocks');
    final db = await _dbHelper.database;
    final rows = await db.query(
      'blocks',
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'position ASC',
    );
    return rows.map(_rowToBlock).toList();
  }

  @override
  Future<BlockModel> createBlock({
    required String noteId,
    required BlockType blockType,
    required String content,
    required int position,
    String? language,
  }) async {
    if (_useFFI) {
      try {
        // FFI 路径：调用 Rust 端 insert_block
        // Rust 端会自动处理 position 后移逻辑
        final block = await _dispatch.insertBlock(
          noteId: noteId,
          blockType: blockType.name,
          content: content,
          position: position,
        );
        return block;
      } catch (e) {
        AppLogger.w('BlockRepository', 'FFI createBlock failed, falling back to sqflite', error: e);
      }
    }
    AppLogger.d('BlockRepository', 'FFI not available, using sqflite for createBlock');
    final now = DateTime.now();
    final block = BlockModel(
      id: _uuid.v4(),
      noteId: noteId,
      blockType: blockType,
      content: content,
      position: position,
      language: language,
      createdAt: now,
      updatedAt: now,
    );

    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      // 将 position >= 新位置的所有已有 block 向后移动一格
      await txn.execute(
        'UPDATE blocks SET position = position + 1, updated_at = ? '
        'WHERE note_id = ? AND position >= ?',
        [now.toIso8601String(), noteId, position],
      );
      await txn.insert('blocks', _blockToRow(block));
    });

    return block;
  }

  @override
  Future<BlockModel?> getBlock(String blockId) async {
    if (_useFFI) {
      try {
        // P1 架构修复 (3.3): 通过 FFI 调用 Rust 端 get_block 单查询
        return await _dispatch.getBlock(blockId);
      } catch (e) {
        AppLogger.w('BlockRepository', 'FFI getBlock failed, falling back to sqflite', error: e);
      }
    }
    AppLogger.d('BlockRepository', 'FFI not available, using sqflite for getBlock');
    final db = await _dbHelper.database;
    final rows = await db.query(
      'blocks',
      where: 'id = ?',
      whereArgs: [blockId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToBlock(rows.first);
  }

  @override
  Future<void> updateBlock({
    required String blockId,
    required String content,
  }) async {
    if (_useFFI) {
      try {
        await _dispatch.updateBlock(id: blockId, content: content);
        return;
      } catch (e) {
        AppLogger.w('BlockRepository', 'FFI updateBlock failed, falling back to sqflite', error: e);
      }
    }
    AppLogger.d('BlockRepository', 'FFI not available, using sqflite for updateBlock');
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'blocks',
      {'content': content, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [blockId],
    );
  }

  @override
  Future<void> updateBlockType({
    required String blockId,
    required BlockType newType,
  }) async {
    if (_useFFI) {
      try {
        // P1 架构修复 (3.3): 通过 FFI 调用 Rust 端 update_block_type
        await _dispatch.updateBlockType(id: blockId, blockType: newType.name);
        return;
      } catch (e) {
        AppLogger.w('BlockRepository', 'FFI updateBlockType failed, falling back to sqflite', error: e);
      }
    }
    AppLogger.d('BlockRepository', 'FFI not available, using sqflite for updateBlockType');
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'blocks',
      {'block_type': newType.name, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [blockId],
    );
  }

  @override
  Future<void> deleteBlock(String blockId) async {
    if (_useFFI) {
      try {
        await _dispatch.deleteBlock(blockId);
        return;
      } catch (e) {
        AppLogger.w('BlockRepository', 'FFI deleteBlock failed, falling back to sqflite', error: e);
      }
    }
    AppLogger.d('BlockRepository', 'FFI not available, using sqflite for deleteBlock');
    final db = await _dbHelper.database;
    // 先查出 noteId 和 position，用于删除后重排
    final rows = await db.query(
      'blocks',
      where: 'id = ?',
      whereArgs: [blockId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final noteId = rows.first['note_id'] as String;
    final deletedPosition = (rows.first['position'] as num?)?.toInt() ?? 0;

    await db.transaction((txn) async {
      await txn.delete('blocks', where: 'id = ?', whereArgs: [blockId]);
      // 删除后重排：position > deletedPosition 的块前移一格
      await txn.execute(
        'UPDATE blocks SET position = position - 1, updated_at = ? '
        'WHERE note_id = ? AND position > ?',
        [DateTime.now().toIso8601String(), noteId, deletedPosition],
      );
    });
  }

  @override
  Future<void> moveBlock({
    required String blockId,
    required int newPosition,
  }) async {
    if (_useFFI) {
      try {
        // P1 架构修复 (3.3): 通过 FFI 调用 Rust 端 move_block
        await _dispatch.moveBlock(id: blockId, newPosition: newPosition);
        return;
      } catch (e) {
        AppLogger.w('BlockRepository', 'FFI moveBlock failed, falling back to sqflite', error: e);
      }
    }
    AppLogger.d('BlockRepository', 'FFI not available, using sqflite for moveBlock');
    final db = await _dbHelper.database;
    final rows = await db.query(
      'blocks',
      where: 'id = ?',
      whereArgs: [blockId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final noteId = rows.first['note_id'] as String;
    final oldPosition = (rows.first['position'] as num?)?.toInt() ?? 0;

    await db.transaction((txn) async {
      if (newPosition > oldPosition) {
        // 向下移动：中间块前移
        await txn.execute(
          'UPDATE blocks SET position = position - 1, updated_at = ? '
          'WHERE note_id = ? AND position > ? AND position <= ?',
          [DateTime.now().toIso8601String(), noteId, oldPosition, newPosition],
        );
      } else if (newPosition < oldPosition) {
        // 向上移动：中间块后移
        await txn.execute(
          'UPDATE blocks SET position = position + 1, updated_at = ? '
          'WHERE note_id = ? AND position >= ? AND position < ?',
          [DateTime.now().toIso8601String(), noteId, newPosition, oldPosition],
        );
      }
      // 移动目标块到新位置
      await txn.update(
        'blocks',
        {'position': newPosition, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [blockId],
      );
    });
  }

  @override
  Future<void> replaceBlocks(String noteId, List<BlockModel> blocks) async {
    if (_useFFI) {
      try {
        // P1 架构修复 (3.3): 通过 FFI 调用 Rust 端 replace_blocks
        await _dispatch.replaceBlocks(noteId: noteId, blocks: blocks);
        return;
      } catch (e) {
        AppLogger.w('BlockRepository', 'FFI replaceBlocks failed, falling back to sqflite', error: e);
      }
    }
    AppLogger.d('BlockRepository', 'FFI not available, using sqflite for replaceBlocks');
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete('blocks', where: 'note_id = ?', whereArgs: [noteId]);
      for (final block in blocks) {
        await txn.insert('blocks', _blockToRow(block, createdAt: now, updatedAt: now));
      }
    });
  }

  // ── 序列化辅助方法 ──────────────────────────────────────────

  Map<String, dynamic> _blockToRow(
    BlockModel block, {
    String? createdAt,
    String? updatedAt,
  }) {
    final created = createdAt ?? block.createdAt.toIso8601String();
    final updated = updatedAt ?? block.updatedAt.toIso8601String();
    return {
      'id': block.id,
      'note_id': block.noteId,
      'block_type': block.blockType.name,
      'content': block.content,
      'language': block.language,
      'position': block.position,
      'created_at': created,
      'updated_at': updated,
    };
  }

  BlockModel _rowToBlock(Map<String, dynamic> row) {
    final now = DateTime.now();
    return BlockModel(
      id: row['id'] as String,
      noteId: row['note_id'] as String,
      blockType: BlockType.values.firstWhere(
        (e) => e.name == row['block_type'],
        orElse: () => BlockType.paragraph,
      ),
      content: (row['content'] as String?) ?? '',
      position: (row['position'] as int?) ?? 0,
      language: row['language'] as String?,
      createdAt: _parseDate(row['created_at']) ?? now,
      updatedAt: _parseDate(row['updated_at']) ?? now,
    );
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
