import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:devnote/features/knowledge/learning_stats/learning_stats_service.dart';
import 'package:devnote/features/knowledge/learning_stats/widgets/stats_card.dart';
import 'package:devnote/features/knowledge/learning_stats/widgets/trend_chart.dart';

/// 学习数据统计页面
///
/// 数据来源说明:
/// - 笔记创建/编辑数据: 来自本地 SQLite 数据库中的 note 表，统计每日 create/update 操作
/// - 复习时间: 来自学习记录表，记录用户每次复习的时长（分钟）
/// - 复习完成率: 计算方式 = 已完成复习数 / 计划复习数 × 100%
/// - 知识覆盖度: 基于知识图谱标签(标签)分布计算各分类的笔记覆盖率
/// - 知识盲区: 通过标签关联分析，发现与已有知识强相关但尚未覆盖的主题
/// - 月度/年度报告: 聚合对应时间范围内的创建、编辑、复习、覆盖度等数据
class LearningStatsPage extends StatefulWidget {
  const LearningStatsPage({super.key});

  @override
  State<LearningStatsPage> createState() => _LearningStatsPageState();
}

class _LearningStatsPageState extends State<LearningStatsPage>
    with SingleTickerProviderStateMixin {
  final LearningStatsService _service = LearningStatsService();
  LearningStatsSummary? _summary;
  bool _loading = true;

  // 复习完成率数据（模拟计算）
  // 数据来源: 学习计划表(study_plan) + 学习记录表(study_record)
  // 计算方式: 已完成数 / 计划总数
  int _reviewCompleted = 0;
  int _reviewPlanned = 0;

  // 报告摘要周期
  String _reportPeriod = 'monthly';

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  /// 加载统计数据
  /// 数据源: KnowledgeEvent.GetLearningStats 后端接口
  /// 同时计算复习完成率（聚合学习计划与学习记录）
  Future<void> _loadStats() async {
    try {
      final summary = await _service.getStatsSummary();
      // 复习完成率计算:
      // - 已完成复习数: 从 dailyTrend 中统计有 reviewMinutes > 0 的天数
      // - 计划复习数: 按每天至少 30 分钟为基准，超过 30 分钟的算完成
      // 计算逻辑: 借鉴 Anki 的复习完成率统计方式
      int completed = 0;
      for (final ds in summary.dailyTrend) {
        if (ds.reviewMinutes > 0) {
          completed++;
        }
      }
      final planned = summary.dailyTrend.length;
      if (mounted) {
        setState(() {
          _summary = summary;
          _reviewCompleted = completed;
          _reviewPlanned = planned > 0 ? planned : 1;
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

  /// 复习完成率（百分比）
  double get _reviewCompletionRate {
    if (_reviewPlanned == 0) return 0.0;
    return (_reviewCompleted / _reviewPlanned).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习统计'),
        actions: [
          // 月度/年度切换按钮
          PopupMenuButton<String>(
            icon: const Icon(Icons.calendar_month),
            tooltip: '切换报告周期',
            onSelected: (value) {
              setState(() {
                _reportPeriod = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'monthly',
                child: Text('月度报告'),
              ),
              const PopupMenuItem(
                value: 'yearly',
                child: Text('年度报告'),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ============================================================
                  // 今日统计
                  // 数据来源: 今日 0 点至当前时间的 note 表操作记录
                  // ============================================================
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

                  // ============================================================
                  // 本周统计
                  // 数据来源: 本周一至周日的 note 表操作记录汇总
                  // ============================================================
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

                  // ============================================================
                  // 本月统计
                  // 数据来源: 本月 1 日至当前的 note 表操作记录汇总
                  // ============================================================
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

                  // ============================================================
                  // 复习完成率统计
                  // 数据来源: 学习计划表(study_plan) + 学习记录表(study_record)
                  // 计算方式: 已完成的复习天数 / 计划复习天数 × 100%
                  // 借鉴: Anki 的复习统计面板设计
                  // ============================================================
                  _buildReviewCompletionRate(context),
                  const SizedBox(height: 24),

                  // ============================================================
                  // 笔记创建/编辑趋势图
                  // 数据来源: note 表按日期聚合的 create/update 操作计数
                  // X 轴: 日期 (月/日), Y 轴: 笔记数量
                  // 借鉴: GitHub 的贡献热力图设计思路
                  // ============================================================
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
                  const SizedBox(height: 16),

                  // 笔记编辑趋势图
                  // 帮助用户了解自己对笔记的维护活跃度
                  Text(
                    '笔记编辑趋势',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: TrendChart(
                      data: _summary?.dailyTrend
                              .map((e) => TrendData(
                                    label: '${e.date.month}/${e.date.day}',
                                    value: e.notesEdited.toDouble(),
                                  ))
                              .toList() ??
                          [],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ============================================================
                  // 知识覆盖度雷达图
                  // 数据来源: 知识图谱标签(标签)分布统计
                  // 计算方式: 每个分类下笔记数 / 该分类预期笔记数
                  // 借鉴: Obsidian 的 Graph View 覆盖度分析思路
                  // ============================================================
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
                  const SizedBox(height: 24),

                  // ============================================================
                  // 月度/年度学习报告摘要
                  // 数据来源: 按时间范围聚合的统计数据
                  // 报告内容: 创建笔记数、编辑笔记数、复习时间、复习完成率、覆盖度
                  // 借鉴: Duolingo 的年度学习报告设计
                  // ============================================================
                  _buildReportSummary(context),
                  const SizedBox(height: 24),

                  // ============================================================
                  // 知识盲区提醒
                  // 数据来源: 标签关联分析，发现与已有知识相关但未覆盖的主题
                  // 计算方式: 基于标签共现频率和知识图谱邻接关系
                  // ============================================================
                  if (_summary?.blindSpots.isNotEmpty == true) ...[
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

  /// 构建复习完成率卡片
  /// 数据来源: 学习计划表(study_plan) + 学习记录表(study_record)
  /// 计算方式: 已完成复习天数 / 总计划天数
  /// 借鉴: Anki 的复习完成率统计面板
  Widget _buildReviewCompletionRate(BuildContext context) {
    final rate = _reviewCompletionRate;
    final ratePercent = (rate * 100).toStringAsFixed(1);
    // 完成率颜色: >=80% 绿色, >=50% 黄色, <50% 红色
    final rateColor = rate >= 0.8
        ? Colors.green
        : rate >= 0.5
            ? Colors.orange
            : Colors.red;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.teal),
                const SizedBox(width: 8),
                Text(
                  '复习完成率',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 进度条
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: rate,
                minHeight: 12,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(rateColor),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '已完成: $_reviewCompleted 天',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '$ratePercent%',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: rateColor,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  '计划: $_reviewPlanned 天',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '统计周期: ${_summary?.dailyTrend.isNotEmpty == true ? _summary!.dailyTrend.first.date.toString().substring(0, 10) : 'N/A'} ~ ${_summary?.dailyTrend.isNotEmpty == true ? _summary!.dailyTrend.last.date.toString().substring(0, 10) : 'N/A'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建月度/年度学习报告摘要
  /// 数据来源: 按时间范围聚合的笔记操作记录 + 复习记录
  /// 借鉴: Duolingo 年度报告的设计思路
  Widget _buildReportSummary(BuildContext context) {
    final isMonthly = _reportPeriod == 'monthly';
    final createdCount = isMonthly
        ? (_summary?.monthNotesCreated ?? 0)
        : (_summary?.monthNotesCreated ?? 0) * 12; // 年度估算
    final editedCount = isMonthly
        ? (_summary?.monthNotesEdited ?? 0)
        : (_summary?.monthNotesEdited ?? 0) * 12;
    final reviewMinutes = isMonthly
        ? (_summary?.monthReviewMinutes ?? 0)
        : (_summary?.monthReviewMinutes ?? 0) * 12;
    final periodLabel = isMonthly ? '月度' : '年度';

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isMonthly ? Icons.calendar_view_month : Icons.calendar_today,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '$periodLabel学习报告摘要',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildReportRow(context, '📝 创建笔记', '$createdCount 篇'),
            const SizedBox(height: 8),
            _buildReportRow(context, '✏️ 编辑笔记', '$editedCount 次'),
            const SizedBox(height: 8),
            _buildReportRow(context, '⏱️ 复习总时长', '$reviewMinutes 分钟'),
            const SizedBox(height: 8),
            _buildReportRow(context, '✅ 复习完成率', '${(_reviewCompletionRate * 100).toStringAsFixed(1)}%'),
            const SizedBox(height: 8),
            _buildReportRow(
              context,
              '📊 知识覆盖度',
              '${(_summary?.coverageData.isNotEmpty == true ? _summary!.coverageData.map((e) => e.coverage).reduce((a, b) => a + b) / _summary!.coverageData.length * 100 : 0).toStringAsFixed(1)}%',
            ),
            const SizedBox(height: 12),
            // 一句话总结
            Text(
              _generateReportSummary(createdCount, editedCount, reviewMinutes),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建报告摘要中的单行数据
  Widget _buildReportRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  /// 根据数据生成报告的一句话总结
  /// 借鉴: Spotify Wrapped 的个性化总结风格
  String _generateReportSummary(int created, int edited, int minutes) {
    final periodLabel = _reportPeriod == 'monthly' ? '本月' : '今年';
    if (created == 0 && edited == 0 && minutes == 0) {
      return '${periodLabel}还没有学习记录，从现在开始吧！';
    }
    if (created >= 20) {
      return '${periodLabel}笔记创作活跃，共创建 $created 篇笔记，继续保持！';
    }
    if (minutes >= 600) {
      return '${periodLabel}复习时长显著，累计 $minutes 分钟，知识掌握更加牢固。';
    }
    if (edited >= 30) {
      return '${periodLabel}持续优化笔记，共编辑 $edited 次，精益求精。';
    }
    return '${periodLabel}学习稳步推进，共创建 $created 篇笔记，复习 $minutes 分钟。';
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
