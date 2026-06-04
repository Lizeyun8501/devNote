import 'package:flutter/material.dart';
import 'package:devnote/features/knowledge/learning_stats/learning_stats_service.dart';
import 'package:devnote/features/knowledge/learning_stats/widgets/stats_card.dart';
import 'package:devnote/features/knowledge/learning_stats/widgets/trend_chart.dart';

class LearningReportPage extends StatefulWidget {
  const LearningReportPage({super.key});

  @override
  State<LearningReportPage> createState() => _LearningReportPageState();
}

class _LearningReportPageState extends State<LearningReportPage> {
  final LearningStatsService _service = LearningStatsService();
  LearningStatsSummary? _summary;
  bool _loading = true;
  String _period = 'monthly';

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
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
        title: const Text('学习报告'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'monthly', label: Text('月度')),
                    ButtonSegment(value: 'yearly', label: Text('年度')),
                  ],
                  selected: {_period},
                  onSelectionChanged: (values) {
                    setState(() {
                      _period = values.first;
                    });
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  '关键指标汇总',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: StatsCard(
                        title: _period == 'monthly' ? '本月创建' : '今年创建',
                        value: '${_summary?.monthNotesCreated ?? 0}',
                        icon: Icons.note_add_outlined,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatsCard(
                        title: _period == 'monthly' ? '本月编辑' : '今年编辑',
                        value: '${_summary?.monthNotesEdited ?? 0}',
                        icon: Icons.edit_note,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  '知识增长趋势',
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
                  '复习时间趋势',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: TrendChart(
                    data: _summary?.dailyTrend
                            .map((e) => TrendData(
                                  label: '${e.date.month}/${e.date.day}',
                                  value: e.reviewMinutes.toDouble(),
                                ))
                            .toList() ??
                        [],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '知识盲区提醒',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_summary?.blindSpots.isEmpty ?? true)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('暂无知识盲区'),
                    ),
                  )
                else
                  ..._summary!.blindSpots.map((spot) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.lightbulb_outline, color: Colors.amber),
                          title: Text(spot.topic),
                          subtitle: Text('建议复习，相关度 ${(spot.relevance * 100).toStringAsFixed(0)}%'),
                        ),
                      )),
              ],
            ),
    );
  }
}
