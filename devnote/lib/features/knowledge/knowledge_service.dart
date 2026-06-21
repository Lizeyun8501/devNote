import 'dart:convert';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/knowledge/learning_stats/learning_stats_service.dart';
import 'package:devnote/features/knowledge/knowledge_map/knowledge_map_service.dart';

class KnowledgeService {
  final Dispatch _dispatch = getIt<Dispatch>();
  final LearningStatsService _statsService = getIt<LearningStatsService>();
  final KnowledgeMapService _mapService = getIt<KnowledgeMapService>();

  Future<Map<String, dynamic>> getKnowledgeOverview() async {
    final responseStr = await _dispatch.getDashboard();
    try {
      final json = jsonDecode(responseStr);
      if (json is Map<String, dynamic>) {
        return json;
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  Future<LearningStatsSummary> getLearningStats() async {
    return _statsService.getStatsSummary();
  }

  Future<KnowledgeMapData> getKnowledgeMap() async {
    return _mapService.getKnowledgeMap();
  }

  Future<Map<String, dynamic>> generateReport({required String period}) async {
    // FFI 层尚未实现此事件，返回空数据
    return {};
  }
}
