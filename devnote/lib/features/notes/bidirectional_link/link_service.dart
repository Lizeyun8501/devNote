// 双向链接服务 —— 解析 [[笔记名]] 格式的维基链接并查找反向引用
// 借鉴 Obsidian 的双向链接设计
// 来源: https://obsidian.md
// 借鉴内容: [[笔记名]] 维基链接语法、反向链接(backlinks)查找、
//         链接解析与目标解析(resolution)、链接创建与移除

import 'package:devnote/core/persistence/note_repository.dart';
import 'package:devnote/core/persistence/folder_repository.dart';
import 'package:devnote/core/persistence/models/note_model.dart';

class LinkInfo {
  final String noteName;
  final String? noteId;

  const LinkInfo({required this.noteName, this.noteId});
}

class BidirectionalLinkService {
  final NoteRepository _noteRepository;
  final FolderRepository _folderRepository;

  BidirectionalLinkService(this._noteRepository, this._folderRepository);

  /// 匹配 [[笔记名]] 格式的维基链接
  /// 借鉴 Obsidian 的 Wikilink 语法
  static final linkPattern = RegExp(r'\[\[(.+?)\]\]');

  /// 解析内容中的所有 [[链接]]
  List<LinkInfo> parseLinks(String content) {
    final matches = linkPattern.allMatches(content);
    return matches.map((match) {
      final noteName = match.group(1)?.trim() ?? '';
      return LinkInfo(noteName: noteName);
    }).toList();
  }

  /// 解析链接并解析目标笔记 ID
  Future<List<LinkInfo>> parseLinksResolved(String content) async {
    final links = parseLinks(content);
    final resolved = <LinkInfo>[];
    for (final link in links) {
      final noteId = await _findNoteByName(link.noteName);
      resolved.add(LinkInfo(noteName: link.noteName, noteId: noteId));
    }
    return resolved;
  }

  /// 查找指向指定笔记的所有反向链接(backlinks)
  /// 借鉴 Obsidian 的反向链接面板设计
  /// 来源: https://help.obsidian.md/Plugins/Backlinks
  Future<List<NoteModel>> findBacklinks(String noteId) async {
    final note = await _noteRepository.getNote(noteId);
    if (note == null) return [];

    final allFolders = await _getAllNoteFolders();
    final backlinks = <NoteModel>[];

    for (final folderId in allFolders) {
      final notes = await _noteRepository.listNotes(folderId);
      for (final n in notes) {
        if (n.id == noteId) continue;
        final links = parseLinks(n.content);
        if (links.any((link) => link.noteName == note.title)) {
          backlinks.add(n);
        }
      }
    }

    return backlinks;
  }

  /// 创建 [[笔记名]] 格式的链接
  String createLink(String noteName) {
    return '[[$noteName]]';
  }

  /// 从内容中移除链接语法，保留纯文本
  String removeLink(String content, String noteName) {
    return content.replaceAll('[[$noteName]]', noteName);
  }

  /// 通过笔记名查找笔记 ID
  Future<String?> _findNoteByName(String name) async {
    final allFolders = await _getAllNoteFolders();
    for (final folderId in allFolders) {
      final notes = await _noteRepository.listNotes(folderId);
      for (final note in notes) {
        if (note.title == name) return note.id;
      }
    }
    return null;
  }

  /// 获取所有文件夹 ID —— 递归获取包括子文件夹在内的所有文件夹
  /// 修复：原代码只调用 listFolders(null) 获取根文件夹，遗漏了所有子文件夹，
  /// 导致反向链接查找不完整，子文件夹中的笔记永远不会被搜索到
  Future<List<String>> _getAllNoteFolders() async {
    final allIds = <String>[];
    await _collectFolderIdsRecursive(null, allIds);
    return allIds;
  }

  /// 递归收集所有文件夹 ID
  Future<void> _collectFolderIdsRecursive(String? parentId, List<String> ids) async {
    final folders = await _folderRepository.listFolders(parentId);
    for (final folder in folders) {
      ids.add(folder.id);
      await _collectFolderIdsRecursive(folder.id, ids);
    }
  }
}
