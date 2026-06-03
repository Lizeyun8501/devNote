import 'package:devnote/features/flashcard/flashcard_service.dart';

sealed class FlashcardState {
  const FlashcardState();
}

final class FlashcardInitial extends FlashcardState {
  const FlashcardInitial();
}

final class FlashcardLoading extends FlashcardState {
  const FlashcardLoading();
}

final class DecksLoaded extends FlashcardState {
  final List<FlashcardDeckModel> decks;

  const DecksLoaded({required this.decks});
}

final class DueCardsLoaded extends FlashcardState {
  final List<FlashcardModel> cards;
  final int currentIndex;
  final bool showBack;

  const DueCardsLoaded({
    required this.cards,
    this.currentIndex = 0,
    this.showBack = false,
  });

  FlashcardModel? get currentCard =>
      currentIndex < cards.length ? cards[currentIndex] : null;

  bool get isComplete => currentIndex >= cards.length;

  DueCardsLoaded copyWith({
    List<FlashcardModel>? cards,
    int? currentIndex,
    bool? showBack,
  }) {
    return DueCardsLoaded(
      cards: cards ?? this.cards,
      currentIndex: currentIndex ?? this.currentIndex,
      showBack: showBack ?? this.showBack,
    );
  }
}

final class ReviewStatsLoaded extends FlashcardState {
  final ReviewStatsModel stats;

  const ReviewStatsLoaded({required this.stats});
}

final class FlashcardError extends FlashcardState {
  final String message;

  const FlashcardError(this.message);
}
