import 'package:uuid/uuid.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/persistence/block_repository.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/core/services/note_block_creation_port.dart';

/// 编辑器服务 - 负责 block 的缓存管理与 Markdown 解析。
///
/// P1 修复 (P1-4): block 持久化逻辑已抽取到 BlockRepository，
/// EditorService 仅保留内存缓存和 Markdown 解析职责，遵循单一职责原则。
///
/// 持久化策略（借鉴思源笔记的设计理念）：
/// 思源笔记的核心设计是"内容块即数据"，每个 block 的增删改都会即时同步到 SQLite，
/// 从而实现本地优先（local-first）的架构。这里采用同样的思路：
///   - _noteBlocks 作为内存缓存，保证 UI 操作的即时响应
///   - 每次 create/update/delete/move/parseMarkdown 操作，先通过 BlockRepository 写入 SQLite，
///     再更新内存缓存，确保数据不会因应用重启而丢失
///   - 打开笔记时通过 loadBlocks() 从 BlockRepository 回读数据到缓存
///   - listBlocks() 在缓存为空时自动从数据库加载（懒加载兜底）
///
/// Markdown 解析优先通过 Rust 端 devnote-editor 引擎执行（FFI），
/// 当 FFI 不可用时回退到 Dart 侧实现。
///
/// P1 修复 (P1-3): 实现 NoteBlockCreationPort 接口，允许 notes 模块
/// 依赖抽象接口而非具体类，打破 notes ↔ editor 循环依赖。
class EditorService implements NoteBlockCreationPort {
  final _uuid = const Uuid();

  // P1 修复 (P1-4): 持久化委托给 BlockRepository
  final BlockRepository _blockRepository;

  /// 内存缓存：noteId → [BlockModel, ...]
  /// UI 从缓存读取以获得即时响应，持久化由 BlockRepository 保证。
  final Map<String, List<BlockModel>> _noteBlocks = {};

  EditorService({BlockRepository? blockRepository})
      : _blockRepository = blockRepository ??
            SqliteBlockRepository(getIt<DatabaseHelper>());

  /// 从 BlockRepository 加载指定笔记的所有 block 到内存缓存。
  /// 在编辑器页面打开时（EditorBloc._onLoadNote）调用。
  Future<void> loadBlocks(String noteId) async {
    _noteBlocks[noteId] = await _blockRepository.loadBlocks(noteId);
  }

  Future<BlockModel> createBlock({
    required String noteId,
    required BlockType blockType,
    required String content,
    required int position,
  }) async {
    // P1 修复 (P1-4): 持久化委托给 BlockRepository
    final block = await _blockRepository.createBlock(
      noteId: noteId,
      blockType: blockType,
      content: content,
      position: position,
    );

    _noteBlocks.putIfAbsent(noteId, () => []);
    // 在缓存中也调整位置，保持一致性
    final cached = _noteBlocks[noteId]!;
    for (var i = 0; i < cached.length; i++) {
      if (cached[i].position >= position) {
        cached[i] = cached[i].copyWith(position: cached[i].position + 1);
      }
    }
    cached.add(block);
    return block;
  }

  /// P1 架构修复: 通过字符串类型名创建 block，避免外部模块 import BlockType enum
  /// 模板类型名与 BlockType.name 一一对应（paragraph/heading1/codeBlock 等），
  /// 未知类型回退为 paragraph。
  @override
  Future<void> createBlockFromString({
    required String noteId,
    required String blockTypeName,
    required String content,
    required int position,
  }) async {
    final blockType = BlockType.values.firstWhere(
      (e) => e.name == blockTypeName,
      orElse: () => BlockType.paragraph,
    );
    await createBlock(
      noteId: noteId,
      blockType: blockType,
      content: content,
      position: position,
    );
  }

  Future<BlockModel?> getBlock(String blockId) async {
    // 缓存优先
    for (final blocks in _noteBlocks.values) {
      final found = blocks.where((b) => b.id == blockId).firstOrNull;
      if (found != null) return found;
    }
    // 缓存未命中时查数据库
    return _blockRepository.getBlock(blockId);
  }

