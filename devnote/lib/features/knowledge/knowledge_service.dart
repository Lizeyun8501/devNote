import 'dart:convert';
import 'dart:typed_data';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/bridge/error.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/knowledge/learning_stats/learning_stats_service.dart';
import 'package:devnote/features/knowledge/knowledge_map/knowledge_map_service.dart';

class KnowledgeService {
  final Dispatch _dispatch = getIt<Dispatch>();

  Future<Map<String, dynamic>> getKnowledgeOverview() async {
    final result = await _dispatch.asyncRequest(
      'KnowledgeEvent.GetOverview',
      payload: Uint8List(0),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is Map<String, dynamic>) {
        return json;
      }
      return {};
    }
    if (result is Failure<Uint8List, FlowyInternalError>) {
      throw Exception(result.error.message);
    }
    throw Exception('Unknown result type');
  }

  Future<LearningStatsSummary> getLearningStats() async {
    final service = LearningStatsService();
    return service.getStatsSummary();
  }

  Future<KnowledgeMapData> getKnowledgeMap() async {
    final service = KnowledgeMapService();
    return service.getKnowledgeMap();
  }

  Future<Map<String, dynamic>> generateReport({required String period}) async {
    final payload = jsonEncode({'period': period});
    final result = await _dispatch.asyncRequest(
      'KnowledgeEvent.GenerateReport',
      payload: utf8.encode(payload),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is Map<String, dynamic>) {
        return json;
      }
      return {};
    }
    if (result is Failure<Uint8List, FlowyInternalError>) {
      throw Exception(result.error.message);
    }
    throw Exception('Unknown result type');
  }
}
