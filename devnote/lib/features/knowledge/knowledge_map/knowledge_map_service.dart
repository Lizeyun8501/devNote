import 'dart:convert';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/persistence/models/tag_model.dart';

class LearningGoal {
  final String id;
  final String title;
  final double progress;
  final List<String> tags;

  const LearningGoal({
    required this.id,
    required this.title,
    required this.progress,
    required this.tags,
  });

  factory LearningGoal.fromJson(Map<String, dynamic> json) {
    return LearningGoal(
      id: json['id'] as String,
      title: json['title'] as String,
      progress: (json['progress'] as num).toDouble(),
      tags: (json['tags'] as List<dynamic>).cast<String>(),
    );
  }
}

class TagInfo {
  final String name;
  final int count;

  const TagInfo({
    required this.name,
    required this.count,
  });

  factory TagInfo.fromJson(Map<String, dynamic> json) {
    return TagInfo(
      name: json['name'] as String,
      count: json['count'] as int,
    );
  }
}

class KnowledgeMapData {
  final List<LearningGoal> goals;
  final List<TagInfo> tags;

  const KnowledgeMapData({
    required this.goals,
    required this.tags,
  });
}

class KnowledgeMapService {
  final Dispatch _dispatch = getIt<Dispatch>();

  Future<KnowledgeMapData> getKnowledgeMap() async {
    final responseStr = await _dispatch.getKnowledgeMap(noteId: '');
    final json = jsonDecode(responseStr);
    if (json is Map<String, dynamic>) {
      final goals = <LearningGoal>[];
      if (json.containsKey('goals') && json['goals'] is List) {
        for (final item in json['goals'] as List<dynamic>) {
          goals.add(LearningGoal.fromJson(item as Map<String, dynamic>));
        }
      }

      final tags = <TagInfo>[];
      if (json.containsKey('tags') && json['tags'] is List) {
        for (final item in json['tags'] as List<dynamic>) {
          tags.add(TagInfo.fromJson(item as Map<String, dynamic>));
        }
      }

      return KnowledgeMapData(goals: goals, tags: tags);
    }
    return const KnowledgeMapData(goals: [], tags: []);
  }

  Future<void> addGoal(String title, List<String> tags) async {
    // FFI 层尚未实现此事件，无操作
  }

  Future<void> updateGoalProgress(String goalId, double progress) async {
    // FFI 层尚未实现此事件，无操作
  }

  Future<List<TagInfo>> getTags() async {
    final tags = await _dispatch.listTags();
    // TagModel 不含 count 字段，使用 0 作为默认值
    return tags.map((t) => TagInfo(name: t.name, count: 0)).toList();
  }
}
