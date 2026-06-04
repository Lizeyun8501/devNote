/// SyncMonitor - 同步状态监控与告警系统
///
/// 借鉴开源项目:
/// 1. Prometheus: https://prometheus.io/
///    借鉴内容: 指标收集模型（Counter、Gauge、Histogram）、时间序列数据、
///    拉取式（Pull-based）指标采集架构。
///
/// 2. Grafana: https://grafana.com/
///    借鉴内容: 告警规则引擎、阈值检测、告警状态机（Normal → Pending → Firing → Resolved）、
///    告警通知机制。
///
/// 设计原理:
/// Prometheus 使用 Counter（只增不减的计数器）和 Gauge（可增可减的仪表盘）来收集指标，
/// 通过 PromQL 查询语言进行指标分析。Grafana 基于 Prometheus 数据实现可视化面板和告警规则。
///
/// 本模块在客户端侧实现类似 Prometheus + Grafana 的监控能力:
/// - Counter 类型指标: syncCount（同步总次数）、syncFailures（失败总次数）、totalSyncedBytes（同步总字节）
/// - Gauge 类型指标: currentPendingChanges（当前待同步变更数）、lastSyncDuration（最近同步耗时）
/// - Histogram 类型指标: syncLatencyDistribution（同步延迟分布）
/// - 告警规则: 失败率阈值、延迟阈值、连续失败次数阈值
///
/// 架构映射:
/// ```
/// Prometheus 概念        → 本实现
/// ─────────────────────────────────────
/// Counter               → _syncCount, _syncFailures, _totalSyncedBytes
/// Gauge                 → _currentPendingChanges, _lastSyncDuration
/// Histogram             → SyncLatencyHistogram（延迟分布统计）
/// Alert Rules           → SyncAlertRule（可配置的告警规则）
/// Alert Manager         → SyncMonitor.checkAndAlert()
/// Metrics Endpoint      → getMetrics() 方法
/// ```
///
/// 使用方式:
/// ```dart
/// final monitor = SyncMonitor();
///
/// // 同步开始时记录
/// monitor.recordSyncStart();
///
/// // 同步成功时记录
/// monitor.recordSyncSuccess(bytes: 1024);
///
/// // 同步失败时记录
/// monitor.recordSyncFailure('网络超时');
///
/// // 检查告警
/// monitor.checkAndAlert();
///
/// // 获取指标
/// print(monitor.syncCount);        // 总同步次数
/// print(monitor.syncFailures);     // 总失败次数
/// print(monitor.averageSyncLatency); // 平均延迟
/// print(monitor.totalSyncedBytes); // 总同步字节数
/// ```

import 'dart:async';
import 'dart:math';

/// 同步指标快照 —— 借鉴 Prometheus 的 Metrics Snapshot
///
/// 来源: https://prometheus.io/docs/concepts/metric_types/
///
/// 包含某一时刻的所有同步相关指标，可用于:
/// - 上报到监控平台
/// - 本地诊断分析
/// - 告警规则评估
class SyncMetricsSnapshot {
  /// Counter: 同步总成功次数 —— 借鉴 Prometheus Counter 类型
  /// 只增不减，用于计算同步频率
  final int syncCount;

  /// Counter: 同步总失败次数 —— 借鉴 Prometheus Counter 类型
  final int syncFailures;

  /// Counter: 同步总字节数 —— 借鉴 Prometheus Counter 类型
  final int totalSyncedBytes;

  /// Gauge: 当前待同步变更数 —— 借鉴 Prometheus Gauge 类型
  final int pendingChanges;

  /// Gauge: 最近一次同步耗时（毫秒） —— 借鉴 Prometheus Gauge 类型
  final Duration lastSyncDuration;

  /// Histogram: 同步延迟分布 —— 借鉴 Prometheus Histogram 类型
  final SyncLatencyHistogram latencyHistogram;

  /// 当前同步状态
  final String currentStatus;

  /// 快照时间戳
  final DateTime timestamp;

