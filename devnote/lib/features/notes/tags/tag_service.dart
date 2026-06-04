import 'package:uuid/uuid.dart';
import 'package:devnote/core/persistence/tag_repository.dart';
import 'package:devnote/core/persistence/models/tag_model.dart';

class TagService {
  final TagRepository _tagRepository;
  final _uuid = const Uuid();

  TagService(this._tagRepository);

  Future<TagModel> createTag(String name) async {
    final tag = TagModel(
      id: _uuid.v4(),
      name: name,
      createdAt: DateTime.now(),
    );
    return _tagRepository.createTag(tag);
  }

  Future<void> addTagToNote(String noteId, String tagId) async {
    await _tagRepository.addTagToNote(noteId, tagId);
  }

  Future<void> removeTagFromNote(String noteId, String tagId) async {
    await _tagRepository.removeTagFromNote(noteId, tagId);
  }

  Future<List<TagModel>> getTagsForNote(String noteId) async {
    return _tagRepository.getTagsForNote(noteId);
  }

  Future<List<TagModel>> getAllTags() async {
    return _tagRepository.getAllTags();
  }
}