  Future<void> updateBlock({required String blockId, required String content}) async {
    // P1 修复 (P1-4): 持久化委托给 BlockRepository
    await _blockRepository.updateBlock(blockId: blockId, content: content);

    for (final blocks in _noteBlocks.values) {
      final index = blocks.indexWhere((b) => b.id == blockId);
      if (index != -1) {
        blocks[index] = blocks[index].copyWith(content: content, updatedAt: DateTime.now());
        return;
      }
    }
  }

  /// 更新 block 类型并持久化
  Future<void> updateBlockType({required String blockId, required BlockType newType}) async {
    // P1 修复 (P1-4): 持久化委托给 BlockRepository
    await _blockRepository.updateBlockType(blockId: blockId, newType: newType);

    for (final blocks in _noteBlocks.values) {
      final index = blocks.indexWhere((b) => b.id == blockId);
      if (index != -1) {
        blocks[index] = blocks[index].copyWith(blockType: newType, updatedAt: DateTime.now());
        return;
      }
    }
  }

  Future<void> deleteBlock(String blockId) async {
    // P1 修复 (P1-4): 持久化委托给 BlockRepository
    // 先从缓存找到 block 所属的 noteId 和位置，用于缓存更新
    String? noteId;
    int? cacheIndex;
    for (final entry in _noteBlocks.entries) {
      final index = entry.value.indexWhere((b) => b.id == blockId);
      if (index != -1) {
        noteId = entry.key;
        cacheIndex = index;
        break;
      }
    }

    await _blockRepository.deleteBlock(blockId);

    // 更新缓存
    if (noteId != null && cacheIndex != null) {
      final blocks = _noteBlocks[noteId]!;
      blocks.removeAt(cacheIndex);
      // 重排缓存中的 position
      for (var i = 0; i < blocks.length; i++) {
        blocks[i] = blocks[i].copyWith(position: i);
      }
    }
  }

  Future<void> moveBlock({required String blockId, required int newPosition}) async {
    // P1 修复 (P1-4): 持久化委托给 BlockRepository
    // 先在缓存中找到并调整
    for (final blocks in _noteBlocks.values) {
      final index = blocks.indexWhere((b) => b.id == blockId);
      if (index != -1) {
        final block = blocks.removeAt(index);
        final insertAt = newPosition.clamp(0, blocks.length);
        blocks.insert(insertAt, block);
        // 重排缓存中的 position
        for (var i = 0; i < blocks.length; i++) {
          blocks[i] = blocks[i].copyWith(position: i);
        }
        break;
      }
    }

    await _blockRepository.moveBlock(blockId: blockId, newPosition: newPosition);
  }

  Future<List<BlockModel>> listBlocks(String noteId) async {
    // 缓存优先：若缓存有数据则直接返回，否则从数据库加载（懒加载兜底）
    final cached = _noteBlocks[noteId];
    if (cached != null && cached.isNotEmpty) {
      return List<BlockModel>.from(cached)
        ..sort((a, b) => a.position.compareTo(b.position));
    }

    // 缓存为空时从 BlockRepository 加载
    await loadBlocks(noteId);
    final blocks = _noteBlocks[noteId] ?? [];
    return List<BlockModel>.from(blocks)
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  Future<List<BlockModel>> parseMarkdown({required String content, required String noteId}) async {
    // 修复(P2): 删除 _tryParseViaFfi 死代码（原方法永远返回 null，FFIBridge 尚未实现 parseMarkdown）。
    // 直接使用 Dart 侧实现（5 种基础块类型）。
    // TODO: FFIBridge 实现 parseMarkdown 后，优先通过 Rust 端 devnote-editor 引擎执行
    // （9 种块类型 + 表格/任务列表子解析器），Dart 实现作为 FFI 不可用时的兜底。
    return await _parseMarkdownDart(content: content, noteId: noteId);
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

    // P1 修复 (P1-4): 通过 BlockRepository 批量替换，事务保证原子性
    await _blockRepository.replaceBlocks(noteId, blocks);
    _noteBlocks[noteId] = List<BlockModel>.from(blocks);
    return blocks;
  }
}
