import 'package:flutter/material.dart';
import 'package:devnote/features/knowledge/dashboard/dashboard_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final DashboardService _service = DashboardService();
  DashboardStats? _stats;
  List<DashboardCardData> _cards = [];
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final statsFuture = _service.getDashboardStats();
      final cardsFuture = _service.getDashboardCards();
      final stats = await statsFuture;
      final cards = await cardsFuture;
      if (mounted) {
        setState(() {
          _stats = stats;
          _cards = cards;
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
        title: const Text('仪表盘'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _filter = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('全部')),
              const PopupMenuItem(value: 'stats', child: Text('统计')),
              const PopupMenuItem(value: 'chart', child: Text('图表')),
              const PopupMenuItem(value: 'recent', child: Text('最近')),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _DashboardStatCard(
                          title: '笔记总数',
                          value: '${_stats?.totalNotes ?? 0}',
                          icon: Icons.note_outlined,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DashboardStatCard(
                          title: '文件夹数',
                          value: '${_stats?.totalFolders ?? 0}',
                          icon: Icons.folder_outlined,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DashboardStatCard(
                          title: '标签数',
                          value: '${_stats?.totalTags ?? 0}',
                          icon: Icons.label_outline,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DashboardStatCard(
                          title: '最近编辑',
                          value: '${_stats?.recentEdits ?? 0}',
                          icon: Icons.edit_outlined,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '快捷筛选',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('全部'),
                        selected: _filter == 'all',
                        onSelected: (_) => setState(() => _filter = 'all'),
                      ),
                      FilterChip(
                        label: const Text('统计'),
                        selected: _filter == 'stats',
                        onSelected: (_) => setState(() => _filter = 'stats'),
                      ),
                      FilterChip(
                        label: const Text('图表'),
                        selected: _filter == 'chart',
                        onSelected: (_) => setState(() => _filter = 'chart'),
                      ),
                      FilterChip(
                        label: const Text('最近'),
                        selected: _filter == 'recent',
                        onSelected: (_) => setState(() => _filter = 'recent'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_filteredCards.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('暂无仪表盘卡片')),
                      ),
                    )
                  else
                    ..._filteredCards.map((card) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _cardTypeIcon(card.type),
                                        size: 18,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          card.title,
                                          style: Theme.of(context).textTheme.titleSmall,
                                        ),
                                      ),
                                      const Icon(Icons.drag_indicator, size: 18),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _buildCardContent(card),
                                ],
                              ),
                            ),
                          ),
                        )),
                ],
              ),
            ),
    );
  }

  List<DashboardCardData> get _filteredCards {
    if (_filter == 'all') return _cards;
    return _cards.where((card) => card.type == _filter).toList();
  }

  IconData _cardTypeIcon(String type) {
    switch (type) {
      case 'stats':
        return Icons.bar_chart_outlined;
      case 'chart':
        return Icons.show_chart;
      case 'recent':
        return Icons.history;
      default:
        return Icons.dashboard_outlined;
    }
  }

  Widget _buildCardContent(DashboardCardData card) {
    switch (card.type) {
      case 'stats':
        return SizedBox(
          height: 60,
          child: CustomPaint(
            size: Size.infinite,
            painter: _MiniBarPainter(
              values: [0.6, 0.8, 0.4, 0.9, 0.7, 0.5, 0.85],
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      case 'chart':
        return SizedBox(
          height: 60,
          child: CustomPaint(
            size: Size.infinite,
            painter: _MiniLinePainter(
              values: [0.3, 0.5, 0.4, 0.7, 0.6, 0.8, 0.75],
              color: Colors.green,
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _DashboardStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _DashboardStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBarPainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _MiniBarPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / (values.length * 2);
    final paint = Paint()..color = color.withValues(alpha: 0.6);

    for (int i = 0; i < values.length; i++) {
      final v = values[i].clamp(0.0, 1.0);
      final x = i * barWidth * 2 + barWidth / 2;
      final barHeight = v * size.height;
      final rect = Rect.fromLTWH(x, size.height - barHeight, barWidth, barHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 4)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniBarPainter oldDelegate) =>
      values != oldDelegate.values || color != oldDelegate.color;
}

class _MiniLinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _MiniLinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final step = size.width / (values.length - 1).clamp(1, values.length);
    final path = Path();

    for (int i = 0; i < values.length; i++) {
      final x = i * step;
      final y = size.height - values[i].clamp(0.0, 1.0) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MiniLinePainter oldDelegate) =>
      values != oldDelegate.values || color != oldDelegate.color;
}
