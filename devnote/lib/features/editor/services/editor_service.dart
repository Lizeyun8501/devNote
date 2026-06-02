import 'package:uuid/uuid.dart';
import 'package:devnote/features/editor/models/block_model.dart';

class EditorService {
  final _uuid = const Uuid();
  final Map<String, List<BlockModel>> _noteBlocks = {};

  Future<BlockModel> createBlock({
    required String noteId,
    required BlockType blockType,
    required String content,
    required int position,
  }) async {
    final block = BlockModel(
      id: _uuid.v4(),
      noteId: noteId,
      blockType: blockType,
      content: content,
      position: position,
    );
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
    for (final blocks in _noteBlocks.values) {
      final index = blocks.indexWhere((b) => b.id == blockId);
      if (index != -1) {
        blocks[index] = blocks[index].copyWith(content: content);
        return;
      }
    }
  }

  Future<void> deleteBlock(String blockId) async {
    for (final blocks in _noteBlocks.values) {
      final index = blocks.indexWhere((b) => b.id == blockId);
      if (index != -1) {
        blocks.removeAt(index);
        for (var i = 0; i < blocks.length; i++) {
          blocks[i] = blocks[i].copyWith(position: i);
        }
        return;
      }
    }
  }

  Future<void> moveBlock({required String blockId, required int newPosition}) async {
    for (final blocks in _noteBlocks.values) {
      final index = blocks.indexWhere((b) => b.id == blockId);
      if (index != -1) {
        final block = blocks.removeAt(index);
        final insertAt = newPosition.clamp(0, blocks.length);
        blocks.insert(insertAt, block);
        for (var i = 0; i < blocks.length; i++) {
          blocks[i] = blocks[i].copyWith(position: i);
        }
        return;
      }
    }
  }

  Future<List<BlockModel>> listBlocks(String noteId) async {
    final blocks = _noteBlocks[noteId] ?? [];
    return List<BlockModel>.from(blocks)..sort((a, b) => a.position.compareTo(b.position));
  }

  Future<List<BlockModel>> parseMarkdown({required String content, required String noteId}) async {
    final lines = content.split('\n');
    final blocks = <BlockModel>[];
    var position = 0;
    var i = 0;

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
        ));
        position++;
      }
    }

    _noteBlocks[noteId] = List<BlockModel>.from(blocks);
    return blocks;
  }
}