  const SyncMetricsSnapshot({
    required this.syncCount,
    required this.syncFailures,
    required this.totalSyncedBytes,
    required this.pendingChanges,
    required this.lastSyncDuration,
    required this.latencyHistogram,
    required this.currentStatus,
    required this.timestamp,
  });

  /// 计算同步成功率
  double get successRate {
    final total = syncCount + syncFailures;
    if (total == 0) return 1.0;
    return syncCount / total;
  }

  /// 计算平均同步延迟
  Duration get averageSyncLatency => latencyHistogram.average;

  /// 转换为 JSON 格式 —— 用于上报或序列化
  Map<String, dynamic> toJson() => {
        'sync_count': syncCount,
        'sync_failures': syncFailures,
        'total_synced_bytes': totalSyncedBytes,
        'pending_changes': pendingChanges,
        'last_sync_duration_ms': lastSyncDuration.inMilliseconds,
        'average_sync_latency_ms': averageSyncLatency.inMilliseconds,
        'success_rate': successRate,
        'current_status': currentStatus,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// 同步延迟直方图 —— 借鉴 Prometheus Histogram 指标类型
///
/// 来源: https://prometheus.io/docs/concepts/metric_types/#histogram
///
/// Histogram 将观测值分布到预定义的桶（Bucket）中，
/// 用于分析延迟分布（P50、P90、P99 等分位数）。
///
/// 桶设计（借鉴 Prometheus 默认桶范围）:
/// - [0, 100ms):   极快同步
/// - [100ms, 500ms): 快速同步
/// - [500ms, 1s):    正常同步
/// - [1s, 3s):       较慢同步
/// - [3s, 10s):      慢同步
/// - [10s, +∞):      极慢同步
class SyncLatencyHistogram {
  /// 桶边界（毫秒） —— 借鉴 Prometheus 默认 bucket 设置
  static const List<int> bucketBoundaries = [100, 500, 1000, 3000, 10000];

  /// 各桶的计数值
  final List<int> _buckets;

  /// 所有观测值的总和（用于计算平均值）
  int _sum = 0;

  /// 观测值总数
  int _count = 0;

  SyncLatencyHistogram() : _buckets = List.filled(bucketBoundaries.length + 1, 0);

  /// 记录一次延迟观测值
  void observe(Duration duration) {
    final ms = duration.inMilliseconds;
    _sum += ms;
    _count++;

    // 找到对应的桶
    int bucketIndex = bucketBoundaries.length; // 默认最后一个桶（+∞）
    for (int i = 0; i < bucketBoundaries.length; i++) {
      if (ms < bucketBoundaries[i]) {
        bucketIndex = i;
        break;
      }
    }
    _buckets[bucketIndex]++;
  }

  /// 获取桶计数值
  List<int> get buckets => List.unmodifiable(_buckets);

  /// 获取桶边界标签
  List<String> get bucketLabels => [
        ...bucketBoundaries.map((b) => '<${b}ms'),
        '>=${bucketBoundaries.last}ms',
      ];

  /// 计算平均延迟 —— 借鉴 Prometheus 的 histogram 平均计算
  Duration get average {
    if (_count == 0) return Duration.zero;
    return Duration(milliseconds: _sum ~/ _count);
  }

  /// 获取总观测次数
  int get count => _count;

  /// 获取延迟总和
  int get sum => _sum;

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      'count': _count,
      'sum_ms': _sum,
      'average_ms': average.inMilliseconds,
      'buckets': <String, int>{},
    };
    for (int i = 0; i < _buckets.length; i++) {
      result['buckets'][bucketLabels[i]] = _buckets[i];
    }
    return result;
  }
}

/// 告警级别 —— 借鉴 Grafana 的 Alert Severity
///
/// 来源: https://grafana.com/docs/grafana/latest/alerting/
enum AlertSeverity {
  /// 信息级别 —— 仅作记录
  info,

  /// 警告级别 —— 需要关注
  warning,

  /// 严重级别 —— 需要立即处理
  critical,
}

