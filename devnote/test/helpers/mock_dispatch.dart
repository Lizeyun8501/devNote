// Mock Dispatch 实现 —— 用于测试依赖 Dispatch 的服务（如 SearchService）
//
// 通过继承 Dispatch 并重写方法，返回可配置的预设值，避免对 FFI/Rust 的依赖。

import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/persistence/models/note_model.dart';
import 'package:devnote/core/persistence/models/folder_model.dart';
import 'package:devnote/core/persistence/models/tag_model.dart';
import 'package:devnote/core/persistence/models/block_model.dart';

/// Mock Dispatch —— 可配置返回值的 Dispatch 子类
///
/// 使用方式：
/// ```dart
/// final mockDispatch = MockDispatch();
/// mockDispatch.searchNotesResult = [
///   {'note_id': 'note-1', 'title': '测试', 'snippet': '...', 'score': 1.0, 'highlights': []}
/// ];
/// ```
class MockDispatch extends Dispatch {
  // 可配置的返回值
  List<Map<String, dynamic>> searchNotesResult = [];
  List<Map<String, dynamic>> listNotesResult = [];
  List<Map<String, dynamic>> listFoldersResult = [];
  List<Map<String, dynamic>> listTagsResult = [];
  List<Map<String, dynamic>> getBlocksResult = [];
  NoteModel? getNoteResult;
  FolderModel? createFolderResult;
  TagModel? createTagResult;
  BlockModel? insertBlockResult;

  // 异常配置（非 null 时对应方法抛出异常）
  Exception? searchNotesError;
  Exception? listNotesError;
  Exception? createNoteError;

  // 调用记录（用于验证调用次数与参数）
  final List<String> searchCalls = [];
  final List<String> createNoteCalls = [];

  @override
  Future<List<Map<String, dynamic>>> searchNotes({
    required String query,
    int? limit,
    int? offset,
  }) async {
    searchCalls.add(query);
    if (searchNotesError != null) throw searchNotesError!;
    return List<Map<String, dynamic>>.from(searchNotesResult);
  }

  @override
  Future<NoteModel> createNote({
    required String title,
    required String content,
    required String folderId,
  }) async {
    createNoteCalls.add(title);
    if (createNoteError != null) throw createNoteError!;
    return NoteModel(
      id: 'new-note-id',
      title: title,
      content: content,
      folderId: folderId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<List<NoteModel>> listNotes(String folderId) async {
    if (listNotesError != null) throw listNotesError!;
    return listNotesResult.map((m) => NoteModel.fromJson(m)).toList();
  }

  @override
  Future<NoteModel?> getNote(String id) async => getNoteResult;

  @override
  Future<FolderModel> createFolder({required String name, String? parentId}) async {
    return createFolderResult ??
        FolderModel(
          id: 'new-folder-id',
          name: name,
          parentId: parentId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
  }

  @override
  Future<List<FolderModel>> listFolders({String? parentId}) async {
    return listFoldersResult.map((m) => FolderModel.fromJson(m)).toList();
  }

  @override
  Future<TagModel> createTag(String name) async {
    return createTagResult ??
        TagModel(id: 'new-tag-id', name: name, createdAt: DateTime.now());
  }

  @override
  Future<List<TagModel>> listTags() async {
    return listTagsResult.map((m) => TagModel.fromJson(m)).toList();
  }

  @override
  Future<void> deleteNote(String id) async {}

  @override
  Future<void> deleteFolder(String id) async {}

  @override
  Future<void> deleteTag(String id) async {}
}
