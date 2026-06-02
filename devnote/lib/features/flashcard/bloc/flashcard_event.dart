import 'package:equatable/equatable.dart';
import 'package:devnote/features/flashcard/flashcard_service.dart';

abstract class FlashcardEvent extends Equatable {
  const FlashcardEvent();

  @override
  List<Object?> get props => [];
}

class LoadDecks extends FlashcardEvent {
  const LoadDecks();
}

class CreateDeck extends FlashcardEvent {
  final String name;
  final String description;

  const CreateDeck({required this.name, this.description = ''});

  @override
  List<Object?> get props => [name, description];
}

class DeleteDeck extends FlashcardEvent {
  final String deckId;

  const DeleteDeck({required this.deckId});

  @override
  List<Object?> get props => [deckId];
}

class LoadDueCards extends FlashcardEvent {
  final String deckId;
  final int limit;

  const LoadDueCards({required this.deckId, this.limit = 20});

  @override
  List<Object?> get props => [deckId, limit];
}

class CreateFlashcardEvent extends FlashcardEvent {
  final String deckId;
  final CardType cardType;
  final String front;
  final String back;
  final String? noteId;

  const CreateFlashcardEvent({
    required this.deckId,
    required this.cardType,
    required this.front,
    required this.back,
    this.noteId,
  });

  @override
  List<Object?> get props => [deckId, cardType, front, back, noteId];
}

class DeleteFlashcardEvent extends FlashcardEvent {
  final String flashcardId;

  const DeleteFlashcardEvent({required this.flashcardId});

  @override
  List<Object?> get props => [flashcardId];
}

class ReviewFlashcardEvent extends FlashcardEvent {
  final String flashcardId;
  final int quality;

  const ReviewFlashcardEvent({required this.flashcardId, required this.quality});

  @override
  List<Object?> get props => [flashcardId, quality];
}

class LoadReviewStats extends FlashcardEvent {
  final String deckId;

  const LoadReviewStats({required this.deckId});

  @override
  List<Object?> get props => [deckId];
}