/// 告警规则 —— 借鉴 Grafana 的 Alert Rule 配置
///
/// 来源: https://grafana.com/docs/grafana/latest/alerting/alerting-rules/
///
/// 告警规则包含:
/// - 规则名称和描述
/// - 评估条件（阈值、持续时间等）
/// - 告警级别
/// - 冷却时间（防止告警风暴）
class SyncAlertRule {
  /// 规则名称
  final String name;

  /// 规则描述
  final String description;

  /// 告警级别
  final AlertSeverity severity;

  /// 阈值（具体含义由评估函数决定）
  final double threshold;

  /// 持续时间阈值（超过此时间才触发告警）
  /// 借鉴 Grafana 的 "for" 条件: 条件持续满足 X 时间后才告警
  final Duration forDuration;

  /// 冷却时间 —— 防止告警风暴
  /// 借鉴 Grafana 的 Repeat Interval 配置
  final Duration cooldown;

  /// 上一次触发告警的时间
  DateTime? _lastFiredAt;

  SyncAlertRule({
    required this.name,
    required this.description,
    required this.severity,
    required this.threshold,
    this.forDuration = Duration.zero,
    this.cooldown = const Duration(minutes: 5),
  });

  /// 检查是否可以触发告警（考虑冷却时间）
  bool canFire() {
    if (_lastFiredAt == null) return true;
    return DateTime.now().difference(_lastFiredAt!) > cooldown;
  }

  /// 记录告警触发时间
  void markFired() {
    _lastFiredAt = DateTime.now();
  }
}

/// 告警事件 —— 借鉴 Grafana Alert Manager 的 Alert 模型
class SyncAlertEvent {
  final String ruleName;
  final AlertSeverity severity;
  final String message;
  final DateTime timestamp;

  const SyncAlertEvent({
    required this.ruleName,
    required this.severity,
    required this.message,
    required this.timestamp,
  });

  @override
  String toString() =>
      '[${severity.name.toUpperCase()}] $ruleName: $message (@${timestamp.toIso8601String()})';
}

/// SyncMonitor - 同步状态监控与告警系统
///
/// 核心设计借鉴:
/// 1. Prometheus 的指标收集模型（Counter/Gauge/Histogram）
///    来源: https://prometheus.io/docs/concepts/metric_types/
///
/// 2. Grafana 的告警规则引擎和通知机制
///    来源: https://grafana.com/docs/grafana/latest/alerting/
///
/// 监控指标:
/// - syncCount (Counter):     同步成功总次数
/// - syncFailures (Counter):  同步失败总次数
/// - totalSyncedBytes (Counter): 同步总字节数
/// - pendingChanges (Gauge):  当前待同步变更数
/// - lastSyncDuration (Gauge): 最近同步耗时
/// - latencyHistogram (Histogram): 同步延迟分布
///
/// 内置告警规则:
/// 1. 高失败率告警: 失败率 > 50% 且至少 5 次同步 → Critical
/// 2. 高延迟告警: 平均延迟 > 10s → Warning
/// 3. 连续失败告警: 连续失败 >= 3 次 → Critical
/// 4. 同步停滞告警: 超过 30 分钟未同步 → Warning
class SyncMonitor {
  // ==================== Counter 指标 ====================

  /// Counter: 同步成功总次数 —— 借鉴 Prometheus Counter
  /// 只增不减，应用重启时重置
  int _syncCount = 0;

  /// Counter: 同步失败总次数 —— 借鉴 Prometheus Counter
  int _syncFailures = 0;

  /// Counter: 同步总字节数 —— 借鉴 Prometheus Counter
  int _totalSyncedBytes = 0;

  // ==================== Gauge 指标 ====================

  /// Gauge: 当前待同步变更数 —— 借鉴 Prometheus Gauge
  /// 可增可减，反映当前积压状态
  int _pendingChanges = 0;

  /// Gauge: 最近一次同步耗时 —— 借鉴 Prometheus Gauge
  Duration _lastSyncDuration = Duration.zero;

  // ==================== Histogram 指标 ====================

  /// Histogram: 同步延迟分布 —— 借鉴 Prometheus Histogram
  final SyncLatencyHistogram _latencyHistogram = SyncLatencyHistogram();

