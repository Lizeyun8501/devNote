import 'dart:convert';
import 'dart:io';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/di/injection.dart';

enum CardType { basic, cloze, reverse }

class FlashcardModel {
  final String id;
  final String? noteId;
  final CardType cardType;
  final String front;
  final String back;
  final String deckId;
  final DateTime createdAt;

  const FlashcardModel({
    required this.id,
    this.noteId,
    required this.cardType,
    required this.front,
    required this.back,
    required this.deckId,
    required this.createdAt,
  });

  factory FlashcardModel.fromJson(Map<String, dynamic> json) {
    return FlashcardModel(
      id: json['id'] as String,
      noteId: json['note_id'] as String?,
      cardType: CardType.values.firstWhere(
        (e) => e.name == (json['card_type'] as String).toLowerCase(),
        orElse: () => CardType.basic,
      ),
      front: json['front'] as String,
      back: json['back'] as String,
      deckId: json['deck_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (noteId != null) 'note_id': noteId,
      'card_type': cardType.name,
      'front': front,
      'back': back,
      'deck_id': deckId,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class FlashcardDeckModel {
  final String id;
  final String name;
  final String description;
  final DateTime createdAt;

  const FlashcardDeckModel({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
  });

  factory FlashcardDeckModel.fromJson(Map<String, dynamic> json) {
    return FlashcardDeckModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class ReviewRecordModel {
  final String id;
  final String flashcardId;
  final int quality;
  final DateTime reviewedAt;
  final DateTime nextReview;
  final double easeFactor;
  final int interval;
  final int repetitions;

  const ReviewRecordModel({
    required this.id,
    required this.flashcardId,
    required this.quality,
    required this.reviewedAt,
    required this.nextReview,
    required this.easeFactor,
    required this.interval,
    required this.repetitions,
  });

  factory ReviewRecordModel.fromJson(Map<String, dynamic> json) {
    return ReviewRecordModel(
      id: json['id'] as String,
      flashcardId: json['flashcard_id'] as String,
      quality: json['quality'] as int,
      reviewedAt: DateTime.parse(json['reviewed_at'] as String),
      nextReview: DateTime.parse(json['next_review'] as String),
      easeFactor: (json['ease_factor'] as num).toDouble(),
      interval: json['interval'] as int,
      repetitions: json['repetitions'] as int,
    );
  }
}

class ReviewStatsModel {
  final int totalCards;
  final int dueCards;
  final int reviewedToday;
  final double averageQuality;

  const ReviewStatsModel({
    required this.totalCards,
    required this.dueCards,
    required this.reviewedToday,
    required this.averageQuality,
  });

  factory ReviewStatsModel.fromJson(Map<String, dynamic> json) {
    return ReviewStatsModel(
      totalCards: json['total_cards'] as int,
      dueCards: json['due_cards'] as int,
      reviewedToday: json['reviewed_today'] as int,
      averageQuality: (json['average_quality'] as num).toDouble(),
    );
  }
}

class FlashcardService {
  final Dispatch _dispatch = getIt<Dispatch>();

  Future<FlashcardDeckModel> createDeck(String name, String description) async {
    final jsonStr = await _dispatch.createDeck(name: name, description: description);
    final json = jsonDecode(jsonStr);
    if (json is Map<String, dynamic>) {
      return FlashcardDeckModel.fromJson(json);
    }
    throw Exception('Failed to create deck');
  }

  Future<void> deleteDeck(String deckId) async {
    await _dispatch.deleteDeck(deckId: deckId);
  }

  Future<List<FlashcardDeckModel>> listDecks() async {
    final list = await _dispatch.listDecks();
    return list.map((e) => FlashcardDeckModel.fromJson(e)).toList();
  }

  Future<FlashcardModel> createFlashcard({
    required String deckId,
    required CardType cardType,
    required String front,
    required String back,
    String? noteId,
  }) async {
    final json = await _dispatch.createFlashcard(
      deckId: deckId,
      cardType: cardType.name,
      front: front,
      back: back,
      noteId: noteId,
    );
    return FlashcardModel.fromJson(json);
  }

  Future<FlashcardModel> updateFlashcard(String id, String front, String back) async {
    final json = await _dispatch.updateFlashcard(id: id, front: front, back: back);
    return FlashcardModel.fromJson(json);
  }

  Future<void> deleteFlashcard(String id) async {
    await _dispatch.deleteFlashcard(flashcardId: id);
  }

  Future<ReviewRecordModel> reviewFlashcard(String flashcardId, int quality) async {
    final jsonStr = await _dispatch.reviewFlashcard(flashcardId: flashcardId, quality: quality);
    final json = jsonDecode(jsonStr);
    if (json is Map<String, dynamic>) {
      return ReviewRecordModel.fromJson(json);
    }
    throw Exception('Failed to review flashcard');
  }

  Future<List<FlashcardModel>> getDueCards(String deckId, int limit) async {
    final jsonStr = await _dispatch.getDueCards(deckId: deckId, limit: limit);
    final json = jsonDecode(jsonStr);
    if (json is List) {
      return json
          .map((e) => FlashcardModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  Future<ReviewStatsModel> getReviewStats(String deckId) async {
    final json = await _dispatch.getReviewStats(deckId: deckId);
    return ReviewStatsModel.fromJson(json);
  }

  // ============================================================
  // 批量生成闪卡功能
  // 借鉴 Anki 的批量导入机制：https://docs.ankiweb.net/importing/textfiles.html
  // ============================================================

  /// 从笔记内容批量生成闪卡
  /// 识别笔记中的 Q: / A: 格式，自动创建问答卡片
  /// 识别 Cloze 格式 {{c1::答案}}，自动创建填空卡片
  Future<List<FlashcardModel>> batchGenerateFromNote(String noteId) async {
    final list = await _dispatch.batchGenerateFromNote(noteId: noteId);
    return list.map((e) => FlashcardModel.fromJson(e)).toList();
  }

  /// 批量导入闪卡（从文本文件）
  /// 支持 CSV / TSV 格式：正面\t背面\t标签1,标签2
  /// 借鉴 Anki 的文本文件导入格式
  Future<int> batchImportCards(String filePath, {String deckId = 'default', String delimiter = '\t'}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $filePath');
    }

    final content = await file.readAsString();
    final lines = content.split('\n').where((line) => line.trim().isNotEmpty).toList();

    int importedCount = 0;
    for (final line in lines) {
      final parts = line.split(delimiter);
      if (parts.length < 2) continue;

      final front = parts[0].trim();
      final back = parts[1].trim();
      if (front.isEmpty || back.isEmpty) continue;

      try {
        // 自动识别卡片类型：包含 Cloze 标记则创建 cloze 卡片
        final cardType = _detectCardType(front, back);
        await createFlashcard(
          deckId: deckId,
          cardType: cardType,
          front: front,
          back: back,
        );
        importedCount++;
      } catch (e) {
        // 跳过导入失败的行，继续处理下一行
        continue;
      }
    }

    return importedCount;
  }

  /// 检测卡片类型
  CardType _detectCardType(String front, String back) {
    // 检测 Cloze 格式: {{c1::答案}}
    if (front.contains(RegExp(r'\{\{c\d+::')) || back.contains(RegExp(r'\{\{c\d+::'))) {
      return CardType.cloze;
    }
    return CardType.basic;
  }
}
