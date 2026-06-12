import 'package:uuid/uuid.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/persistence/database_helper.dart';

/// 编辑器服务 - 负责 block 的 CRUD 与 Markdown 解析。
///
/// 持久化策略（借鉴思源笔记的设计理念）：
/// 思源笔记的核心设计是"内容块即数据"，每个 block 的增删改都会即时同步到 SQLite，
/// 从而实现本地优先（local-first）的架构。这里采用同样的思路：
///   - _noteBlocks 作为内存缓存，保证 UI 操作的即时响应
///   - 每次 create/update/delete/move/parseMarkdown 操作，先写入 SQLite，
///     再更新内存缓存，确保数据不会因应用重启而丢失
///   - 打开笔记时通过 loadBlocks() 从 SQLite 回读数据到缓存
///   - listBlocks() 在缓存为空时自动从数据库加载（懒加载兜底）
///
/// Markdown 解析优先通过 Rust 端 devnote-editor 引擎执行（FFI），
/// 当 FFI 不可用时回退到 Dart 侧实现。
class EditorService {
  final _uuid = const Uuid();
  /// 修复：使用 DI 容器中的 DatabaseHelper 单例，避免创建多个数据库连接实例
  /// 原代码 `DatabaseHelper()` 直接 new，绕过 DI 导致多连接、潜在数据不一致
  final DatabaseHelper _db = getIt<DatabaseHelper>();

  /// 内存缓存：noteId → [BlockModel, ...]
  /// UI 从缓存读取以获得即时响应，持久化由 SQLite 保证。
  final Map<String, List<BlockModel>> _noteBlocks = {};

  /// 从 SQLite 加载指定笔记的所有 block 到内存缓存。
  /// 在编辑器页面打开时（EditorBloc._onLoadNote）调用。
  Future<void> loadBlocks(String noteId) async {
    final db = await _db.database;
    final rows = await db.query(
      'blocks',
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'position ASC',
    );
    _noteBlocks[noteId] = rows.map(_rowToBlock).toList();
  }

  Future<BlockModel> createBlock({
    required String noteId,
    required BlockType blockType,
    required String content,
    required int position,
  }) async {
    final now = DateTime.now();
    final block = BlockModel(
      id: _uuid.v4(),
      noteId: noteId,
      blockType: blockType,
      content: content,
      position: position,
      createdAt: now,
      updatedAt: now,
    );

    // 思源笔记风格：先写 SQLite，再更新缓存
    final db = await _db.database;
    await db.insert('blocks', _blockToRow(block, createdAt: now.toIso8601String(), updatedAt: now.toIso8601String()));

    _noteBlocks.putIfAbsent(noteId, () => []);
    _noteBlocks[noteId]!.add(block);
    return block;
  }

  Future<BlockModel?> getBlock(String blockId) async {
    for (final blocks in _noteBlocks.values) {
      final found = blocks.where((b) => b.id == blockId).firstOrNull;
      if (found != null) return found;
    }
    return null;
  }

  Future<void> updateBlock({required String blockId, required String content}) async {
    // 思源笔记风格：先 UPDATE SQLite，再更新缓存
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'blocks',
      {'content': content, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [blockId],
    );

    for (final blocks in _noteBlocks.values) {
      final index = blocks.indexWhere((b) => b.id == blockId);
      if (index != -1) {
        blocks[index] = blocks[index].copyWith(content: content, updatedAt: DateTime.now());
        return;
      }
    }
  }

