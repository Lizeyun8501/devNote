import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:devnote/features/knowledge/learning_stats/learning_stats_service.dart';
import 'package:devnote/features/knowledge/learning_stats/widgets/stats_card.dart';
import 'package:devnote/features/knowledge/learning_stats/widgets/trend_chart.dart';

class LearningStatsPage extends StatefulWidget {
  const LearningStatsPage({super.key});

  @override
  State<LearningStatsPage> createState() => _LearningStatsPageState();
}

class _LearningStatsPageState extends State<LearningStatsPage> {
  final LearningStatsService _service = LearningStatsService();
  LearningStatsSummary? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final summary = await _service.getStatsSummary();
      if (mounted) {
        setState(() {
          _summary = summary;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习统计'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '今日',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: StatsCard(
                          title: '创建笔记',
                          value: '${_summary?.todayNotesCreated ?? 0}',
                          icon: Icons.note_add_outlined,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatsCard(
                          title: '编辑笔记',
                          value: '${_summary?.todayNotesEdited ?? 0}',
                          icon: Icons.edit_note,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatsCard(
                          title: '复习时间',
                          value: '${_summary?.todayReviewMinutes ?? 0}分钟',
                          icon: Icons.timer_outlined,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '本周',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: StatsCard(
                          title: '创建笔记',
                          value: '${_summary?.weekNotesCreated ?? 0}',
                          icon: Icons.note_add_outlined,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatsCard(
                          title: '编辑笔记',
                          value: '${_summary?.weekNotesEdited ?? 0}',
                          icon: Icons.edit_note,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatsCard(
                          title: '复习时间',
                          value: '${_summary?.weekReviewMinutes ?? 0}分钟',
                          icon: Icons.timer_outlined,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '本月',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: StatsCard(
                          title: '创建笔记',
                          value: '${_summary?.monthNotesCreated ?? 0}',
                          icon: Icons.note_add_outlined,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatsCard(
                          title: '编辑笔记',
                          value: '${_summary?.monthNotesEdited ?? 0}',
                          icon: Icons.edit_note,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: StatsCard(
                          title: '复习时间',
                          value: '${_summary?.monthReviewMinutes ?? 0}分钟',
                          icon: Icons.timer_outlined,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '笔记创建趋势',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: TrendChart(
                      data: _summary?.dailyTrend
                              .map((e) => TrendData(
                                    label: '${e.date.month}/${e.date.day}',
                                    value: e.notesCreated.toDouble(),
                                  ))
                              .toList() ??
                          [],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '知识覆盖度',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: _summary?.coverageData.isNotEmpty == true
                        ? CustomPaint(
                            size: Size.infinite,
                            painter: _RadarPainter(
                              categories: _summary!.coverageData.map((e) => e.category).toList(),
                              values: _summary!.coverageData.map((e) => e.coverage).toList(),
                            ),
                          )
                        : const Center(child: Text('暂无覆盖度数据')),
                  ),
                  if (_summary?.blindSpots.isNotEmpty == true) ...[
                    const SizedBox(height: 24),
                    Text(
                      '知识盲区',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ..._summary!.blindSpots.map((spot) => ListTile(
                          leading: const Icon(Icons.warning_amber, color: Colors.amber),
                          title: Text(spot.topic),
                          subtitle: Text('相关度: ${(spot.relevance * 100).toStringAsFixed(0)}%'),
                        )),
                  ],
                ],
              ),
            ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<String> categories;
  final List<double> values;

  _RadarPainter({
    required this.categories,
    required this.values,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 40;
    final n = categories.length;
    if (n < 3) return;

    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int level = 1; level <= 4; level++) {
      final r = radius * level / 4;
      final path = Path();
      for (int i = 0; i < n; i++) {
        final angle = 2 * 3.14159265 * i / n - 3.14159265 / 2;
        final px = center.dx + r * math.cos(angle);
        final py = center.dy + r * math.sin(angle);
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    for (int i = 0; i < n; i++) {
      final angle = 2 * 3.14159265 * i / n - 3.14159265 / 2;
      final ex = center.dx + radius * math.cos(angle);
      final ey = center.dy + radius * math.sin(angle);
      canvas.drawLine(center, Offset(ex, ey), gridPaint);
    }

    final dataPath = Path();
    for (int i = 0; i < n; i++) {
      final angle = 2 * 3.14159265 * i / n - 3.14159265 / 2;
      final v = i < values.length ? values[i].clamp(0.0, 1.0) : 0.0;
      final r = radius * v;
      final px = center.dx + r * math.cos(angle);
      final py = center.dy + r * math.sin(angle);
      if (i == 0) {
        dataPath.moveTo(px, py);
      } else {
        dataPath.lineTo(px, py);
      }
    }
    dataPath.close();
    canvas.drawPath(dataPath, paint);
    canvas.drawPath(dataPath, linePaint);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < n; i++) {
      final angle = 2 * 3.14159265 * i / n - 3.14159265 / 2;
      final lx = center.dx + (radius + 20) * math.cos(angle);
      final ly = center.dy + (radius + 20) * math.sin(angle);
      textPainter.text = TextSpan(
        text: categories[i],
        style: TextStyle(fontSize: 10, color: Colors.grey[700]),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(lx - textPainter.width / 2, ly - textPainter.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      categories != oldDelegate.categories || values != oldDelegate.values;
}