  // ==================== 状态追踪 ====================

  /// 最近一次同步成功的时间
  DateTime? _lastSuccessAt;

  /// 最近一次同步尝试的时间
  DateTime? _lastSyncAttemptAt;

  /// 当前同步状态
  String _currentStatus = 'idle';

  /// 同步开始时间（用于计算延迟）
  DateTime? _syncStartTime;

  /// 连续失败次数
  int _consecutiveFailures = 0;

  // ==================== 告警规则 ====================

  /// 内置告警规则列表 —— 借鉴 Grafana 的 Alert Rules
  final List<SyncAlertRule> _alertRules = [];

  /// 已触发的告警事件列表
  final List<SyncAlertEvent> _alerts = [];

  /// 告警回调 —— 当检测到告警时调用
  void Function(SyncAlertEvent)? _onAlert;

  // ==================== 默认告警规则 ====================

  /// 设置默认告警规则 —— 借鉴 Grafana 推荐的监控配置
  void _setupDefaultAlertRules() {
    // 借鉴 Grafana 的高错误率告警规则
    // 来源: https://grafana.com/docs/grafana-cloud/alerting-and-irm/alerting/alerting-rules/
    _alertRules.add(SyncAlertRule(
      name: '高失败率告警',
      description: '同步失败率超过 50%，可能存在服务异常',
      severity: AlertSeverity.critical,
      threshold: 0.5, // 50% 失败率
      forDuration: const Duration(seconds: 30),
      cooldown: const Duration(minutes: 10),
    ));

    // 借鉴 Grafana 的高延迟告警规则
    _alertRules.add(SyncAlertRule(
      name: '高延迟告警',
      description: '平均同步延迟超过 10 秒，网络可能存在拥塞',
      severity: AlertSeverity.warning,
      threshold: 10000, // 10 秒（毫秒）
      forDuration: const Duration(minutes: 1),
      cooldown: const Duration(minutes: 5),
    ));

    // 借鉴 Grafana 的连续错误告警规则
    _alertRules.add(SyncAlertRule(
      name: '连续失败告警',
      description: '同步连续失败 3 次以上，需要人工介入',
      severity: AlertSeverity.critical,
      threshold: 3, // 连续 3 次失败
      forDuration: Duration.zero,
      cooldown: const Duration(minutes: 15),
    ));

    // 借鉴 Grafana 的停滞告警规则
    _alertRules.add(SyncAlertRule(
      name: '同步停滞告警',
      description: '超过 30 分钟未成功同步，可能存在连接问题',
      severity: AlertSeverity.warning,
      threshold: 30 * 60 * 1000, // 30 分钟（毫秒）
      forDuration: Duration.zero,
      cooldown: const Duration(minutes: 30),
    ));
  }

  SyncMonitor() {
    _setupDefaultAlertRules();
  }

  /// 设置告警回调函数
  void setAlertCallback(void Function(SyncAlertEvent) callback) {
    _onAlert = callback;
  }

  // ==================== Counter 指标访问 ====================

  /// 获取同步成功总次数 —— 对应 Prometheus Counter: devnote_sync_total
  int get syncCount => _syncCount;

  /// 获取同步失败总次数 —— 对应 Prometheus Counter: devnote_sync_failures_total
  int get syncFailures => _syncFailures;

  /// 获取同步总字节数 —— 对应 Prometheus Counter: devnote_synced_bytes_total
  int get totalSyncedBytes => _totalSyncedBytes;

  // ==================== Gauge 指标访问 ====================

  /// 获取当前待同步变更数 —— 对应 Prometheus Gauge: devnote_pending_changes
  int get pendingChanges => _pendingChanges;

  /// 获取最近一次同步耗时 —— 对应 Prometheus Gauge: devnote_last_sync_duration_seconds
  Duration get lastSyncDuration => _lastSyncDuration;

  // ==================== Histogram 指标访问 ====================

