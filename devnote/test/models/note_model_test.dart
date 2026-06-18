// NoteModel 单元测试
//
// 测试 Freezed 生成的 NoteModel 的构造、序列化、相等性、copyWith 功能。
// 验证 JSON 字段映射（snake_case）与 DateTime 处理。

import 'package:flutter_test/flutter_test.dart';
import 'package:devnote/core/persistence/models/note_model.dart';

void main() {
  final testTime = DateTime(2024, 1, 15, 10, 30, 0);

  group('NoteModel - 构造', () {
    test('使用必填字段构造 NoteModel', () {
      final note = NoteModel(
        id: 'note-1',
        title: '测试笔记',
        content: '内容',
        folderId: 'folder-1',
        createdAt: testTime,
        updatedAt: testTime,
      );
      expect(note.id, 'note-1');
      expect(note.title, '测试笔记');
      expect(note.content, '内容');
      expect(note.folderId, 'folder-1');
      expect(note.createdAt, testTime);
      expect(note.updatedAt, testTime);
    });
  });

  group('NoteModel - JSON 序列化', () {
    test('toJson 正确映射字段名为 snake_case', () {
      final note = NoteModel(
        id: 'note-1',
        title: '测试',
        content: '内容',
        folderId: 'folder-1',
        createdAt: testTime,
        updatedAt: testTime,
      );
      final json = note.toJson();
      expect(json['id'], 'note-1');
      expect(json['title'], '测试');
      expect(json['content'], '内容');
      // 验证 snake_case 映射
      expect(json['folder_id'], 'folder-1');
      expect(json['created_at'], testTime);
      expect(json['updated_at'], testTime);
    });

    test('fromJson 正确从 snake_case JSON 反序列化', () {
      final json = {
        'id': 'note-1',
        'title': '测试',
        'content': '内容',
        'folder_id': 'folder-1',
        'created_at': testTime.toIso8601String(),
        'updated_at': testTime.toIso8601String(),
      };
      final note = NoteModel.fromJson(json);
      expect(note.id, 'note-1');
      expect(note.title, '测试');
      expect(note.content, '内容');
      expect(note.folderId, 'folder-1');
    });

    test('toJson → fromJson 往返保持数据一致', () {
      final original = NoteModel(
        id: 'note-1',
        title: '往返测试',
        content: '往返内容',
        folderId: 'folder-1',
        createdAt: testTime,
        updatedAt: testTime,
      );
      final json = original.toJson();
      final restored = NoteModel.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.content, original.content);
      expect(restored.folderId, original.folderId);
    });
  });

  group('NoteModel - 相等性', () {
    test('相同字段的两个 NoteModel 相等', () {
      final note1 = NoteModel(
        id: 'note-1',
        title: '测试',
        content: '内容',
        folderId: 'folder-1',
        createdAt: testTime,
        updatedAt: testTime,
      );
      final note2 = NoteModel(
        id: 'note-1',
        title: '测试',
        content: '内容',
        folderId: 'folder-1',
        createdAt: testTime,
        updatedAt: testTime,
      );
      expect(note1, equals(note2));
      expect(note1.hashCode, note2.hashCode);
    });

    test('不同 ID 的两个 NoteModel 不相等', () {
      final note1 = NoteModel(
        id: 'note-1',
        title: '测试',
        content: '',
        folderId: '',
        createdAt: testTime,
        updatedAt: testTime,
      );
      final note2 = NoteModel(
        id: 'note-2',
        title: '测试',
        content: '',
        folderId: '',
        createdAt: testTime,
        updatedAt: testTime,
      );
      expect(note1, isNot(equals(note2)));
    });
  });

  group('NoteModel - copyWith', () {
    test('copyWith 修改部分字段保留其他字段', () {
      final original = NoteModel(
        id: 'note-1',
        title: '原标题',
        content: '原内容',
        folderId: 'folder-1',
        createdAt: testTime,
        updatedAt: testTime,
      );
      final copied = original.copyWith(title: '新标题', content: '新内容');
      expect(copied.id, 'note-1');
      expect(copied.title, '新标题');
      expect(copied.content, '新内容');
      expect(copied.folderId, 'folder-1');
      expect(copied.createdAt, testTime);
    });

    test('copyWith 不传参时返回字段相同的副本', () {
      final original = NoteModel(
        id: 'note-1',
        title: '标题',
        content: '内容',
        folderId: 'folder-1',
        createdAt: testTime,
        updatedAt: testTime,
      );
      final copied = original.copyWith();
      expect(copied, equals(original));
    });
  });
}
