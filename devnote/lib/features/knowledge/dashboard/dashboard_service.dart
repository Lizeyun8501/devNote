import 'dart:convert';
import 'package:devnote/core/bridge/dispatch.dart';
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
    final responseStr = await _dispatch.getDashboard();
    final json = jsonDecode(responseStr);
    if (json is List) {
      return json
          .map((e) => DashboardCardData.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<DashboardStats> getDashboardStats() async {
    final responseStr = await _dispatch.getDashboard();
    try {
      final json = jsonDecode(responseStr);
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
    } catch (_) {
      return const DashboardStats(
        totalNotes: 0,
        totalFolders: 0,
        totalTags: 0,
        recentEdits: 0,
      );
    }
  }

  Future<void> updateCardOrder(List<String> cardIds) async {
    // FFI 层尚未实现此事件，无操作
  }
}
