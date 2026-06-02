import 'dart:convert';
import 'dart:typed_data';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/bridge/error.dart';

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
  final Dispatch _dispatch = Dispatch.instance;

  Future<KnowledgeMapData> getKnowledgeMap() async {
    final result = await _dispatch.asyncRequest(
      'KnowledgeEvent.GetKnowledgeMap',
      payload: Uint8List(0),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
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
    if (result is Failure<Uint8List, FlowyInternalError>) {
      throw Exception(result.error.message);
    }
    throw Exception('Unknown result type');
  }

  Future<void> addGoal(String title, List<String> tags) async {
    final payload = jsonEncode({
      'title': title,
      'tags': tags,
    });
    await _dispatch.asyncRequest(
      'KnowledgeEvent.AddGoal',
      payload: utf8.encode(payload),
    );
  }

  Future<void> updateGoalProgress(String goalId, double progress) async {
    final payload = jsonEncode({
      'goal_id': goalId,
      'progress': progress,
    });
    await _dispatch.asyncRequest(
      'KnowledgeEvent.UpdateGoalProgress',
      payload: utf8.encode(payload),
    );
  }

  Future<List<TagInfo>> getTags() async {
    final result = await _dispatch.asyncRequest(
      'KnowledgeEvent.GetTags',
      payload: Uint8List(0),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is List) {
        return json
            .map((e) => TagInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    }
    return [];
  }
}
