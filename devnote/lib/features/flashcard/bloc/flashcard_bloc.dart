import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/flashcard/bloc/flashcard_event.dart';
import 'package:devnote/features/flashcard/bloc/flashcard_state.dart';
import 'package:devnote/features/flashcard/flashcard_service.dart';

class FlashcardBloc extends Bloc<FlashcardEvent, FlashcardState> {
  final FlashcardService _flashcardService;

  FlashcardBloc(this._flashcardService) : super(const FlashcardInitial()) {
    on<LoadDecks>(_onLoadDecks);
    on<CreateDeck>(_onCreateDeck);
    on<DeleteDeck>(_onDeleteDeck);
    on<LoadDueCards>(_onLoadDueCards);
    on<CreateFlashcardEvent>(_onCreateFlashcard);
    on<DeleteFlashcardEvent>(_onDeleteFlashcard);
    on<ReviewFlashcardEvent>(_onReviewFlashcard);
    on<LoadReviewStats>(_onLoadReviewStats);
  }

  Future<void> _onLoadDecks(LoadDecks event, Emitter<FlashcardState> emit) async {
    emit(const FlashcardLoading());
    try {
      final decks = await _flashcardService.listDecks();
      emit(DecksLoaded(decks: decks));
    } catch (e) {
      emit(FlashcardError(e.toString()));
    }
  }

  Future<void> _onCreateDeck(CreateDeck event, Emitter<FlashcardState> emit) async {
    try {
      await _flashcardService.createDeck(event.name, event.description);
      final decks = await _flashcardService.listDecks();
      emit(DecksLoaded(decks: decks));
    } catch (e) {
      emit(FlashcardError(e.toString()));
    }
  }

  Future<void> _onDeleteDeck(DeleteDeck event, Emitter<FlashcardState> emit) async {
    try {
      await _flashcardService.deleteDeck(event.deckId);
      final decks = await _flashcardService.listDecks();
      emit(DecksLoaded(decks: decks));
    } catch (e) {
      emit(FlashcardError(e.toString()));
    }
  }

  Future<void> _onLoadDueCards(LoadDueCards event, Emitter<FlashcardState> emit) async {
    emit(const FlashcardLoading());
    try {
      final cards = await _flashcardService.getDueCards(event.deckId, event.limit);
      emit(DueCardsLoaded(cards: cards));
    } catch (e) {
      emit(FlashcardError(e.toString()));
    }
  }

  Future<void> _onCreateFlashcard(CreateFlashcardEvent event, Emitter<FlashcardState> emit) async {
    try {
      await _flashcardService.createFlashcard(
        deckId: event.deckId,
        cardType: event.cardType,
        front: event.front,
        back: event.back,
        noteId: event.noteId,
      );
    } catch (e) {
      emit(FlashcardError(e.toString()));
    }
  }

  Future<void> _onDeleteFlashcard(DeleteFlashcardEvent event, Emitter<FlashcardState> emit) async {
    try {
      await _flashcardService.deleteFlashcard(event.flashcardId);
    } catch (e) {
      emit(FlashcardError(e.toString()));
    }
  }

  Future<void> _onReviewFlashcard(ReviewFlashcardEvent event, Emitter<FlashcardState> emit) async {
    final currentState = state;
    if (currentState is! DueCardsLoaded) return;
    try {
      await _flashcardService.reviewFlashcard(event.flashcardId, event.quality);
      final nextIndex = currentState.currentIndex + 1;
      emit(currentState.copyWith(
        currentIndex: nextIndex,
        showBack: false,
      ));
    } catch (e) {
      emit(FlashcardError(e.toString()));
    }
  }

  Future<void> _onLoadReviewStats(LoadReviewStats event, Emitter<FlashcardState> emit) async {
    try {
      final stats = await _flashcardService.getReviewStats(event.deckId);
      emit(ReviewStatsLoaded(stats: stats));
    } catch (e) {
      emit(FlashcardError(e.toString()));
    }
  }
}
