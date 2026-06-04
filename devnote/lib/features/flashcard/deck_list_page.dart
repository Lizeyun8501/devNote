import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/flashcard/bloc/flashcard_bloc.dart';
import 'package:devnote/features/flashcard/bloc/flashcard_event.dart';
import 'package:devnote/features/flashcard/bloc/flashcard_state.dart';
import 'package:devnote/features/flashcard/flashcard_service.dart';
import 'package:go_router/go_router.dart';

class DeckListPage extends StatelessWidget {
  const DeckListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => FlashcardBloc(FlashcardService())..add(const LoadDecks()),
      child: const _DeckListView(),
    );
  }
}

class _DeckListView extends StatelessWidget {
  const _DeckListView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('闪卡牌组'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateDeckDialog(context),
          ),
        ],
      ),
      body: BlocBuilder<FlashcardBloc, FlashcardState>(
        builder: (context, state) {
          if (state is FlashcardLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is FlashcardError) {
            return Center(child: Text('Error: ${state.message}'));
          }
          if (state is DecksLoaded) {
            if (state.decks.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.style, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('暂无牌组，点击右上角创建'),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.decks.length,
              itemBuilder: (context, index) {
                final deck = state.decks[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.style),
                    title: Text(deck.name),
                    subtitle: deck.description.isNotEmpty
                        ? Text(deck.description)
                        : null,
                    trailing: PopupMenuButton(
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'review', child: Text('开始复习')),
                        const PopupMenuItem(value: 'add_card', child: Text('添加卡片')),
                        const PopupMenuItem(value: 'stats', child: Text('复习统计')),
                        const PopupMenuItem(value: 'delete', child: Text('删除牌组')),
                      ],
                      onSelected: (value) {
                        switch (value) {
                          case 'review':
                            context.push('/flashcard/review/${deck.id}');
                          case 'add_card':
                            context.push('/flashcard/create?deckId=${deck.id}');
                          case 'stats':
                            context.push('/flashcard/stats/${deck.id}');
                          case 'delete':
                            context.read<FlashcardBloc>().add(DeleteDeck(deckId: deck.id));
                        }
                      },
                    ),
                    onTap: () {
                      context.push('/flashcard/review/${deck.id}');
                    },
                  ),
                );
              },
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  void _showCreateDeckDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('创建牌组'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '牌组名称'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: '描述'),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  context.read<FlashcardBloc>().add(
                        CreateDeck(
                          name: nameController.text,
                          description: descController.text,
                        ),
                      );
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
  }
}
