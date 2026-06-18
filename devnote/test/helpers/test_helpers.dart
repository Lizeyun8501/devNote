// 测试辅助工具 —— Mock 数据工厂与 Mock 仓库实现
//
// 提供测试用的数据工厂方法与轻量级 Mock 仓库，避免对 SQLite/FFI 的依赖。
// 所有 Mock 均返回预置数据，确保测试可独立运行。

import 'dart:typed_data';

import 'package:devnote/core/persistence/models/note_model.dart';
import 'package:devnote/core/persistence/models/block_model.dart';
import 'package:devnote/core/persistence/models/folder_model.dart';
import 'package:devnote/core/persistence/models/tag_model.dart';
import 'package:devnote/core/persistence/note_repository.dart';
import 'package:devnote/core/persistence/folder_repository.dart';
import 'package:devnote/core/persistence/tag_repository.dart';
import 'package:devnote/features/editor/models/block_model.dart' as editor;
import 'package:devnote/features/search/search_service.dart';

// ============================================================
// Mock 数据工厂方法
// ============================================================

/// 创建 Mock 笔记数据
///
/// [id] 笔记 ID，默认 'note-1'
/// [title] 标题，默认 '测试笔记'
/// [content] 内容，默认空字符串
/// [folderId] 所属文件夹 ID，默认 'folder-1'
NoteModel createMockNote({
  String id = 'note-1',
  String title = '测试笔记',
  String content = '这是测试内容',
  String folderId = 'folder-1',
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final now = DateTime(2024, 1, 1, 10, 0);
  return NoteModel(
    id: id,
    title: title,
    content: content,
    folderId: folderId,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
  );
}

/// 创建一批 Mock 笔记数据
List<NoteModel> createMockNotes(int count, {String folderId = 'folder-1'}) {
  return List.generate(count, (i) {
    final ts = DateTime(2024, 1, 1).add(Duration(days: i));
    return createMockNote(
      id: 'note-$i',
      title: '笔记 $i',
      content: '内容 $i',
      folderId: folderId,
      createdAt: ts,
      updatedAt: ts.add(const Duration(hours: 1)),
    );
  });
}

/// 创建 Mock 文件夹数据
FolderModel createMockFolder({
  String id = 'folder-1',
  String name = '测试文件夹',
  String? parentId,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final now = DateTime(2024, 1, 1);
  return FolderModel(
    id: id,
    name: name,
    parentId: parentId,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
  );
}

/// 创建 Mock 标签数据
TagModel createMockTag({
  String id = 'tag-1',
  String name = '测试标签',
  DateTime? createdAt,
}) {
  return TagModel(
    id: id,
    name: name,
    createdAt: createdAt ?? DateTime(2024, 1, 1),
  );
}

/// 创建 Mock 持久化层 BlockModel（Freezed 版本，用于数据库序列化）
BlockModel createMockPersistenceBlock({
  String id = 'block-1',
  String noteId = 'note-1',
  String blockType = 'paragraph',
  String content = '段落内容',
  int position = 0,
}) {
  return BlockModel(
    id: id,
    noteId: noteId,
    blockType: blockType,
    content: content,
    position: position,
  );
}

/// 创建 Mock 编辑器 BlockModel（Equatable 版本，用于编辑器 UI）
editor.BlockModel createMockEditorBlock({
  String id = 'block-1',
  String noteId = 'note-1',
  editor.BlockType blockType = editor.BlockType.paragraph,
  String content = '段落内容',
  int position = 0,
  String? language,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final now = DateTime(2024, 1, 1, 10, 0);
  return editor.BlockModel(
    id: id,
    noteId: noteId,
    blockType: blockType,
    content: content,
    position: position,
    language: language,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
  );
}

/// 创建 Mock 搜索结果
SearchResultModel createMockSearchResult({
  String noteId = 'note-1',
  String title = '测试笔记',
  String snippet = '匹配的片段',
  double score = 1.0,
}) {
  return SearchResultModel(
    noteId: noteId,
    title: title,
    snippet: snippet,
    highlights: [
      HighlightModel(start: 0, end: 2, text: '匹配'),
    ],
    score: score,
  );
}

/// 创建随机字节数据（用于加密测试）
Uint8List createMockBytes(int length, {int seed = 42}) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = (seed + i) % 256;
  }
  return bytes;
}

// ============================================================
// Mock 仓库实现 —— 返回预置数据，无 SQLite/FFI 依赖
// ============================================================

/// Mock 笔记仓库
///
/// 通过构造函数注入预置笔记列表，所有方法基于该列表返回数据。
/// 支持配置抛出异常以测试错误分支。
class MockNoteRepository implements NoteRepository {
  final List<NoteModel> _notes;
  final Exception? _error;

  MockNoteRepository(this._notes, {Exception? error}) : _error = error;

  /// 创建一个抛出异常的 Mock 仓库，用于测试错误分支
  factory MockNoteRepository.withError(Exception error) {
    return MockNoteRepository([], error: error);
  }

  @override
  Future<NoteModel> createNote(NoteModel note) async {
    if (_error != null) throw _error!;
    _notes.add(note);
    return note;
  }

  @override
  Future<NoteModel?> getNote(String id) async {
    if (_error != null) throw _error!;
    return _notes.where((n) => n.id == id).firstOrNull;
  }

  @override
  Future<NoteModel> updateNote(NoteModel note) async {
    if (_error != null) throw _error!;
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index != -1) {
      _notes[index] = note;
    }
    return note;
  }

  @override
  Future<void> deleteNote(String id) async {
    if (_error != null) throw _error!;
    _notes.removeWhere((n) => n.id == id);
  }

  @override
  Future<List<NoteModel>> listNotes(String folderId) async {
    if (_error != null) throw _error!;
    return _notes.where((n) => n.folderId == folderId).toList();
  }

  @override
  Future<List<NoteModel>> listNotesPaged(String folderId,
      {int limit = 20, int offset = 0}) async {
    if (_error != null) throw _error!;
    return _notes
        .where((n) => n.folderId == folderId)
        .skip(offset)
        .take(limit)
        .toList();
  }
}

