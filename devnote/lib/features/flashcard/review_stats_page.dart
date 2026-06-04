import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/flashcard/bloc/flashcard_bloc.dart';
import 'package:devnote/features/flashcard/bloc/flashcard_event.dart';
import 'package:devnote/features/flashcard/bloc/flashcard_state.dart';
import 'package:devnote/features/flashcard/flashcard_service.dart';

class ReviewStatsPage extends StatelessWidget {
  final String deckId;

  const ReviewStatsPage({super.key, required this.deckId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => FlashcardBloc(FlashcardService())..add(LoadReviewStats(deckId: deckId)),
      child: const _ReviewStatsView(),
    );
  }
}

class _ReviewStatsView extends StatelessWidget {
  const _ReviewStatsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('复习统计'),
      ),
      body: BlocBuilder<FlashcardBloc, FlashcardState>(
        builder: (context, state) {
          if (state is FlashcardLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is FlashcardError) {
            return Center(child: Text('Error: ${state.message}'));
          }
          if (state is ReviewStatsLoaded) {
            final stats = state.stats;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatCard(
                        title: '总卡片',
                        value: '${stats.totalCards}',
                        icon: Icons.style,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        title: '待复习',
                        value: '${stats.dueCards}',
                        icon: Icons.pending_actions,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _StatCard(
                        title: '今日已复习',
                        value: '${stats.reviewedToday}',
                        icon: Icons.check_circle,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        title: '平均评分',
                        value: stats.averageQuality.toStringAsFixed(1),
                        icon: Icons.star,
                        color: Colors.amber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '记忆曲线',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _ForgettingCurvePainter(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '复习日历',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _HeatmapPainter(
                        reviewedToday: stats.reviewedToday,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                title,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForgettingCurvePainter extends CustomPainter {
  final Color color;

  const _ForgettingCurvePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    const padding = 30.0;
    final chartWidth = size.width - padding * 2;
    final chartHeight = size.height - padding * 2;

    final path = Path();
    final fillPath = Path();

    for (var i = 0; i <= 100; i++) {
      final t = i / 100;
      final x = padding + t * chartWidth;
      final retention = (t * 30).abs().toDouble();
      final y = padding + chartHeight * (1 - math.exp(retention) / (1 + math.exp(retention)));

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(padding + chartWidth, padding + chartHeight);
    fillPath.lineTo(padding, padding + chartHeight);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    final axisPaint = Paint()
      ..color = Colors.grey
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(padding, padding),
      Offset(padding, padding + chartHeight),
      axisPaint,
    );
    canvas.drawLine(
      Offset(padding, padding + chartHeight),
      Offset(padding + chartWidth, padding + chartHeight),
      axisPaint,
    );

    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(text: '100%', style: TextStyle(fontSize: 10, color: Colors.grey));
    tp.layout();
    tp.paint(canvas, Offset(2, padding - 4));

    tp.text = TextSpan(text: '0%', style: TextStyle(fontSize: 10, color: Colors.grey));
    tp.layout();
    tp.paint(canvas, Offset(4, padding + chartHeight - 4));

    tp.text = TextSpan(text: '时间', style: TextStyle(fontSize: 10, color: Colors.grey));
    tp.layout();
    tp.paint(canvas, Offset(padding + chartWidth - 20, padding + chartHeight + 8));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HeatmapPainter extends CustomPainter {
  final int reviewedToday;
  final Color color;

  const _HeatmapPainter({required this.reviewedToday, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const cols = 7;
    const rows = 4;
    const padding = 20.0;
    final cellWidth = (size.width - padding * 2) / cols;
    final cellHeight = (size.height - padding * 2) / rows;
    final gap = 3.0;

    final random = DateTime.now().millisecondsSinceEpoch;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final x = padding + col * cellWidth + gap / 2;
        final y = padding + row * cellHeight + gap / 2;
        final w = cellWidth - gap;
        final h = cellHeight - gap;

        var intensity = 0.0;
        if (row == rows - 1 && col == cols - 1) {
          intensity = reviewedToday > 0 ? (reviewedToday / 20).clamp(0.1, 1.0) : 0.0;
        } else {
          final seed = (random + row * cols + col) % 100;
          if (seed < 30) intensity = 0.0;
          else if (seed < 50) intensity = 0.2;
          else if (seed < 70) intensity = 0.4;
          else if (seed < 85) intensity = 0.6;
          else intensity = 0.8;
        }

        final paint = Paint()
          ..color = intensity > 0
              ? color.withValues(alpha: intensity)
              : Colors.grey.withValues(alpha: 0.1)
          ..style = PaintingStyle.fill;

        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          Radius.circular(w * 0.15),
        );
        canvas.drawRRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
