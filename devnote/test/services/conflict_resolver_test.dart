// ConflictResolver 单元测试
//
// 测试冲突解决器的向量时钟、CRDT 合并、策略化解决、差异计算功能。
// 验证 Git 风格三方合并与 Yjs CRDT 风格自动合并的正确性。

import 'package:flutter_test/flutter_test.dart';

import 'package:devnote/features/sync/conflict/conflict_resolver.dart';
import 'package:devnote/features/editor/models/block_model.dart';
import '../../helpers/test_helpers.dart';

void main() {
  late ConflictResolver resolver;

  setUp(() {
    resolver = ConflictResolver();
  });

  group('VectorClock', () {
    test('increment 递增指定设备的时钟', () {
      final vc = VectorClock();
      expect(vc.get('device-a'), 0);
      vc.increment('device-a');
      expect(vc.get('device-a'), 1);
      vc.increment('device-a');
      expect(vc.get('device-a'), 2);
    });

    test('merge 取各设备最大值', () {
      final vc1 = VectorClock({'a': 2, 'b': 1});
      final vc2 = VectorClock({'a': 1, 'b': 3, 'c': 1});
      vc1.merge(vc2);
      expect(vc1.get('a'), 2);
      expect(vc1.get('b'), 3);
      expect(vc1.get('c'), 1);
    });

    test('isBefore 判断因果关系（所有分量 <=）', () {
      final vc1 = VectorClock({'a': 1});
      final vc2 = VectorClock({'a': 2});
      expect(vc1.isBefore(vc2), isTrue);
      expect(vc2.isBefore(vc1), isFalse);
    });

    test('isConcurrent 判断并发关系', () {
      final vc1 = VectorClock({'a': 1});
      final vc2 = VectorClock({'b': 1});
      expect(vc1.isConcurrent(vc2), isTrue);
    });

    test('toJson / fromJson 序列化往返', () {
      final vc = VectorClock({'a': 1, 'b': 2});
      final json = vc.toJson();
      final restored = VectorClock.fromJson(json);
      expect(restored.get('a'), 1);
      expect(restored.get('b'), 2);
    });

    test('copy 创建独立副本', () {
      final vc = VectorClock({'a': 1});
      final copy = vc.copy();
      copy.increment('a');
      expect(vc.get('a'), 1);
      expect(copy.get('a'), 2);
    });
  });

  group('ConflictInfo', () {
    test('fromJson 正确反序列化', () {
      final json = {
        'block_id': 'block-1',
        'local_content': '本地',
        'remote_content': '远端',
        'local_operation_id': 'op-local',
        'remote_operation_id': 'op-remote',
        'conflict_type': 'ContentConflict',
      };
      final info = ConflictInfo.fromJson(json);
      expect(info.blockId, 'block-1');
      expect(info.localContent, '本地');
      expect(info.remoteContent, '远端');
      expect(info.conflictType, ConflictType.contentConflict);
    });

    test('fromJson 未知冲突类型默认为 contentConflict', () {
      final json = {
        'block_id': 'block-1',
        'local_content': '',
        'remote_content': '',
        'local_operation_id': '',
        'remote_operation_id': '',
        'conflict_type': 'UnknownType',
      };
      final info = ConflictInfo.fromJson(json);
      expect(info.conflictType, ConflictType.contentConflict);
    });
  });

  group('ConflictResolver - addConflicts & clear', () {
    test('addConflicts 添加冲突到列表', () {
      final conflict = ConflictInfo(
        blockId: 'block-1',
        localContent: '本地',
        remoteContent: '远端',
        localOperationId: 'op-1',
        remoteOperationId: 'op-2',
        conflictType: ConflictType.contentConflict,
      );
      resolver.addConflicts([conflict]);
      expect(resolver.conflicts.length, 1);
      expect(resolver.hasConflicts, isTrue);
    });

    test('clear 清空所有冲突和解决结果', () {
      resolver.addConflicts([
        ConflictInfo(
          blockId: 'block-1',
          localContent: '',
          remoteContent: '',
          localOperationId: '',
          remoteOperationId: '',
          conflictType: ConflictType.contentConflict,
        ),
      ]);
      resolver.resolveConflict('block-1', '解决内容');
      resolver.clear();
      expect(resolver.conflicts, isEmpty);
      expect(resolver.resolutions, isEmpty);
      expect(resolver.hasConflicts, isFalse);
    });
  });

  group('ConflictResolver - mergeWithCrdt', () {
    test('moveConflict 自动解决为远端内容', () {
      final conflict = ConflictInfo(
        blockId: 'block-1',
        localContent: '本地位置',
        remoteContent: '远端位置',
        localOperationId: 'op-1',
        remoteOperationId: 'op-2',
        conflictType: ConflictType.moveConflict,
      );
      final result = resolver.mergeWithCrdt([conflict]);
      expect(result.autoResolved.length, 1);
      expect(result.manualRequired, isEmpty);
      expect(resolver.resolutions['block-1'], '远端位置');
    });

    test('deleteModifyConflict 无法自动解决，需手动处理', () {
      final conflict = ConflictInfo(
        blockId: 'block-1',
        localContent: '本地修改',
        remoteContent: '',
        localOperationId: 'op-1',
        remoteOperationId: 'op-2',
        conflictType: ConflictType.deleteModifyConflict,
      );
      final result = resolver.mergeWithCrdt([conflict]);
      expect(result.autoResolved, isEmpty);
      expect(result.manualRequired.length, 1);
    });

    test('contentConflict 内容等价时自动解决', () {
      final conflict = ConflictInfo(
        blockId: 'block-1',
        localContent: '  相同内容  ',
        remoteContent: '相同内容',
        localOperationId: 'op-1',
        remoteOperationId: 'op-2',
        conflictType: ConflictType.contentConflict,
      );
      final result = resolver.mergeWithCrdt([conflict]);
      expect(result.autoResolved.length, 1);
      expect(resolver.resolutions['block-1'], '  相同内容  ');
    });

    test('contentConflict 内容不一致时需手动处理', () {
      final conflict = ConflictInfo(
        blockId: 'block-1',
        localContent: '本地内容',
        remoteContent: '远端内容',
        localOperationId: 'op-1',
        remoteOperationId: 'op-2',
        conflictType: ConflictType.contentConflict,
      );
      final result = resolver.mergeWithCrdt([conflict]);
      expect(result.manualRequired.length, 1);
      expect(result.hasManualConflicts, isTrue);
    });
  });

  group('ConflictResolver - resolveConflict & resolveAll', () {
    test('resolveConflict 手动指定解决内容', () {
      resolver.addConflicts([
        ConflictInfo(
          blockId: 'block-1',
          localContent: '本地',
          remoteContent: '远端',
          localOperationId: '',
          remoteOperationId: '',
          conflictType: ConflictType.contentConflict,
        ),
      ]);
      resolver.resolveConflict('block-1', '手动解决内容');
      expect(resolver.resolutions['block-1'], '手动解决内容');
      expect(resolver.allResolved, isTrue);
    });

    test('resolveAll preferLocal 策略采用本地内容', () {
      resolver.addConflicts([
        ConflictInfo(
          blockId: 'block-1',
          localContent: '本地内容',
          remoteContent: '远端内容',
          localOperationId: '',
          remoteOperationId: '',
          conflictType: ConflictType.deleteModifyConflict,
        ),
      ]);
      resolver.resolveAll(MergeStrategy.preferLocal);
      expect(resolver.resolutions['block-1'], '本地内容');
    });

    test('resolveAll preferRemote 策略采用远端内容', () {
      resolver.addConflicts([
        ConflictInfo(
          blockId: 'block-1',
          localContent: '本地内容',
          remoteContent: '远端内容',
          localOperationId: '',
          remoteOperationId: '',
          conflictType: ConflictType.deleteModifyConflict,
        ),
      ]);
      resolver.resolveAll(MergeStrategy.preferRemote);
      expect(resolver.resolutions['block-1'], '远端内容');
    });

    test('resolveAll manual 策略不自动解决', () {
      resolver.addConflicts([
        ConflictInfo(
          blockId: 'block-1',
          localContent: '本地',
          remoteContent: '远端',
          localOperationId: '',
          remoteOperationId: '',
          conflictType: ConflictType.deleteModifyConflict,
        ),
      ]);
      resolver.resolveAll(MergeStrategy.manual);
      expect(resolver.resolutions, isEmpty);
      expect(resolver.allResolved, isFalse);
    });
  });

  group('ConflictResolver - computeDiff', () {
    test('相同内容产生全 equal 行', () {
      final diff = resolver.computeDiff('line1\nline2', 'line1\nline2');
      expect(diff.every((d) => d.type == DiffType.equal), isTrue);
      expect(diff.length, 2);
    });

    test('新增行产生 added 类型', () {
      final diff = resolver.computeDiff('line1', 'line1\nline2');
      expect(diff.any((d) => d.type == DiffType.added), isTrue);
    });

    test('删除行产生 removed 类型', () {
      final diff = resolver.computeDiff('line1\nline2', 'line1');
      expect(diff.any((d) => d.type == DiffType.removed), isTrue);
    });
  });

  group('ConflictResolver - mergeWithVectorClocks', () {
    test('两端内容一致时无冲突', () {
      final block = createMockEditorBlock(id: 'block-1', content: '相同内容');
      final localClock = VectorClock({'a': 1});
      final remoteClock = VectorClock({'a': 1});
      final baseClock = VectorClock();

      final results = resolver.mergeWithVectorClocks(
        [block],
        [block],
        localClock,
        remoteClock,
        baseClock,
      );
      expect(results.length, 1);
      expect(results.first.action, BlockResolutionAction.noConflict);
    });

    test('local 因果在 remote 之前时采用 remote', () {
      final localBlock = createMockEditorBlock(id: 'block-1', content: '旧内容');
      final remoteBlock = createMockEditorBlock(id: 'block-1', content: '新内容');
      final localClock = VectorClock({'a': 1});
      final remoteClock = VectorClock({'a': 2});
      final baseClock = VectorClock();

      final results = resolver.mergeWithVectorClocks(
        [localBlock],
        [remoteBlock],
        localClock,
        remoteClock,
        baseClock,
      );
      expect(results.first.action, BlockResolutionAction.keepRemote);
      expect(results.first.block.content, '新内容');
    });

    test('remote 因果在 local 之前时采用 local', () {
      final localBlock = createMockEditorBlock(id: 'block-1', content: '新内容');
      final remoteBlock = createMockEditorBlock(id: 'block-1', content: '旧内容');
      final localClock = VectorClock({'a': 2});
      final remoteClock = VectorClock({'a': 1});
      final baseClock = VectorClock();

      final results = resolver.mergeWithVectorClocks(
        [localBlock],
        [remoteBlock],
        localClock,
        remoteClock,
        baseClock,
      );
      expect(results.first.action, BlockResolutionAction.keepLocal);
      expect(results.first.block.content, '新内容');
    });

    test('块仅存在于本地时保留本地版本', () {
      final localBlock = createMockEditorBlock(id: 'block-1', content: '本地独有');
      final localClock = VectorClock();
      final remoteClock = VectorClock();
      final baseClock = VectorClock();

      final results = resolver.mergeWithVectorClocks(
        [localBlock],
        [],
        localClock,
        remoteClock,
        baseClock,
      );
      expect(results.first.action, BlockResolutionAction.keepLocal);
    });

    test('块仅存在于远端时保留远端版本', () {
      final remoteBlock = createMockEditorBlock(id: 'block-1', content: '远端独有');
      final localClock = VectorClock();
      final remoteClock = VectorClock();
      final baseClock = VectorClock();

      final results = resolver.mergeWithVectorClocks(
        [],
        [remoteBlock],
        localClock,
        remoteClock,
        baseClock,
      );
      expect(results.first.action, BlockResolutionAction.keepRemote);
    });

    test('并发编辑文本块时进行字符级合并', () {
      final localBlock = createMockEditorBlock(
        id: 'block-1',
        content: 'Hello World',
        blockType: BlockType.paragraph,
      );
      final remoteBlock = createMockEditorBlock(
        id: 'block-1',
        content: 'Hello Dart',
        blockType: BlockType.paragraph,
      );
      // 并发：a 和 b 各自独立递增
      final localClock = VectorClock({'a': 1});
      final remoteClock = VectorClock({'b': 1});
      final baseClock = VectorClock();

      final results = resolver.mergeWithVectorClocks(
        [localBlock],
        [remoteBlock],
        localClock,
        remoteClock,
        baseClock,
      );
      expect(results.first.action, BlockResolutionAction.charMerged);
      // 合并后应包含双方独有的部分
      expect(results.first.block.content, contains('World'));
      expect(results.first.block.content, contains('Dart'));
    });

    test('并发编辑非文本块时基于时间戳 last-write-wins', () {
      final now = DateTime.now();
      final localBlock = createMockEditorBlock(
        id: 'block-1',
        content: 'local code',
        blockType: BlockType.codeBlock,
        updatedAt: now.add(const Duration(minutes: 1)),
      );
      final remoteBlock = createMockEditorBlock(
        id: 'block-1',
        content: 'remote code',
        blockType: BlockType.codeBlock,
        updatedAt: now,
      );
      final localClock = VectorClock({'a': 1});
      final remoteClock = VectorClock({'b': 1});
      final baseClock = VectorClock();

      final results = resolver.mergeWithVectorClocks(
        [localBlock],
        [remoteBlock],
        localClock,
        remoteClock,
        baseClock,
      );
      expect(results.first.action, BlockResolutionAction.lastWriteWins);
      // local 的时间戳更晚，应胜出
      expect(results.first.block.content, 'local code');
    });
  });
}
