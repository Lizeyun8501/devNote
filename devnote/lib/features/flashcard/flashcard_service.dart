import 'dart:convert';
import 'dart:typed_data';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/bridge/error.dart';
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
    final payload = jsonEncode({'name': name, 'description': description});
    final result = await _dispatch.asyncRequest(
      'FlashcardEvent.CreateDeck',
      payload: utf8.encode(payload),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is Map<String, dynamic>) {
        return FlashcardDeckModel.fromJson(json);
      }
    }
    throw Exception('Failed to create deck');
  }

  Future<void> deleteDeck(String deckId) async {
    final payload = jsonEncode({'deck_id': deckId});
    await _dispatch.asyncRequest(
      'FlashcardEvent.DeleteDeck',
      payload: utf8.encode(payload),
    );
  }

  Future<List<FlashcardDeckModel>> listDecks() async {
    final result = await _dispatch.asyncRequest(
      'FlashcardEvent.ListDecks',
      payload: Uint8List(0),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is List) {
        return json
            .map((e) => FlashcardDeckModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

  Future<FlashcardModel> createFlashcard({
    required String deckId,
    required CardType cardType,
    required String front,
    required String back,
    String? noteId,
  }) async {
    final payload = jsonEncode({
      'deck_id': deckId,
      'card_type': cardType.name,
      'front': front,
      'back': back,
      if (noteId != null) 'note_id': noteId,
    });
    final result = await _dispatch.asyncRequest(
      'FlashcardEvent.CreateFlashcard',
      payload: utf8.encode(payload),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is Map<String, dynamic>) {
        return FlashcardModel.fromJson(json);
      }
    }
    throw Exception('Failed to create flashcard');
  }

  Future<FlashcardModel> updateFlashcard(String id, String front, String back) async {
    final payload = jsonEncode({'id': id, 'front': front, 'back': back});
    final result = await _dispatch.asyncRequest(
      'FlashcardEvent.UpdateFlashcard',
      payload: utf8.encode(payload),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is Map<String, dynamic>) {
        return FlashcardModel.fromJson(json);
      }
    }
    throw Exception('Failed to update flashcard');
  }

  Future<void> deleteFlashcard(String id) async {
    final payload = jsonEncode({'flashcard_id': id});
    await _dispatch.asyncRequest(
      'FlashcardEvent.DeleteFlashcard',
      payload: utf8.encode(payload),
    );
  }

  Future<ReviewRecordModel> reviewFlashcard(String flashcardId, int quality) async {
    final payload = jsonEncode({'flashcard_id': flashcardId, 'quality': quality});
    final result = await _dispatch.asyncRequest(
      'FlashcardEvent.ReviewFlashcard',
      payload: utf8.encode(payload),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is Map<String, dynamic>) {
        return ReviewRecordModel.fromJson(json);
      }
    }
    throw Exception('Failed to review flashcard');
  }

  Future<List<FlashcardModel>> getDueCards(String deckId, int limit) async {
    final payload = jsonEncode({'deck_id': deckId, 'limit': limit});
    final result = await _dispatch.asyncRequest(
      'FlashcardEvent.GetDueCards',
      payload: utf8.encode(payload),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is List) {
        return json
            .map((e) => FlashcardModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

  Future<ReviewStatsModel> getReviewStats(String deckId) async {
    final payload = jsonEncode({'deck_id': deckId});
    final result = await _dispatch.asyncRequest(
      'FlashcardEvent.GetReviewStats',
      payload: utf8.encode(payload),
    );
    if (result is Success<Uint8List, FlowyInternalError>) {
      final json = jsonDecode(utf8.decode(result.value));
      if (json is Map<String, dynamic>) {
        return ReviewStatsModel.fromJson(json);
      }
    }
    throw Exception('Failed to get review stats');
  }
}
