import 'dart:convert';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/di/injection.dart';

class DailyStats {
  final DateTime date;
  final int notesCreated;
  final int notesEdited;
  final int reviewMinutes;

  const DailyStats({
    required this.date,
    required this.notesCreated,
    required this.notesEdited,
    required this.reviewMinutes,
  });

  factory DailyStats.fromJson(Map<String, dynamic> json) {
    return DailyStats(
      date: DateTime.parse(json['date'] as String),
      notesCreated: json['notes_created'] as int,
      notesEdited: json['notes_edited'] as int,
      reviewMinutes: json['review_minutes'] as int,
    );
  }
}

class KnowledgeCoverage {
  final String category;
  final double coverage;

  const KnowledgeCoverage({
    required this.category,
    required this.coverage,
  });

  factory KnowledgeCoverage.fromJson(Map<String, dynamic> json) {
    return KnowledgeCoverage(
      category: json['category'] as String,
      coverage: (json['coverage'] as num).toDouble(),
    );
  }
}

class KnowledgeBlindSpot {
  final String topic;
  final double relevance;

  const KnowledgeBlindSpot({
    required this.topic,
    required this.relevance,
  });

  factory KnowledgeBlindSpot.fromJson(Map<String, dynamic> json) {
    return KnowledgeBlindSpot(
      topic: json['topic'] as String,
      relevance: (json['relevance'] as num).toDouble(),
    );
  }
}

class LearningStatsSummary {
  final int todayNotesCreated;
  final int todayNotesEdited;
  final int todayReviewMinutes;
  final int weekNotesCreated;
  final int weekNotesEdited;
  final int weekReviewMinutes;
  final int monthNotesCreated;
  final int monthNotesEdited;
  final int monthReviewMinutes;
  final List<DailyStats> dailyTrend;
  final List<KnowledgeCoverage> coverageData;
  final List<KnowledgeBlindSpot> blindSpots;

  const LearningStatsSummary({
    required this.todayNotesCreated,
    required this.todayNotesEdited,
    required this.todayReviewMinutes,
    required this.weekNotesCreated,
    required this.weekNotesEdited,
    required this.weekReviewMinutes,
    required this.monthNotesCreated,
    required this.monthNotesEdited,
    required this.monthReviewMinutes,
    required this.dailyTrend,
    required this.coverageData,
    required this.blindSpots,
  });
}

class LearningStatsService {
  final Dispatch _dispatch = getIt<Dispatch>();

  Future<LearningStatsSummary> getStatsSummary() async {
    final responseStr = await _dispatch.getLearningStats(noteId: '');
    final json = jsonDecode(responseStr);
    if (json is Map<String, dynamic>) {
      return _parseSummary(json);
    }
    return _emptySummary();
  }

  LearningStatsSummary _emptySummary() {
    return const LearningStatsSummary(
      todayNotesCreated: 0,
      todayNotesEdited: 0,
      todayReviewMinutes: 0,
      weekNotesCreated: 0,
      weekNotesEdited: 0,
      weekReviewMinutes: 0,
      monthNotesCreated: 0,
      monthNotesEdited: 0,
      monthReviewMinutes: 0,
      dailyTrend: [],
      coverageData: [],
      blindSpots: [],
    );
  }

  LearningStatsSummary _parseSummary(Map<String, dynamic> json) {
    final dailyTrend = <DailyStats>[];
    if (json.containsKey('daily_trend') && json['daily_trend'] is List) {
      for (final item in json['daily_trend'] as List<dynamic>) {
        dailyTrend.add(DailyStats.fromJson(item as Map<String, dynamic>));
      }
    }

    final coverageData = <KnowledgeCoverage>[];
    if (json.containsKey('coverage') && json['coverage'] is List) {
      for (final item in json['coverage'] as List<dynamic>) {
        coverageData.add(KnowledgeCoverage.fromJson(item as Map<String, dynamic>));
      }
    }

    final blindSpots = <KnowledgeBlindSpot>[];
    if (json.containsKey('blind_spots') && json['blind_spots'] is List) {
      for (final item in json['blind_spots'] as List<dynamic>) {
        blindSpots.add(KnowledgeBlindSpot.fromJson(item as Map<String, dynamic>));
      }
    }

    return LearningStatsSummary(
      todayNotesCreated: json['today_notes_created'] as int? ?? 0,
      todayNotesEdited: json['today_notes_edited'] as int? ?? 0,
      todayReviewMinutes: json['today_review_minutes'] as int? ?? 0,
      weekNotesCreated: json['week_notes_created'] as int? ?? 0,
      weekNotesEdited: json['week_notes_edited'] as int? ?? 0,
      weekReviewMinutes: json['week_review_minutes'] as int? ?? 0,
      monthNotesCreated: json['month_notes_created'] as int? ?? 0,
      monthNotesEdited: json['month_notes_edited'] as int? ?? 0,
      monthReviewMinutes: json['month_review_minutes'] as int? ?? 0,
      dailyTrend: dailyTrend,
      coverageData: coverageData,
      blindSpots: blindSpots,
    );
  }

  Future<List<DailyStats>> getNoteCreationTrend({int days = 30}) async {
    // FFI 层尚未实现此事件，返回空数据
    return [];
  }

  Future<List<KnowledgeCoverage>> getKnowledgeCoverage() async {
    // FFI 层尚未实现此事件，返回空数据
    return [];
  }

  Future<List<KnowledgeBlindSpot>> findBlindSpots() async {
    // FFI 层尚未实现此事件，返回空数据
    return [];
  }
}
