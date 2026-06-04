import 'package:flutter/material.dart';
import 'package:devnote/features/knowledge/dashboard/dashboard_service.dart';

/// 数据库仪表盘页面
///
/// 设计灵感来源：
/// 1. Grafana Dashboard 设计 (https://grafana.com/docs/grafana/latest/dashboards/)
///    - 统计卡片：顶部展示关键指标（KPI）概览
///    - 趋势图表：时间序列折线图展示数据增长趋势
///    - 聚合面板：按数据库维度展示记录数统计
/// 2. 借鉴 Grafana 的 Panel 概念，每个仪表盘组件都是独立的可复用 Panel。
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

  /// 模拟数据：今日新增笔记数
  int _todayNewNotes = 0;

  /// 模拟数据：待复习卡片数
  int _pendingReviewCards = 0;

  /// 模拟数据：知识图谱节点数
  int _graphNodeCount = 0;

  /// 模拟数据：最近 7 天笔记增长趋势
  final List<double> _weeklyTrend = [3, 5, 2, 8, 6, 4, 7];

  /// 模拟数据：各数据库记录数
  final List<_DbAggregation> _dbAggregations = [
    const _DbAggregation(name: '学习笔记', recordCount: 42, rowCount: 128),
    const _DbAggregation(name: '工作日志', recordCount: 18, rowCount: 56),
    const _DbAggregation(name: '项目跟踪', recordCount: 7, rowCount: 35),
    const _DbAggregation(name: '阅读清单', recordCount: 23, rowCount: 89),
  ];

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
          _todayNewNotes = (stats.totalNotes * 0.15).round(); // 模拟今日新增 ~15%
          _pendingReviewCards = (stats.totalNotes * 0.3).round(); // 模拟待复习 ~30%
          _graphNodeCount = stats.totalNotes + stats.totalTags; // 模拟知识图谱节点
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
                  // ---- 统计卡片行 ----
                  // 借鉴 Grafana Stat Panel：展示关键指标的聚合值
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
                          title: '今日新增',
                          value: '$_todayNewNotes',
                          icon: Icons.add_circle_outline,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DashboardStatCard(
                          title: '待复习卡片',
                          value: '$_pendingReviewCards',
                          icon: Icons.school_outlined,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DashboardStatCard(
                          title: '知识图谱节点',
                          value: '$_graphNodeCount',
                          icon: Icons.account_tree_outlined,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ---- 趋势图表面板 ----
                  // 借鉴 Grafana Time Series Panel：展示时间序列数据变化趋势
                  if (_filter == 'all' || _filter == 'chart') ...[
                    _buildSectionTitle(context, '最近 7 天笔记增长趋势'),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.show_chart,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 8),
                                const Text(
                                  '笔记增长曲线',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 120,
                              child: CustomPaint(
                                size: const Size(double.infinity, 120),
                                painter: _TrendLinePainter(
                                  values: _weeklyTrend,
                                  color: Theme.of(context).colorScheme.primary,
                                  labels: _getPast7DaysLabels(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ---- 数据库聚合面板 ----
                  // 借鉴 Grafana Bar Gauge / Table Panel：按维度展示聚合数据
                  if (_filter == 'all' || _filter == 'stats') ...[
                    _buildSectionTitle(context, '数据库聚合概览'),
                    const SizedBox(height: 8),
                    ..._dbAggregations.map(
                        (db) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          db.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall,
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            _buildAggregationBar(
                                              context,
                                              label: '记录数',
                                              value: db.recordCount,
                                              max: _dbAggregations
                                                  .map((e) => e.recordCount)
                                                  .reduce((a, b) => a > b ? a : b),
                                              color: Colors.blue,
                                            ),
                                            const SizedBox(height: 4),
                                            _buildAggregationBar(
                                              context,
                                              label: '行数',
                                              value: db.rowCount,
                                              max: _dbAggregations
                                                  .map((e) => e.rowCount)
                                                  .reduce((a, b) => a > b ? a : b),
                                              color: Colors.teal,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )),
                    const SizedBox(height: 16),
                  ],

                  // ---- 快捷筛选 ----
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
                                        color:
                                            Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          card.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall,
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

  /// 构建面板标题
  /// 借鉴 Grafana Panel Header 样式
  Widget _buildSectionTitle(BuildContext context, String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  /// 构建聚合进度条
  Widget _buildAggregationBar(
    BuildContext context, {
    required String label,
    required int value,
    required int max,
    required Color color,
  }) {
    final ratio = max > 0 ? value / max : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: color.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text(
            '$value',
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  /// 获取过去 7 天的日期标签
  List<String> _getPast7DaysLabels() {
    final labels = <String>[];
    for (int i = 6; i >= 0; i--) {
      final date = DateTime.now().subtract(Duration(days: i));
      labels.add('${date.month}/${date.day}');
    }
    return labels;
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
            size: const Size(double.infinity, 60),
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
            size: const Size(double.infinity, 60),
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

/// 数据库聚合数据模型
class _DbAggregation {
  final String name;
  final int recordCount;
  final int rowCount;

  const _DbAggregation({
    required this.name,
    required this.recordCount,
    required this.rowCount,
  });
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

/// 趋势折线 Painter
/// 借鉴 Grafana Time Series Panel 的绘制方式：
/// 带渐变填充的平滑折线图，支持日期标签显示。
class _TrendLinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final List<String> labels;

  _TrendLinePainter({
    required this.values,
    required this.color,
    this.labels = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final range = (maxVal - minVal).clamp(1.0, double.infinity);
    final padding = 30.0; // 底部留白给标签
    final chartHeight = size.height - padding;

    // 绘制渐变填充区域
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.3),
          color.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, chartHeight));

    final fillPath = Path();
    final linePath = Path();

    final stepX = size.width / (values.length - 1).clamp(1, values.length);

    for (int i = 0; i < values.length; i++) {
      final x = i * stepX;
      final normalizedY = (values[i] - minVal) / range;
      final y = chartHeight - normalizedY * chartHeight;

      if (i == 0) {
        fillPath.moveTo(x, chartHeight);
        fillPath.lineTo(x, y);
        linePath.moveTo(x, y);
      } else {
        fillPath.lineTo(x, y);
        linePath.lineTo(x, y);
      }
    }

    // 闭合填充区域
    fillPath.lineTo((values.length - 1) * stepX, chartHeight);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

    // 绘制折线
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    // 绘制数据点
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (int i = 0; i < values.length; i++) {
      final x = i * stepX;
      final normalizedY = (values[i] - minVal) / range;
      final y = chartHeight - normalizedY * chartHeight;
      canvas.drawCircle(Offset(x, y), 3.5, dotPaint);
    }

    // 绘制日期标签
    if (labels.isNotEmpty) {
      final labelStyle = TextStyle(
        color: Colors.grey.shade500,
        fontSize: 10,
      );
      final textPainter = TextPainter(
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );

      for (int i = 0; i < labels.length; i++) {
        final x = i * stepX;
        textPainter.text = TextSpan(text: labels[i], style: labelStyle);
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, chartHeight + 4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter oldDelegate) =>
      values != oldDelegate.values || color != oldDelegate.color;
}
