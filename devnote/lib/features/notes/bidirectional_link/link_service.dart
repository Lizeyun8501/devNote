import 'package:devnote/core/persistence/note_repository.dart';
import 'package:devnote/core/persistence/models/note_model.dart';

class LinkInfo {
  final String noteName;
  final String? noteId;

  const LinkInfo({required this.noteName, this.noteId});
}

class BidirectionalLinkService {
  final NoteRepository _noteRepository;

  BidirectionalLinkService(this._noteRepository);

  static final linkPattern = RegExp(r'\[\[(.+?)\]\]');

  List<LinkInfo> parseLinks(String content) {
    final matches = linkPattern.allMatches(content);
    return matches.map((match) {
      final noteName = match.group(1)?.trim() ?? '';
      return LinkInfo(noteName: noteName);
    }).toList();
  }

  Future<List<LinkInfo>> parseLinksResolved(String content) async {
    final links = parseLinks(content);
    final resolved = <LinkInfo>[];
    for (final link in links) {
      final noteId = await _findNoteByName(link.noteName);
      resolved.add(LinkInfo(noteName: link.noteName, noteId: noteId));
    }
    return resolved;
  }

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

  String createLink(String noteName) {
    return '[[$noteName]]';
  }

  String removeLink(String content, String noteName) {
    return content.replaceAll('[[$noteName]]', noteName);
  }

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

  Future<List<String>> _getAllNoteFolders() async {
    return [];
  }
}
