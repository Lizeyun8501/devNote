import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/flashcard/bloc/flashcard_bloc.dart';
import 'package:devnote/features/flashcard/bloc/flashcard_event.dart';
import 'package:devnote/features/flashcard/bloc/flashcard_state.dart';
import 'package:devnote/features/flashcard/flashcard_service.dart';

class CreateCardPage extends StatefulWidget {
  final String? deckId;

  const CreateCardPage({super.key, this.deckId});

  @override
  State<CreateCardPage> createState() => _CreateCardPageState();
}

class _CreateCardPageState extends State<CreateCardPage> {
  final _frontController = TextEditingController();
  final _backController = TextEditingController();
  CardType _cardType = CardType.basic;
  String? _selectedDeckId;

  @override
  void initState() {
    super.initState();
    _selectedDeckId = widget.deckId;
  }

  @override
  void dispose() {
    _frontController.dispose();
    _backController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => FlashcardBloc(getIt<FlashcardService>())..add(const LoadDecks()),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('创建卡片'),
          actions: [
            TextButton(
              onPressed: _createCard,
              child: const Text('保存'),
            ),
          ],
        ),
        body: BlocBuilder<FlashcardBloc, FlashcardState>(
          builder: (context, state) {
            final decks = state is DecksLoaded ? state.decks : <FlashcardDeckModel>[];

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedDeckId,
                    decoration: const InputDecoration(
                      labelText: '选择牌组',
                      border: OutlineInputBorder(),
                    ),
                    items: decks.map((deck) {
                      return DropdownMenuItem(
                        value: deck.id,
                        child: Text(deck.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedDeckId = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<CardType>(
                    segments: const [
                      ButtonSegment(value: CardType.basic, label: Text('基础'), icon: Icon(Icons.looks_one)),
                      ButtonSegment(value: CardType.cloze, label: Text('填空'), icon: Icon(Icons.text_fields)),
                      ButtonSegment(value: CardType.reverse, label: Text('双向'), icon: Icon(Icons.swap_horiz)),
                    ],
                    selected: {_cardType},
                    onSelectionChanged: (types) {
                      setState(() {
                        _cardType = types.first;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _frontController,
                    decoration: InputDecoration(
                      labelText: _cardType == CardType.cloze ? '文本（用 {{...}} 标记填空）' : '正面',
                      border: const OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _backController,
                    decoration: InputDecoration(
                      labelText: _cardType == CardType.cloze ? '填空答案' : '背面',
                      border: const OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _createCard,
                      child: const Text('创建卡片'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _createCard() {
    if (_selectedDeckId == null || _frontController.text.isEmpty || _backController.text.isEmpty) {
      return;
    }
    context.read<FlashcardBloc>().add(
          CreateFlashcardEvent(
            deckId: _selectedDeckId!,
            cardType: _cardType,
            front: _frontController.text,
            back: _backController.text,
          ),
        );
    Navigator.pop(context);
  }
}
