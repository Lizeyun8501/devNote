import 'package:equatable/equatable.dart';
import 'package:devnote/features/flashcard/flashcard_service.dart';

abstract class FlashcardState extends Equatable {
  const FlashcardState();

  @override
  List<Object?> get props => [];
}

class FlashcardInitial extends FlashcardState {
  const FlashcardInitial();
}

class FlashcardLoading extends FlashcardState {
  const FlashcardLoading();
}

class DecksLoaded extends FlashcardState {
  final List<FlashcardDeckModel> decks;

  const DecksLoaded({required this.decks});

  @override
  List<Object?> get props => [decks];
}

class DueCardsLoaded extends FlashcardState {
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

  @override
  List<Object?> get props => [cards, currentIndex, showBack];
}

class ReviewStatsLoaded extends FlashcardState {
  final ReviewStatsModel stats;

  const ReviewStatsLoaded({required this.stats});

  @override
  List<Object?> get props => [stats];
}

class FlashcardError extends FlashcardState {
  final String message;

  const FlashcardError(this.message);

  @override
  List<Object?> get props => [message];
}