  /// 更新 block 类型并持久化到 SQLite
  Future<void> updateBlockType({required String blockId, required BlockType newType}) async {
    final db = await _db.database;
    final now = DateTime.now();
    await db.update(
      'blocks',
      {'block_type': newType.name, 'updated_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [blockId],
    );

    for (final blocks in _noteBlocks.values) {
      final index = blocks.indexWhere((b) => b.id == blockId);
      if (index != -1) {
        blocks[index] = blocks[index].copyWith(blockType: newType, updatedAt: now);
        return;
      }
    }
  }

  Future<void> deleteBlock(String blockId) async {
    // 思源笔记风格：先从 SQLite DELETE，再更新缓存
    final db = await _db.database;

    // 修复：将删除和位置重排包装在事务中，确保原子性
    // 原代码先 delete 再循环 update，如果中途某个 update 失败，
    // 位置数据会不一致（部分块位置正确，部分不正确）
    for (final blocks in _noteBlocks.values) {
      final index = blocks.indexWhere((b) => b.id == blockId);
      if (index != -1) {
        await db.transaction((txn) async {
          await txn.delete('blocks', where: 'id = ?', whereArgs: [blockId]);
          blocks.removeAt(index);
          // 删除后重新排位，在事务中批量写回数据库
          for (var i = 0; i < blocks.length; i++) {
            blocks[i] = blocks[i].copyWith(position: i);
            await txn.update(
              'blocks',
              {'position': i, 'updated_at': DateTime.now().toIso8601String()},
              where: 'id = ?',
              whereArgs: [blocks[i].id],
            );
          }
        });
        return;
      }
    }
    // 如果缓存中没找到，仍然尝试从数据库删除
    await db.delete('blocks', where: 'id = ?', whereArgs: [blockId]);
  }

  Future<void> moveBlock({required String blockId, required int newPosition}) async {
    final db = await _db.database;

    // 修复：将移动和位置重排包装在事务中，确保原子性
    // 原代码循环中逐个 db.update 不在事务中，中途失败导致位置不一致
    for (final blocks in _noteBlocks.values) {
      final index = blocks.indexWhere((b) => b.id == blockId);
      if (index != -1) {
        final block = blocks.removeAt(index);
        final insertAt = newPosition.clamp(0, blocks.length);
        blocks.insert(insertAt, block);
        await db.transaction((txn) async {
          // 移动后重新排位，在事务中批量写回数据库
          for (var i = 0; i < blocks.length; i++) {
            blocks[i] = blocks[i].copyWith(position: i);
            await txn.update(
              'blocks',
              {'position': i, 'updated_at': DateTime.now().toIso8601String()},
              where: 'id = ?',
              whereArgs: [blocks[i].id],
            );
          }
        });
        return;
      }
    }
  }

  Future<List<BlockModel>> listBlocks(String noteId) async {
    // 缓存优先：若缓存有数据则直接返回，否则从数据库加载（懒加载兜底）
    final cached = _noteBlocks[noteId];
    if (cached != null && cached.isNotEmpty) {
      return List<BlockModel>.from(cached)
        ..sort((a, b) => a.position.compareTo(b.position));
    }

    // 缓存为空时从 SQLite 加载
    await loadBlocks(noteId);
    final blocks = _noteBlocks[noteId] ?? [];
    return List<BlockModel>.from(blocks)
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  Future<List<BlockModel>> parseMarkdown({required String content, required String noteId}) async {
    // 优先通过 Rust 端 devnote-editor 引擎执行（9 种块类型 + 表格/任务列表子解析器）
    final ffiBlocks = await _tryParseViaFfi(content, noteId);
    if (ffiBlocks != null) {
      await _persistBlocks(noteId, ffiBlocks);
      _noteBlocks[noteId] = List<BlockModel>.from(ffiBlocks);
      return ffiBlocks;
    }
    // FFI 不可用时回退到 Dart 侧实现（5 种基础块类型）
    return await _parseMarkdownDart(content: content, noteId: noteId);
  }

  /// 尝试通过 FFI 调 Rust 解析器；不可用或失败时返回 null
  Future<List<BlockModel>?> _tryParseViaFfi(String content, String noteId) async {
    // FFIBridge 尚未实现 parseMarkdown 方法，直接回退到 Dart 解析器
    return null;
  }

  

  /// 将块列表持久化到 SQLite（思源笔记风格：先清空再批量插入）
  /// 修复：将 DELETE + INSERT 包装在事务中，确保原子性
  /// 原代码先 DELETE 再 INSERT 不在事务中，如果 INSERT 中途失败，
  /// 所有旧数据已被删除，导致笔记内容完全丢失
  Future<void> _persistBlocks(String noteId, List<BlockModel> blocks) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete('blocks', where: 'note_id = ?', whereArgs: [noteId]);
      for (final block in blocks) {
        await txn.insert('blocks', _blockToRow(block, createdAt: now, updatedAt: now));
      }
    });
  }

  /// Dart 侧 Markdown 解析实现（5 种基础块）—— FFI 不可用时的兜底
  Future<List<BlockModel>> _parseMarkdownDart({required String content, required String noteId}) async {
    final lines = content.split('\n');
    final blocks = <BlockModel>[];
    var position = 0;
    var i = 0;
    final now = DateTime.now();

    while (i < lines.length) {
      final line = lines[i];

      if (line.startsWith('```')) {
        final language = line.length > 3 ? line.substring(3).trim() : null;
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        blocks.add(BlockModel(
          id: _uuid.v4(),
          noteId: noteId,
          blockType: BlockType.codeBlock,
          content: codeLines.join('\n'),
          position: position,
          language: language,
          createdAt: now,
          updatedAt: now,
        ));
        position++;
        i++;
      } else if (line.startsWith('###### ')) {
        blocks.add(BlockModel(
          id: _uuid.v4(),
          noteId: noteId,
          blockType: BlockType.heading6,
          content: line.substring(7),
          position: position,
          createdAt: now,
          updatedAt: now,
        ));
        position++;
        i++;
      } else if (line.startsWith('##### ')) {
        blocks.add(BlockModel(
          id: _uuid.v4(),
          noteId: noteId,
          blockType: BlockType.heading5,
          content: line.substring(6),
          position: position,
          createdAt: now,
          updatedAt: now,
        ));
        position++;
        i++;
      } else if (line.startsWith('#### ')) {
        blocks.add(BlockModel(
          id: _uuid.v4(),
          noteId: noteId,
          blockType: BlockType.heading4,
          content: line.substring(5),
          position: position,
          createdAt: now,
          updatedAt: now,
        ));
        position++;
        i++;
      } else if (line.startsWith('### ')) {
        blocks.add(BlockModel(
          id: _uuid.v4(),
          noteId: noteId,
          blockType: BlockType.heading3,
          content: line.substring(4),
          position: position,
          createdAt: now,
          updatedAt: now,
        ));
        position++;
        i++;
      } else if (line.startsWith('## ')) {
        blocks.add(BlockModel(
          id: _uuid.v4(),
          noteId: noteId,
          blockType: BlockType.heading2,
          content: line.substring(3),
          position: position,
          createdAt: now,
          updatedAt: now,
        ));
        position++;
        i++;
      } else if (line.startsWith('# ')) {
        blocks.add(BlockModel(
          id: _uuid.v4(),
          noteId: noteId,
          blockType: BlockType.heading1,
          content: line.substring(2),
          position: position,
          createdAt: now,
          updatedAt: now,
        ));
        position++;
        i++;
      } else if (line.startsWith('> ')) {
        final quoteLines = <String>[line.substring(2)];
        i++;
        while (i < lines.length && lines[i].startsWith('> ')) {
          quoteLines.add(lines[i].substring(2));
          i++;
        }
        blocks.add(BlockModel(
          id: _uuid.v4(),
          noteId: noteId,
          blockType: BlockType.quote,
          content: quoteLines.join('\n'),
          position: position,
          createdAt: now,
          updatedAt: now,
        ));
        position++;
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        final listLines = <String>[line.substring(2)];
        i++;
        while (i < lines.length && (lines[i].startsWith('- ') || lines[i].startsWith('* '))) {
          listLines.add(lines[i].substring(2));
          i++;
        }
        blocks.add(BlockModel(
          id: _uuid.v4(),
          noteId: noteId,
          blockType: BlockType.list,
          content: listLines.join('\n'),
          position: position,
          createdAt: now,
          updatedAt: now,
        ));
        position++;
      } else if (line.trim().isEmpty) {
        i++;
      } else {
        final paragraphLines = <String>[line];
        i++;
        while (i < lines.length &&
            lines[i].trim().isNotEmpty &&
            !lines[i].startsWith('#') &&
            !lines[i].startsWith('```') &&
            !lines[i].startsWith('> ') &&
            !lines[i].startsWith('- ') &&
            !lines[i].startsWith('* ')) {
          paragraphLines.add(lines[i]);
          i++;
        }
        blocks.add(BlockModel(
          id: _uuid.v4(),
          noteId: noteId,
          blockType: BlockType.paragraph,
          content: paragraphLines.join('\n'),
          position: position,
          createdAt: now,
          updatedAt: now,
        ));
        position++;
      }
    }

    // 思源笔记风格：先清空该笔记在数据库中的旧 blocks，
    // 再将新解析出的所有 blocks 批量 INSERT 到 SQLite，最后更新缓存
    await _persistBlocks(noteId, blocks);
    _noteBlocks[noteId] = List<BlockModel>.from(blocks);
    return blocks;
  }

  // ── 数据库序列化辅助方法 ──────────────────────────────────────────

  /// 将 BlockModel 转换为 sqflite 行数据
  Map<String, dynamic> _blockToRow(
    BlockModel block, {
    required String createdAt,
    required String updatedAt,
  }) {
    return {
      'id': block.id,
      'note_id': block.noteId,
      'block_type': block.blockType.name,
      'content': block.content,
      'language': block.language,
      'position': block.position,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// 从 sqflite 行数据还原 BlockModel
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