  /// 获取平均同步延迟 —— 对应 Prometheus Histogram: devnote_sync_latency_seconds
  Duration get averageSyncLatency => _latencyHistogram.average;

  /// 获取延迟直方图
  SyncLatencyHistogram get latencyHistogram => _latencyHistogram;

  // ==================== 记录同步事件 ====================

  /// 记录同步开始 —— 用于计算同步延迟
  ///
  /// 借鉴 Prometheus 的 sync_duration_seconds Histogram 的 start timer 模式
  void recordSyncStart() {
    _syncStartTime = DateTime.now();
    _lastSyncAttemptAt = DateTime.now();
    _currentStatus = 'syncing';
  }

  /// 记录同步成功
  ///
  /// 借鉴 Prometheus 的 Counter 指标增量模式:
  /// - sync_count++ (Counter 增量)
  /// - synced_bytes_total += bytes (Counter 增量)
  /// - sync_duration_seconds.observe(duration) (Histogram 观测)
  void recordSyncSuccess(int bytes) {
    // Counter 增量 —— 借鉴 Prometheus Counter.Inc()
    _syncCount++;
    _totalSyncedBytes += bytes;

    // 计算同步延迟
    final duration = _syncStartTime != null
        ? DateTime.now().difference(_syncStartTime!)
        : Duration.zero;
    _lastSyncDuration = duration;

    // Histogram 观测 —— 借鉴 Prometheus Histogram.Observe()
    _latencyHistogram.observe(duration);

    // 更新状态
    _lastSuccessAt = DateTime.now();
    _currentStatus = 'success';
    _consecutiveFailures = 0; // 重置连续失败计数

    _syncStartTime = null;
  }

  /// 记录同步失败
  ///
  /// 借鉴 Prometheus 的 Counter 指标和 Grafana 的错误追踪:
  /// - sync_failures_total++ (Counter 增量)
  /// - 更新连续失败计数（用于告警规则）
  void recordSyncFailure(String reason) {
    // Counter 增量 —— 借鉴 Prometheus Counter.Inc()
    _syncFailures++;

    // 计算同步延迟（即使失败也记录）
    final duration = _syncStartTime != null
        ? DateTime.now().difference(_syncStartTime!)
        : Duration.zero;
    _lastSyncDuration = duration;
    _latencyHistogram.observe(duration);

    // 更新状态
    _currentStatus = 'failure: $reason';
    _consecutiveFailures++;

    _syncStartTime = null;
  }

  /// 设置待同步变更数
  void setPendingChanges(int count) {
    _pendingChanges = count;
  }

  /// 增加待同步变更数
  void incrementPendingChanges([int count = 1]) {
    _pendingChanges += count;
  }

  /// 减少待同步变更数
  void decrementPendingChanges([int count = 1]) {
    _pendingChanges = (_pendingChanges - count).clamp(0, double.infinity).toInt();
  }

  // ==================== 告警检查 ====================

  /// 检查同步状态并发送告警
  ///
  /// 借鉴 Grafana 的 Alert Rule 评估流程:
  /// https://grafana.com/docs/grafana/latest/alerting/alerting-rules/evaluate/
  ///
  /// 评估流程:
  /// 1. 遍历所有告警规则
  /// 2. 对每条规则评估当前指标是否满足触发条件
  /// 3. 满足条件且超过冷却时间 → 触发告警
  /// 4. 调用告警回调函数
  ///
  /// 返回: 本次检查触发的告警列表
  List<SyncAlertEvent> checkAndAlert() {
    final triggeredAlerts = <SyncAlertEvent>[];

    for (final rule in _alertRules) {
      if (!_evaluateRule(rule)) continue;
      if (!rule.canFire()) continue;

      // 触发告警
      final event = SyncAlertEvent(
        ruleName: rule.name,
        severity: rule.severity,
        message: _buildAlertMessage(rule),
        timestamp: DateTime.now(),
      );

      triggeredAlerts.add(event);
      _alerts.add(event);
      rule.markFired();

      // 调用告警回调
      _onAlert?.call(event);
    }

    return triggeredAlerts;
  }

