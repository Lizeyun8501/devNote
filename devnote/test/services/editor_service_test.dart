// EditorService 单元测试
//
// 测试 EditorService 的 block 缓存管理与 Markdown 解析功能。
// 使用 mocktail 模拟 BlockRepository，避免对 SQLite/FFI 的依赖。
// 通过 createMockEditorBlock 辅助函数构造测试数据。

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:devnote/core/persistence/block_repository.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import 'package:devnote/features/editor/services/editor_service.dart';
import '../helpers/test_helpers.dart';

// Mock BlockRepository —— 避免对 SQLite/FFI 的依赖
class MockBlockRepository extends Mock implements BlockRepository {}

void main() {
  late MockBlockRepository mockBlockRepository;
  late EditorService editorService;

  setUpAll(() {
    // 注册 fallback 值，用于 mocktail 匹配命名参数中的 BlockType
    registerFallbackValue(BlockType.paragraph);
  });

  setUp(() {
    mockBlockRepository = MockBlockRepository();
    editorService = EditorService(blockRepository: mockBlockRepository);
  });

  group('EditorService - loadBlocks', () {
    test('从 repository 加载 block 到缓存', () async {
      // 准备 mock 数据：两个 block
      final blocks = [
        createMockEditorBlock(id: 'block-1', position: 0),
        createMockEditorBlock(id: 'block-2', position: 1),
      ];
      when(() => mockBlockRepository.loadBlocks('note-1'))
          .thenAnswer((_) async => blocks);

      await editorService.loadBlocks('note-1');

      // 通过 listBlocks 验证缓存已加载（缓存非空时不再调用 repository）
      final result = await editorService.listBlocks('note-1');
      expect(result.length, 2);
      expect(result[0].id, 'block-1');
      expect(result[1].id, 'block-2');
      // loadBlocks 只应被调用一次（手动调用），listBlocks 不应再次触发
      verify(() => mockBlockRepository.loadBlocks('note-1')).called(1);
    });
  });

  group('EditorService - createBlock', () {
    test('创建 block 后缓存更新，position 调整正确', () async {
      // 预设缓存：先加载两个 block（position 0 和 1）
      final initialBlocks = [
        createMockEditorBlock(id: 'block-1', position: 0, content: 'A'),
        createMockEditorBlock(id: 'block-2', position: 1, content: 'B'),
      ];
      when(() => mockBlockRepository.loadBlocks('note-1'))
          .thenAnswer((_) async => initialBlocks);
      await editorService.loadBlocks('note-1');

      // mock createBlock：返回与入参一致的新 block
      when(() => mockBlockRepository.createBlock(
            noteId: any(named: 'noteId'),
            blockType: any(named: 'blockType'),
            content: any(named: 'content'),
            position: any(named: 'position'),
            language: any(named: 'language'),
          )).thenAnswer((invocation) async => createMockEditorBlock(
                id: 'block-new',
                noteId: invocation.namedArguments[#noteId] as String,
                blockType: invocation.namedArguments[#blockType] as BlockType,
                content: invocation.namedArguments[#content] as String,
                position: invocation.namedArguments[#position] as int,
              ));

      // 在 position=1 处插入新 block
      final created = await editorService.createBlock(
        noteId: 'note-1',
        blockType: BlockType.paragraph,
        content: 'C',
        position: 1,
      );

      expect(created.id, 'block-new');
      expect(created.position, 1);

      // 验证缓存：原 position >= 1 的 block 后移一格
      final cached = await editorService.listBlocks('note-1');
      expect(cached.length, 3);
      // 按 position 排序后：block-1(0), block-new(1), block-2(2)
      expect(cached[0].id, 'block-1');
      expect(cached[0].position, 0);
      expect(cached[1].id, 'block-new');
      expect(cached[1].position, 1);
      expect(cached[2].id, 'block-2');
      expect(cached[2].position, 2);
    });
  });

  group('EditorService - createBlockFromString', () {
    test('字符串类型名正确映射到 BlockType', () async {
      // mock createBlock：返回与入参一致的新 block，便于通过缓存验证类型
      when(() => mockBlockRepository.createBlock(
            noteId: any(named: 'noteId'),
            blockType: any(named: 'blockType'),
            content: any(named: 'content'),
            position: any(named: 'position'),
            language: any(named: 'language'),
          )).thenAnswer((invocation) async => createMockEditorBlock(
                id: 'block-1',
                blockType: invocation.namedArguments[#blockType] as BlockType,
                content: invocation.namedArguments[#content] as String,
                position: invocation.namedArguments[#position] as int,
              ));

      // 使用 heading1 类型名
      await editorService.createBlockFromString(
        noteId: 'note-1',
        blockTypeName: 'heading1',
        content: '标题',
        position: 0,
      );

      // 通过缓存验证 createBlock 被调用时 blockType 为 heading1
      final cached = await editorService.listBlocks('note-1');
      expect(cached.length, 1);
      expect(cached[0].blockType, BlockType.heading1);
      expect(cached[0].content, '标题');
    });

    test('未知类型回退 paragraph', () async {
      when(() => mockBlockRepository.createBlock(
            noteId: any(named: 'noteId'),
            blockType: any(named: 'blockType'),
            content: any(named: 'content'),
            position: any(named: 'position'),
            language: any(named: 'language'),
          )).thenAnswer((invocation) async => createMockEditorBlock(
                id: 'block-1',
                blockType: invocation.namedArguments[#blockType] as BlockType,
                content: invocation.namedArguments[#content] as String,
                position: invocation.namedArguments[#position] as int,
              ));

      // 使用未知类型名
      await editorService.createBlockFromString(
        noteId: 'note-1',
        blockTypeName: 'unknownType',
        content: '内容',
        position: 0,
      );

      // 验证回退为 paragraph
      final cached = await editorService.listBlocks('note-1');
      expect(cached.length, 1);
      expect(cached[0].blockType, BlockType.paragraph);
    });
  });

  group('EditorService - getBlock', () {
    test('缓存优先返回缓存中的 block', () async {
      // 预设缓存
      final blocks = [
        createMockEditorBlock(id: 'block-1', position: 0),
      ];
      when(() => mockBlockRepository.loadBlocks('note-1'))
          .thenAnswer((_) async => blocks);
      await editorService.loadBlocks('note-1');

      final result = await editorService.getBlock('block-1');

      expect(result, isNotNull);
      expect(result!.id, 'block-1');
      // 缓存命中，不应调用 repository.getBlock
      verifyNever(() => mockBlockRepository.getBlock('block-1'));
    });

    test('缓存未命中时查 repository', () async {
      final block = createMockEditorBlock(id: 'block-x', position: 0);
      when(() => mockBlockRepository.getBlock('block-x'))
          .thenAnswer((_) async => block);

      // 缓存为空，应回退到 repository
      final result = await editorService.getBlock('block-x');

      expect(result, isNotNull);
      expect(result!.id, 'block-x');
      verify(() => mockBlockRepository.getBlock('block-x')).called(1);
    });
  });

  group('EditorService - updateBlock', () {
    test('更新内容后缓存同步更新', () async {
      // 预设缓存
      final blocks = [
        createMockEditorBlock(id: 'block-1', content: '原内容', position: 0),
      ];
      when(() => mockBlockRepository.loadBlocks('note-1'))
          .thenAnswer((_) async => blocks);
      await editorService.loadBlocks('note-1');

      when(() => mockBlockRepository.updateBlock(
            blockId: any(named: 'blockId'),
            content: any(named: 'content'),
          )).thenAnswer((_) async {});

      await editorService.updateBlock(blockId: 'block-1', content: '新内容');

      // 验证缓存已同步更新
      final cached = await editorService.getBlock('block-1');
      expect(cached, isNotNull);
      expect(cached!.content, '新内容');
    });
  });

  group('EditorService - updateBlockType', () {
    test('更新类型后缓存同步更新', () async {
      // 预设缓存：原类型为 paragraph
      final blocks = [
        createMockEditorBlock(
            id: 'block-1', blockType: BlockType.paragraph, position: 0),
      ];
      when(() => mockBlockRepository.loadBlocks('note-1'))
          .thenAnswer((_) async => blocks);
      await editorService.loadBlocks('note-1');

      when(() => mockBlockRepository.updateBlockType(
            blockId: any(named: 'blockId'),
            newType: any(named: 'newType'),
          )).thenAnswer((_) async {});

      await editorService.updateBlockType(
          blockId: 'block-1', newType: BlockType.heading1);

      // 验证缓存已同步更新为 heading1
      final cached = await editorService.getBlock('block-1');
      expect(cached, isNotNull);
      expect(cached!.blockType, BlockType.heading1);
    });
  });

  group('EditorService - deleteBlock', () {
    test('删除后缓存移除，position 重排', () async {
      // 预设缓存：三个 block
      final blocks = [
        createMockEditorBlock(id: 'block-1', position: 0),
        createMockEditorBlock(id: 'block-2', position: 1),
        createMockEditorBlock(id: 'block-3', position: 2),
      ];
      when(() => mockBlockRepository.loadBlocks('note-1'))
          .thenAnswer((_) async => blocks);
      await editorService.loadBlocks('note-1');

      when(() => mockBlockRepository.deleteBlock('block-2'))
          .thenAnswer((_) async {});

      await editorService.deleteBlock('block-2');

      // 验证缓存：block-2 已移除，剩余 block 的 position 重排为 0, 1
      final cached = await editorService.listBlocks('note-1');
      expect(cached.length, 2);
      expect(cached[0].id, 'block-1');
      expect(cached[0].position, 0);
      expect(cached[1].id, 'block-3');
      expect(cached[1].position, 1);
    });
  });

  group('EditorService - moveBlock', () {
    test('移动后缓存顺序更新，position 重排', () async {
      // 预设缓存：三个 block
      final blocks = [
        createMockEditorBlock(id: 'block-1', position: 0),
        createMockEditorBlock(id: 'block-2', position: 1),
        createMockEditorBlock(id: 'block-3', position: 2),
      ];
      when(() => mockBlockRepository.loadBlocks('note-1'))
          .thenAnswer((_) async => blocks);
      await editorService.loadBlocks('note-1');

      when(() => mockBlockRepository.moveBlock(
            blockId: any(named: 'blockId'),
            newPosition: any(named: 'newPosition'),
          )).thenAnswer((_) async {});

      // 将 block-3 (pos=2) 移动到 pos=0
      await editorService.moveBlock(blockId: 'block-3', newPosition: 0);

      // 验证缓存顺序：block-3, block-1, block-2，position 重排为 0, 1, 2
      final cached = await editorService.listBlocks('note-1');
      expect(cached.length, 3);
      expect(cached[0].id, 'block-3');
      expect(cached[0].position, 0);
      expect(cached[1].id, 'block-1');
      expect(cached[1].position, 1);
      expect(cached[2].id, 'block-2');
      expect(cached[2].position, 2);
    });
  });

  group('EditorService - listBlocks', () {
    test('缓存优先返回缓存数据', () async {
      // 预设缓存
      final blocks = [
        createMockEditorBlock(id: 'block-1', position: 0),
      ];
      when(() => mockBlockRepository.loadBlocks('note-1'))
          .thenAnswer((_) async => blocks);
      await editorService.loadBlocks('note-1');

      final result = await editorService.listBlocks('note-1');

      expect(result.length, 1);
      expect(result[0].id, 'block-1');
      // loadBlocks 仅在手动调用时触发一次，listBlocks 不应再次调用
      verify(() => mockBlockRepository.loadBlocks('note-1')).called(1);
    });

    test('缓存为空时从 repository 加载', () async {
      final blocks = [
        createMockEditorBlock(id: 'block-1', position: 0),
        createMockEditorBlock(id: 'block-2', position: 1),
      ];
      when(() => mockBlockRepository.loadBlocks('note-1'))
          .thenAnswer((_) async => blocks);

      // 未预先调用 loadBlocks，listBlocks 应触发懒加载
      final result = await editorService.listBlocks('note-1');

      expect(result.length, 2);
      expect(result[0].id, 'block-1');
      expect(result[1].id, 'block-2');
      verify(() => mockBlockRepository.loadBlocks('note-1')).called(1);
    });
  });

  group('EditorService - parseMarkdown', () {
    setUp(() {
      // parseMarkdown 会调用 replaceBlocks 批量写入，需要 mock
      when(() => mockBlockRepository.replaceBlocks(any(), any()))
          .thenAnswer((_) async {});
    });

    test('解析 heading', () async {
      const content = '# 标题';

      final blocks = await editorService.parseMarkdown(
          content: content, noteId: 'note-1');

      expect(blocks.length, 1);
      expect(blocks[0].blockType, BlockType.heading1);
      expect(blocks[0].content, '标题');
      expect(blocks[0].position, 0);
    });

    test('解析 code block', () async {
      const content = '```dart\nprint("hello");\n```';

      final blocks = await editorService.parseMarkdown(
          content: content, noteId: 'note-1');

      expect(blocks.length, 1);
      expect(blocks[0].blockType, BlockType.codeBlock);
      expect(blocks[0].content, 'print("hello");');
      expect(blocks[0].language, 'dart');
    });

    test('解析 paragraph', () async {
      const content = '这是段落内容';

      final blocks = await editorService.parseMarkdown(
          content: content, noteId: 'note-1');

      expect(blocks.length, 1);
      expect(blocks[0].blockType, BlockType.paragraph);
      expect(blocks[0].content, '这是段落内容');
    });

    test('解析 quote', () async {
      const content = '> 引用内容';

      final blocks = await editorService.parseMarkdown(
          content: content, noteId: 'note-1');

      expect(blocks.length, 1);
      expect(blocks[0].blockType, BlockType.quote);
      expect(blocks[0].content, '引用内容');
    });

    test('解析 list', () async {
      const content = '- 列表项 1\n- 列表项 2';

      final blocks = await editorService.parseMarkdown(
          content: content, noteId: 'note-1');

      expect(blocks.length, 1);
      expect(blocks[0].blockType, BlockType.list);
      expect(blocks[0].content, '列表项 1\n列表项 2');
    });

    test('解析后缓存更新并调用 replaceBlocks', () async {
      const content = '# 标题\n\n段落';

      final blocks = await editorService.parseMarkdown(
          content: content, noteId: 'note-1');

      // 验证 replaceBlocks 被调用
      verify(() => mockBlockRepository.replaceBlocks('note-1', any())).called(1);

      // 验证缓存已更新：listBlocks 不应再调用 loadBlocks
      final cached = await editorService.listBlocks('note-1');
      expect(cached.length, blocks.length);
      verifyNever(() => mockBlockRepository.loadBlocks(any()));
    });
  });
}