/// Mock 文件夹仓库
class MockFolderRepository implements FolderRepository {
  final List<FolderModel> _folders;
  final Exception? _error;

  MockFolderRepository(this._folders, {Exception? error}) : _error = error;

  factory MockFolderRepository.withError(Exception error) {
    return MockFolderRepository([], error: error);
  }

  @override
  Future<FolderModel> createFolder(FolderModel folder) async {
    if (_error != null) throw _error!;
    _folders.add(folder);
    return folder;
  }

  @override
  Future<List<FolderModel>> listFolders(String? parentId) async {
    if (_error != null) throw _error!;
    return _folders.where((f) => f.parentId == parentId).toList();
  }

  @override
  Future<void> deleteFolder(String id) async {
    if (_error != null) throw _error!;
    _folders.removeWhere((f) => f.id == id);
  }

  @override
  Future<FolderModel> updateFolder(FolderModel folder) async {
    if (_error != null) throw _error!;
    final index = _folders.indexWhere((f) => f.id == folder.id);
    if (index != -1) {
      _folders[index] = folder;
    }
    return folder;
  }
}

/// Mock 标签仓库
class MockTagRepository implements TagRepository {
  final List<TagModel> _tags = [];
  final Map<String, List<String>> _noteTags = {};
  final Exception? _error;

  MockTagRepository({Exception? error}) : _error = error;

  factory MockTagRepository.withError(Exception error) {
    return MockTagRepository(error: error);
  }

  @override
  Future<TagModel> createTag(TagModel tag) async {
    if (_error != null) throw _error!;
    _tags.add(tag);
    return tag;
  }

  @override
  Future<void> addTagToNote(String noteId, String tagId) async {
    if (_error != null) throw _error!;
    _noteTags.putIfAbsent(noteId, () => []).add(tagId);
  }

  @override
  Future<void> removeTagFromNote(String noteId, String tagId) async {
    if (_error != null) throw _error!;
    _noteTags[noteId]?.remove(tagId);
  }

  @override
  Future<List<TagModel>> getTagsForNote(String noteId) async {
    if (_error != null) throw _error!;
    final tagIds = _noteTags[noteId] ?? [];
    return _tags.where((t) => tagIds.contains(t.id)).toList();
  }

  @override
  Future<List<TagModel>> getAllTags() async {
    if (_error != null) throw _error!;
    return List<TagModel>.from(_tags);
  }
}