  /// 评估单条告警规则
  bool _evaluateRule(SyncAlertRule rule) {
    switch (rule.name) {
      case '高失败率告警':
        // 评估失败率是否超过阈值
        final total = _syncCount + _syncFailures;
        if (total < 5) return false; // 至少 5 次同步才评估
        final failureRate = _syncFailures / total;
        return failureRate > rule.threshold;

      case '高延迟告警':
        // 评估平均延迟是否超过阈值
        return _latencyHistogram.average.inMilliseconds > rule.threshold;

      case '连续失败告警':
        // 评估连续失败次数是否超过阈值
        return _consecutiveFailures >= rule.threshold;

      case '同步停滞告警':
        // 评估是否超过指定时间未同步
        if (_lastSuccessAt == null) return true;
        final elapsed = DateTime.now().difference(_lastSuccessAt!);
        return elapsed.inMilliseconds > rule.threshold;

      default:
        return false;
    }
  }

  /// 构建告警消息
  String _buildAlertMessage(SyncAlertRule rule) {
    switch (rule.name) {
      case '高失败率告警':
        final total = _syncCount + _syncFailures;
        final rate = total > 0 ? (_syncFailures / total * 100).toStringAsFixed(1) : '0';
        return '同步失败率 ${rate}%（总 ${total} 次，失败 ${_syncFailures} 次）';

      case '高延迟告警':
        return '平均同步延迟 ${_latencyHistogram.average.inSeconds} 秒（阈值 ${rule.threshold ~/ 1000} 秒）';

      case '连续失败告警':
        return '同步连续失败 ${_consecutiveFailures} 次（阈值 ${rule.threshold.toInt()} 次）';

      case '同步停滞告警':
        final elapsed = _lastSuccessAt != null
            ? DateTime.now().difference(_lastSuccessAt!)
            : Duration.zero;
        return '已 ${elapsed.inMinutes} 分钟未成功同步（阈值 ${(rule.threshold / 60000).toInt()} 分钟）';

      default:
        return rule.description;
    }
  }

  // ==================== 指标获取 ====================

  /// 获取当前指标快照 —— 借鉴 Prometheus 的 /metrics 端点
  SyncMetricsSnapshot getMetrics() {
    return SyncMetricsSnapshot(
      syncCount: _syncCount,
      syncFailures: _syncFailures,
      totalSyncedBytes: _totalSyncedBytes,
      pendingChanges: _pendingChanges,
      lastSyncDuration: _lastSyncDuration,
      latencyHistogram: _latencyHistogram,
      currentStatus: _currentStatus,
      timestamp: DateTime.now(),
    );
  }

  /// 获取已触发的告警列表
  List<SyncAlertEvent> get triggeredAlerts => List.unmodifiable(_alerts);

  /// 获取同步成功率
  double get successRate {
    final total = _syncCount + _syncFailures;
    if (total == 0) return 1.0;
    return _syncCount / total;
  }

  /// 获取同步频率（次/分钟） —— 借鉴 Prometheus 的 rate() 函数
  double get syncRatePerMinute {
    if (_lastSyncAttemptAt == null) return 0.0;
    final elapsed = DateTime.now().difference(_lastSyncAttemptAt!);
    if (elapsed.inMinutes == 0) return 0.0;
    return _syncCount / elapsed.inMinutes;
  }

  /// 重置所有指标 —— 用于测试或手动重置
  void reset() {
    _syncCount = 0;
    _syncFailures = 0;
    _totalSyncedBytes = 0;
    _pendingChanges = 0;
    _lastSyncDuration = Duration.zero;
    _lastSuccessAt = null;
    _lastSyncAttemptAt = null;
    _consecutiveFailures = 0;
    _currentStatus = 'idle';
    _syncStartTime = null;
    _alerts.clear();
  }

  /// 添加自定义告警规则
  void addAlertRule(SyncAlertRule rule) {
    _alertRules.add(rule);
  }

  /// 移除告警规则
  void removeAlertRule(String ruleName) {
    _alertRules.removeWhere((r) => r.name == ruleName);
  }
}
