import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/flashcard/bloc/flashcard_bloc.dart';
import 'package:devnote/features/flashcard/bloc/flashcard_event.dart';
import 'package:devnote/features/flashcard/bloc/flashcard_state.dart';
import 'package:devnote/features/flashcard/flashcard_service.dart';
import 'package:devnote/features/flashcard/widgets/flashcard_widget.dart';
import 'package:devnote/features/flashcard/widgets/rating_buttons.dart';

class ReviewPage extends StatelessWidget {
  final String deckId;

  const ReviewPage({super.key, required this.deckId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => FlashcardBloc(getIt<FlashcardService>())
        ..add(LoadDueCards(deckId: deckId)),
      child: const _ReviewView(),
    );
  }
}

class _ReviewView extends StatefulWidget {
  const _ReviewView();

  @override
  State<_ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends State<_ReviewView> {
  bool _showBack = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('复习'),
      ),
      body: BlocBuilder<FlashcardBloc, FlashcardState>(
        builder: (context, state) {
          if (state is FlashcardLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is FlashcardError) {
            return Center(child: Text('Error: ${state.message}'));
          }
          if (state is DueCardsLoaded) {
            if (state.cards.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, size: 64, color: Colors.green),
                    SizedBox(height: 16),
                    Text('暂无到期卡片'),
                  ],
                ),
              );
            }

            if (state.isComplete) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.celebration, size: 64, color: Colors.amber),
                    const SizedBox(height: 16),
                    const Text('复习完成！'),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('返回'),
                    ),
                  ],
                ),
              );
            }

            final card = state.currentCard!;
            final progress = (state.currentIndex + 1) / state.cards.length;

            return Column(
              children: [
                LinearProgressIndicator(value: progress),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${state.currentIndex + 1} / ${state.cards.length}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        _cardTypeLabel(card.cardType),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                FlashcardWidget(
                  front: card.front,
                  back: card.back,
                  showBack: _showBack,
                  onFlip: () {
                    setState(() {
                      _showBack = true;
                    });
                  },
                ),
                const Spacer(),
                if (_showBack)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    child: RatingButtons(
                      onRate: (quality) {
                        context.read<FlashcardBloc>().add(
                              ReviewFlashcardEvent(
                                flashcardId: card.id,
                                quality: quality,
                              ),
                            );
                        setState(() {
                          _showBack = false;
                        });
                      },
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '点击卡片翻转查看答案',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ),
              ],
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  String _cardTypeLabel(CardType type) {
    switch (type) {
      case CardType.basic:
        return '基础卡片';
      case CardType.cloze:
        return '填空卡片';
      case CardType.reverse:
        return '双向卡片';
    }
  }
}
