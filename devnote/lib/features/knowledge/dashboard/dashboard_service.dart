import 'dart:convert';
import 'dart:typed_data';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/bridge/error.dart';
import 'package:devnote/core/di/injection.dart';

class DashboardCardData {
  final String id;
  final String title;
  final String type;
  final Map<String, dynamic> config;

  const DashboardCardData({
    required this.id,
    required this.title,
    required this.type,
    required this.config,
  });

  factory DashboardCardData.fromJson(Map<String, dynamic> json) {
    return DashboardCardData(
      id: json['id'] as String,
      title: json['title'] as String,
      type: json['type'] as String,
      config: json['config'] as Map<String, dynamic>? ?? {},
    );
  }
}

class DashboardStats {
  final int totalNotes;
  final int totalFolders;
  final int totalTags;
  final int recentEdits;

  const DashboardStats({
    required this.totalNotes,
    required this.totalFolders,
    required this.totalTags,
    required this.recentEdits,
  });
}

class DashboardService {
  final Dispatch _dispatch = getIt<Dispatch>();

  Future<List<DashboardCardData>> getDashboardCards() async {
    final result = await _dispatch.asyncRequest(
      'KnowledgeEvent.GetDashboardCards',
      payload: Uint8List(0),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is List) {
        return json
            .map((e) => DashboardCardData.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    }
    if (result is Failure<Uint8List, FlowyInternalError>) {
      throw Exception(result.error.message);
    }
    throw Exception('Unknown result type');
  }

  Future<DashboardStats> getDashboardStats() async {
    final result = await _dispatch.asyncRequest(
      'KnowledgeEvent.GetDashboardStats',
      payload: Uint8List(0),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is Map<String, dynamic>) {
        return DashboardStats(
          totalNotes: json['total_notes'] as int? ?? 0,
          totalFolders: json['total_folders'] as int? ?? 0,
          totalTags: json['total_tags'] as int? ?? 0,
          recentEdits: json['recent_edits'] as int? ?? 0,
        );
      }
      return const DashboardStats(
        totalNotes: 0,
        totalFolders: 0,
        totalTags: 0,
        recentEdits: 0,
      );
    }
    if (result is Failure<Uint8List, FlowyInternalError>) {
      throw Exception(result.error.message);
    }
    throw Exception('Unknown result type');
  }

  Future<void> updateCardOrder(List<String> cardIds) async {
    final payload = jsonEncode({'card_ids': cardIds});
    await _dispatch.asyncRequest(
      'KnowledgeEvent.UpdateCardOrder',
      payload: utf8.encode(payload),
    );
  }
}
