// BlockModel 单元测试
//
// 测试两种 BlockModel：
// 1. 持久化层 BlockModel（Freezed，用于数据库序列化）
// 2. 编辑器层 BlockModel（Equatable，用于 UI 编辑）
// 验证构造、序列化、copyWith、相等性、BlockType 枚举。

import 'package:flutter_test/flutter_test.dart';
import 'package:devnote/core/persistence/models/block_model.dart' as persistence;
import 'package:devnote/features/editor/models/block_model.dart';

void main() {
  final testTime = DateTime(2024, 1, 15, 10, 30);

  group('持久化层 BlockModel (Freezed)', () {
    test('构造 BlockModel', () {
      final block = persistence.BlockModel(
        id: 'block-1',
        noteId: 'note-1',
        blockType: 'paragraph',
        content: '内容',
        position: 0,
      );
      expect(block.id, 'block-1');
      expect(block.noteId, 'note-1');
      expect(block.blockType, 'paragraph');
      expect(block.content, '内容');
      expect(block.position, 0);
    });

    test('toJson 映射字段为 snake_case', () {
      final block = persistence.BlockModel(
        id: 'block-1',
        noteId: 'note-1',
        blockType: 'heading1',
        content: '标题',
        position: 1,
      );
      final json = block.toJson();
      expect(json['id'], 'block-1');
      expect(json['note_id'], 'note-1');
      expect(json['block_type'], 'heading1');
      expect(json['content'], '标题');
      expect(json['position'], 1);
    });

    test('fromJson 反序列化', () {
      final json = {
        'id': 'block-1',
        'note_id': 'note-1',
        'block_type': 'codeBlock',
        'content': 'print("hello")',
        'position': 2,
      };
      final block = persistence.BlockModel.fromJson(json);
      expect(block.id, 'block-1');
      expect(block.noteId, 'note-1');
      expect(block.blockType, 'codeBlock');
      expect(block.content, 'print("hello")');
      expect(block.position, 2);
    });

    test('toJson → fromJson 往返一致', () {
      final original = persistence.BlockModel(
        id: 'block-1',
        noteId: 'note-1',
        blockType: 'list',
        content: '列表项',
        position: 3,
      );
      final restored = persistence.BlockModel.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.noteId, original.noteId);
      expect(restored.blockType, original.blockType);
      expect(restored.content, original.content);
      expect(restored.position, original.position);
    });

    test('相同字段的 BlockModel 相等', () {
      final block1 = persistence.BlockModel(
        id: 'block-1',
        noteId: 'note-1',
        blockType: 'paragraph',
        content: '内容',
        position: 0,
      );
      final block2 = persistence.BlockModel(
        id: 'block-1',
        noteId: 'note-1',
        blockType: 'paragraph',
        content: '内容',
        position: 0,
      );
      expect(block1, equals(block2));
    });
  });

  group('编辑器层 BlockModel (Equatable)', () {
    test('构造 BlockModel 包含所有字段', () {
      final block = BlockModel(
        id: 'block-1',
        noteId: 'note-1',
        blockType: BlockType.paragraph,
        content: '段落内容',
        position: 0,
        language: null,
        createdAt: testTime,
        updatedAt: testTime,
      );
      expect(block.id, 'block-1');
      expect(block.noteId, 'note-1');
      expect(block.blockType, BlockType.paragraph);
      expect(block.content, '段落内容');
      expect(block.position, 0);
      expect(block.language, isNull);
      expect(block.children, isEmpty);
      expect(block.createdAt, testTime);
      expect(block.updatedAt, testTime);
    });

    test('copyWith 修改部分字段', () {
      final original = BlockModel(
        id: 'block-1',
        noteId: 'note-1',
        blockType: BlockType.paragraph,
        content: '原内容',
        position: 0,
        createdAt: testTime,
        updatedAt: testTime,
      );
      final copied = original.copyWith(
        content: '新内容',
        blockType: BlockType.heading1,
      );
      expect(copied.id, 'block-1');
      expect(copied.content, '新内容');
      expect(copied.blockType, BlockType.heading1);
      expect(copied.position, 0);
    });

    test('copyWith 修改 language 字段', () {
      final original = BlockModel(
        id: 'block-1',
        noteId: 'note-1',
        blockType: BlockType.codeBlock,
        content: 'print("hello")',
        position: 0,
        createdAt: testTime,
        updatedAt: testTime,
      );
      final copied = original.copyWith(language: 'python');
      expect(copied.language, 'python');
      expect(copied.content, 'print("hello")');
    });

    test('相同 props 的 BlockModel 相等', () {
      final block1 = BlockModel(
        id: 'block-1',
        noteId: 'note-1',
        blockType: BlockType.paragraph,
        content: '内容',
        position: 0,
        createdAt: testTime,
        updatedAt: testTime,
      );
      final block2 = BlockModel(
        id: 'block-1',
        noteId: 'note-1',
        blockType: BlockType.paragraph,
        content: '内容',
        position: 0,
        createdAt: testTime,
        updatedAt: testTime,
      );
      expect(block1, equals(block2));
      expect(block1.hashCode, block2.hashCode);
    });

    test('不同 ID 的 BlockModel 不相等', () {
      final block1 = BlockModel(
        id: 'block-1',
        noteId: 'note-1',
        blockType: BlockType.paragraph,
        content: '',
        position: 0,
        createdAt: testTime,
        updatedAt: testTime,
      );
      final block2 = BlockModel(
        id: 'block-2',
        noteId: 'note-1',
        blockType: BlockType.paragraph,
        content: '',
        position: 0,
        createdAt: testTime,
        updatedAt: testTime,
      );
      expect(block1, isNot(equals(block2)));
    });
  });

  group('BlockType 枚举', () {
    test('包含所有预期的块类型', () {
      expect(BlockType.values, contains(BlockType.paragraph));
      expect(BlockType.values, contains(BlockType.heading1));
      expect(BlockType.values, contains(BlockType.heading6));
      expect(BlockType.values, contains(BlockType.codeBlock));
      expect(BlockType.values, contains(BlockType.list));
      expect(BlockType.values, contains(BlockType.orderedList));
      expect(BlockType.values, contains(BlockType.quote));
      expect(BlockType.values, contains(BlockType.tableBlock));
      expect(BlockType.values, contains(BlockType.image));
      expect(BlockType.values, contains(BlockType.latexBlock));
      expect(BlockType.values, contains(BlockType.taskListBlock));
      expect(BlockType.values, contains(BlockType.pdf));
      expect(BlockType.values, contains(BlockType.whiteboard));
    });

    test('BlockType.values 长度为 17', () {
      expect(BlockType.values.length, 17);
    });
  });
}
