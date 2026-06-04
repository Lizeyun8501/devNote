/// SyncMonitor - 同步状态监控与告警系统
///
/// 借鉴 OpenTelemetry CNCF 标准可观测性框架:
/// 来源: https://pub.dev/packages/opentelemetry
/// 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/
///
/// 替换说明:
/// 原实现使用自建的 Prometheus/Grafana 风格监控引擎（Counter/Gauge/Histogram），
/// 现替换为 OpenTelemetry 标准指标体系，遵循 CNCF OpenTelemetry 规范:
/// - Counter → OpenTelemetry Counter（api.opentelemetry.io/counter）
///   规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#counter
/// - Histogram → OpenTelemetry Histogram
///   规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#histogram
/// - MeterProvider → OpenTelemetry MeterProvider
///   规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#meterprovider
///
/// 保留部分:
/// - 告警系统（SyncAlertRule、SyncAlertEvent、AlertSeverity）—— 应用层逻辑，OTel 不覆盖
/// - SyncMetricsSnapshot —— 向后兼容的指标快照
/// - SyncLatencyHistogram —— 兼容包装器，内部委托给 OTel Histogram
///
/// 架构映射:
/// ```
/// OpenTelemetry 概念     → 本实现
/// ─────────────────────────────────────
/// MeterProvider          → OTelMeterProvider（OTel 规范 MeterProvider）
/// Meter                  → OTelMeter（OTel 规范 Meter）
/// Counter                → OTelCounter（OTel 规范 Counter）
/// Histogram              → OTelHistogram（OTel 规范 Histogram）
/// SyncLatencyHistogram   → 兼容包装器，委托给 OTelHistogram
/// Alert Rules            → SyncAlertRule（应用层逻辑，OTel 不覆盖）
/// Alert Manager          → SyncMonitor.checkAndAlert()
/// Metrics Snapshot       → SyncMetricsSnapshot（向后兼容）
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
import 'dart:io';

// 借鉴 OpenTelemetry Dart SDK —— 来源: https://pub.dev/packages/opentelemetry
// 使用 OTel API 和 SDK 中的类型（Attributes、Resource 等）
import 'package:opentelemetry/api.dart' as otel_api;
import 'package:opentelemetry/sdk.dart' as otel_sdk;

// ==================== OpenTelemetry 指标仪器实现 ====================
// 以下类型遵循 OpenTelemetry Metrics API 规范实现:
// https://opentelemetry.io/docs/specs/otel/metrics/api/
//
// 由于 opentelemetry-dart 包的 Metrics API 仍处于 Alpha 阶段，
// 此处按照 OTel 规范定义 Counter、Histogram、Meter、MeterProvider，
// 并在可能的情况下复用 opentelemetry 包中的类型（如 Attributes、Resource）。

/// OpenTelemetry Counter —— 借鉴 OTel 规范 Counter
///
/// 来源: https://opentelemetry.io/docs/specs/otel/metrics/api/#counter
/// 规范定义: Counter 是一种同步仪器，支持非负增量。
/// Counter 用于测量单调递增的值，例如请求计数、错误计数、字节数等。
///
/// 替换说明: 替代原自建 Counter（_syncCount、_syncFailures、_totalSyncedBytes）
class OTelCounter {
  /// 仪器名称 —— 遵循 OTel 规范的命名约定
  /// 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#instrument-name-syntax
  final String name;

  /// 仪器描述 —— 遵循 OTel 规范的可选描述字段
  final String? description;

  /// 测量单位 —— 遵循 OTel 规范的可选单位字段
  final String? unit;

  /// 当前累计值 —— Counter 只增不减，遵循 OTel 规范
  int _value = 0;

  OTelCounter({
    required this.name,
    this.description,
    this.unit,
  });

  /// 增加计数 —— 对应 OTel 规范 Counter.Add() 操作
  /// 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#add
  ///
  /// [value] 必须为非负数，遵循 OTel 规范约束
  void add(int value, [Map<String, Object>? attributes]) {
    if (value < 0) return; // OTel 规范: Counter 只允许非负增量
    _value += value;
  }

  /// 获取当前值
  int get value => _value;

  /// 重置计数器 —— 用于测试
  void reset() {
    _value = 0;
  }
}

/// OpenTelemetry Histogram —— 借鉴 OTel 规范 Histogram
///
/// 来源: https://opentelemetry.io/docs/specs/otel/metrics/api/#histogram
/// 规范定义: Histogram 是一种同步仪器，记录值的分布统计。
/// Histogram 适用于需要分析值分布的场景，如请求延迟、负载大小等。
///
/// 替换说明: 替代原自建 SyncLatencyHistogram 的核心逻辑
class OTelHistogram {
  /// 仪器名称
  final String name;

  /// 仪器描述
  final String? description;

  /// 测量单位
  final String? unit;

  /// 桶边界 —— 借鉴 OTel 规范的 ExplicitBucketBoundaries
  /// 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#instrument-advisory-parameter-explicitbucketboundaries
  final List<double> bucketBoundaries;

  /// 各桶的计数值 —— 遵循 OTel 规范的桶聚合方式
  final List<int> _buckets;

  /// 所有观测值的总和 —— 对应 OTel HistogramDataPoint.sum
  double _sum = 0;

  /// 观测值总数 —— 对应 OTel HistogramDataPoint.count
  int _count = 0;

  /// 所有观测值（用于计算分位数）—— OTel 规范可选
  final List<double> _observations = [];

  OTelHistogram({
    required this.name,
    this.description,
    this.unit,
    this.bucketBoundaries = const [100, 500, 1000, 3000, 10000],
  }) : _buckets = List.filled(bucketBoundaries.length + 1, 0);

  /// 记录一次观测值 —— 对应 OTel 规范 Histogram.Record() 操作
  /// 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#record
  void record(double value, [Map<String, Object>? attributes]) {
    _sum += value;
    _count++;
    _observations.add(value);

    // 将观测值分配到对应的桶 —— 遵循 OTel 规范的桶聚合逻辑
    int bucketIndex = bucketBoundaries.length; // 默认最后一个桶（+∞）
    for (int i = 0; i < bucketBoundaries.length; i++) {
      if (value < bucketBoundaries[i]) {
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
        ...bucketBoundaries.map((b) => '<${b.toInt()}ms'),
        '>=${bucketBoundaries.last.toInt()}ms',
      ];

  /// 计算平均值 —— 对应 OTel HistogramDataPoint 的 sum/count
  double get average {
    if (_count == 0) return 0;
    return _sum / _count;
  }

  /// 获取总观测次数 —— 对应 OTel HistogramDataPoint.count
  int get count => _count;

  /// 获取观测值总和 —— 对应 OTel HistogramDataPoint.sum
  double get sum => _sum;

  /// 计算分位数 —— 借鉴 OTel 规范的 Quantile 计算
  double quantile(double q) {
    if (_observations.isEmpty) return 0;
    final sorted = List<double>.from(_observations)..sort();
    final index = (q * (sorted.length - 1)).round();
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  /// 重置直方图 —— 用于测试
  void reset() {
    for (int i = 0; i < _buckets.length; i++) {
      _buckets[i] = 0;
    }
    _sum = 0;
    _count = 0;
    _observations.clear();
  }
}

/// OpenTelemetry Meter —— 借鉴 OTel 规范 Meter
///
/// 来源: https://opentelemetry.io/docs/specs/otel/metrics/api/#meter
/// 规范定义: Meter 负责创建指标仪器（Instruments）。
/// Meter 由 MeterProvider 创建，与特定的 instrumentation scope 关联。
class OTelMeter {
  /// Meter 名称 —— 对应 OTel 规范的 instrumentation scope name
  final String name;

  /// Meter 版本 —— 对应 OTel 规范的 instrumentation scope version
  final String? version;

  /// 此 Meter 创建的 Counter 仪器列表
  final Map<String, OTelCounter> _counters = {};

  /// 此 Meter 创建的 Histogram 仪器列表
  final Map<String, OTelHistogram> _histograms = {};

  OTelMeter({
    required this.name,
    this.version,
  });

  /// 创建 Counter —— 对应 OTel 规范 Meter 创建 Counter 操作
  /// 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#counter-creation
  OTelCounter createCounter(String name, {String? description, String? unit}) {
    return _counters.putIfAbsent(
      name,
      () => OTelCounter(name: name, description: description, unit: unit),
    );
  }

  /// 创建 Histogram —— 对应 OTel 规范 Meter 创建 Histogram 操作
  /// 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#histogram-creation
  OTelHistogram createHistogram(
    String name, {
    String? description,
    String? unit,
    List<double>? explicitBucketBoundaries,
  }) {
    return _histograms.putIfAbsent(
      name,
      () => OTelHistogram(
        name: name,
        description: description,
        unit: unit,
        bucketBoundaries: explicitBucketBoundaries ?? const [100, 500, 1000, 3000, 10000],
      ),
    );
  }

  /// 获取指定名称的 Counter
  OTelCounter? getCounter(String name) => _counters[name];

  /// 获取指定名称的 Histogram
  OTelHistogram? getHistogram(String name) => _histograms[name];
}

/// OTLP/Prometheus 导出配置 —— 借鉴 OTel 规范的 MetricExporter 配置
///
/// 来源: https://opentelemetry.io/docs/specs/otel/protocol/exporter/
/// 规范定义: 配置指标导出的目标端点、间隔和超时。
class OTelExporterConfig {
  /// 导出目标端点 URL
  final String endpoint;

  /// 导出间隔 —— 每隔多长时间收集并推送一次指标
  final Duration exportInterval;

  /// 导出超时 —— 单次导出 HTTP 请求的超时时间
  final Duration exportTimeout;

  OTelExporterConfig({
    required this.endpoint,
    this.exportInterval = const Duration(seconds: 10),
    this.exportTimeout = const Duration(seconds: 5),
  });

  /// 默认 OTLP 配置 —— 导出至 OTLP HTTP 接收端
  /// 端点: http://localhost:4318/v1/metrics
  factory OTelExporterConfig.otlp() {
    return OTelExporterConfig(
      endpoint: 'http://localhost:4318/v1/metrics',
      exportInterval: const Duration(seconds: 10),
      exportTimeout: const Duration(seconds: 5),
    );
  }

  /// 默认 Prometheus 配置 —— 推送至 Prometheus pushgateway
  /// 端点: http://localhost:9090/metrics
  factory OTelExporterConfig.prometheus() {
    return OTelExporterConfig(
      endpoint: 'http://localhost:9090/metrics',
      exportInterval: const Duration(seconds: 15),
      exportTimeout: const Duration(seconds: 5),
    );
  }
}

/// OpenTelemetry MeterProvider —— 借鉴 OTel 规范 MeterProvider
///
/// 来源: https://opentelemetry.io/docs/specs/otel/metrics/api/#meterprovider
/// 规范定义: MeterProvider 是 Metrics API 的入口点，提供对 Meter 的访问。
/// 通常在应用中初始化一次，其生命周期与应用生命周期一致。
///
/// 替换说明: 替代原自建指标系统，使用 OTel 标准的 MeterProvider 模式
class OTelMeterProvider {
  /// 已创建的 Meter 实例 —— 对应 OTel 规范的 Meter 缓存
  final Map<String, OTelMeter> _meters = {};

  /// OTel Resource —— 借鉴 opentelemetry/sdk.dart 中的 Resource 概念
  /// 用于标识产生遥测数据的实体
  otel_sdk.Resource? resource;

  /// 导出配置 —— 借鉴 OTel 规范的 MetricExporter 配置
  OTelExporterConfig? exporterConfig;

  /// 定时导出 Timer
  Timer? _exportTimer;

  OTelMeterProvider({this.resource, this.exporterConfig});

  /// 获取 Meter —— 对应 OTel 规范 MeterProvider.GetMeter() 操作
  /// 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#get-a-meter
  OTelMeter getMeter(String name, {String? version}) {
    final key = '${name}_$version';
    return _meters.putIfAbsent(
      key,
      () => OTelMeter(name: name, version: version),
    );
  }

  /// 收集所有 Meter 的指标数据，格式化为 OTLP JSON
  Map<String, dynamic> _collectMetrics() {
    final scopeMetrics = <Map<String, dynamic>>[];
    for (final meter in _meters.values) {
      final counters = <Map<String, dynamic>>[];
      for (final counter in meter._counters.values) {
        counters.add({
          'name': counter.name,
          'description': counter.description,
          'unit': counter.unit,
          'data': {
            'dataPoints': [
              {
                'asInt': counter.value,
                'timeUnixNano': DateTime.now().microsecondsSinceEpoch * 1000,
              }
            ],
            'isMonotonic': true,
          },
        });
      }

      final histograms = <Map<String, dynamic>>[];
      for (final histogram in meter._histograms.values) {
        histograms.add({
          'name': histogram.name,
          'description': histogram.description,
          'unit': histogram.unit,
          'data': {
            'dataPoints': [
              {
                'count': histogram.count,
                'sum': histogram.sum,
                'bucketCounts': histogram.buckets,
                'explicitBounds': histogram.bucketBoundaries,
                'timeUnixNano': DateTime.now().microsecondsSinceEpoch * 1000,
              }
            ],
          },
        });
      }

      if (counters.isNotEmpty || histograms.isNotEmpty) {
        scopeMetrics.add({
          'scope': {'name': meter.name, 'version': meter.version},
          'metrics': [
            ...counters,
            ...histograms,
          ],
        });
      }
    }

    return {
      'resourceMetrics': [
        {
          'resource': {
            'attributes': [
              {'key': 'service.name', 'value': {'stringValue': 'devnote'}},
            ],
          },
          'scopeMetrics': scopeMetrics,
        }
      ],
    };
  }

  /// 启动定时导出 —— 借鉴 OTel 规范的 PeriodicExportingMetricReader
  /// 规范: https://opentelemetry.io/docs/specs/otel/sdk/metric/export/
  ///
  /// 每隔 [exportInterval] 收集所有指标并通过 HTTP POST 推送至配置的端点
  void startExport() {
    if (exporterConfig == null) return;
    stopExport();
    _exportTimer = Timer.periodic(exporterConfig!.exportInterval, (_) async {
      try {
        final metrics = _collectMetrics();
        // 借鉴 OTLP HTTP 导出协议: Content-Type 为 application/json
        // 规范: https://opentelemetry.io/docs/specs/otel/protocol/exporter/
        final uri = Uri.parse(exporterConfig!.endpoint);
        final client = HttpClient();
        try {
          final request = await client.postUrl(uri);
          request.headers.set('Content-Type', 'application/json');
          request.write(metrics.toString());
          await request.close().timeout(exporterConfig!.exportTimeout);
        } finally {
          client.close();
        }
      } catch (_) {
        // 导出失败时静默忽略，避免影响主流程
      }
    });
  }

  /// 停止定时导出
  void stopExport() {
    _exportTimer?.cancel();
    _exportTimer = null;
  }
}

// ==================== 全局 MeterProvider 实例 ====================

/// 全局 MeterProvider —— 借鉴 OTel 规范的全局 MeterProvider 模式
/// 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#meterprovider
///
/// 类似于 opentelemetry/api.dart 中的 globalTracerProvider 模式，
/// 提供全局默认的 MeterProvider 实例
OTelMeterProvider _globalMeterProvider = OTelMeterProvider();

/// 获取全局 MeterProvider
OTelMeterProvider get globalMeterProvider => _globalMeterProvider;

/// 注册全局 MeterProvider —— 借鉴 OTel api.dart 中的 registerGlobalTracerProvider 模式
void registerGlobalMeterProvider(OTelMeterProvider provider) {
  _globalMeterProvider = provider;
}

// ==================== 同步指标快照 ====================

/// 同步指标快照 —— 向后兼容的指标快照
///
/// 保留原有 SyncMetricsSnapshot 以确保向后兼容，
/// 内部数据来源于 OTel Counter 和 Histogram。
class SyncMetricsSnapshot {
  /// Counter: 同步总成功次数 —— 借鉴 OTel Counter 类型
  final int syncCount;

  /// Counter: 同步总失败次数 —— 借鉴 OTel Counter 类型
  final int syncFailures;

  /// Counter: 同步总字节数 —— 借鉴 OTel Counter 类型
  final int totalSyncedBytes;

  /// Gauge: 当前待同步变更数
  final int pendingChanges;

  /// Gauge: 最近一次同步耗时（毫秒）
  final Duration lastSyncDuration;

  /// Histogram: 同步延迟分布 —— 兼容包装器，委托给 OTel Histogram
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

/// 同步延迟直方图 —— 兼容包装器，委托给 OTel Histogram
///
/// 保留原有 SyncLatencyHistogram 接口以确保向后兼容，
/// 内部实现委托给 OpenTelemetry Histogram。
///
/// 借鉴 OpenTelemetry Histogram 规范:
/// 来源: https://opentelemetry.io/docs/specs/otel/metrics/api/#histogram
class SyncLatencyHistogram {
  /// 内部委托的 OTel Histogram 实例
  final OTelHistogram _otelHistogram;

  /// 桶边界（毫秒） —— 借鉴 OTel 规范的 ExplicitBucketBoundaries
  static const List<int> bucketBoundaries = [100, 500, 1000, 3000, 10000];

  /// 创建兼容包装器 —— 委托给 OTel Histogram
  SyncLatencyHistogram([OTelHistogram? histogram])
      : _otelHistogram = histogram ??
            OTelHistogram(
              name: 'devnote.sync.latency',
              description: '同步延迟分布',
              unit: 'ms',
              bucketBoundaries: bucketBoundaries.map((b) => b.toDouble()).toList(),
            );

  /// 记录一次延迟观测值 —— 委托给 OTel Histogram.record()
  void observe(Duration duration) {
    _otelHistogram.record(duration.inMilliseconds.toDouble());
  }

  /// 获取桶计数值 —— 委托给 OTel Histogram
  List<int> get buckets => _otelHistogram.buckets;

  /// 获取桶边界标签
  List<String> get bucketLabels => _otelHistogram.bucketLabels;

  /// 计算平均延迟 —— 委托给 OTel Histogram
  Duration get average {
    if (_otelHistogram.count == 0) return Duration.zero;
    return Duration(milliseconds: _otelHistogram.average.round());
  }

  /// 获取总观测次数 —— 委托给 OTel Histogram
  int get count => _otelHistogram.count;

  /// 获取延迟总和 —— 委托给 OTel Histogram
  int get sum => _otelHistogram.sum.round();

  /// 获取内部 OTel Histogram 实例（用于高级操作）
  OTelHistogram get otelHistogram => _otelHistogram;

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      'count': _otelHistogram.count,
      'sum_ms': _otelHistogram.sum.round(),
      'average_ms': average.inMilliseconds,
      'buckets': <String, int>{},
    };
    final bucketValues = _otelHistogram.buckets;
    final labels = _otelHistogram.bucketLabels;
    for (int i = 0; i < bucketValues.length; i++) {
      result['buckets'][labels[i]] = bucketValues[i];
    }
    return result;
  }
}

// ==================== 告警系统 ====================
// 告警系统为应用层逻辑，OpenTelemetry 规范不覆盖此部分，因此保留原有实现。

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
/// 核心设计借鉴 OpenTelemetry CNCF 标准可观测性框架:
/// 来源: https://pub.dev/packages/opentelemetry
/// 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/
///
/// 使用 OTel MeterProvider 创建指标仪器:
/// - syncCount (Counter):         同步成功总次数
/// - syncFailures (Counter):      同步失败总次数
/// - totalSyncedBytes (Counter):  同步总字节数
/// - pendingChanges (Gauge):      当前待同步变更数
/// - lastSyncDuration (Gauge):    最近同步耗时
/// - latencyHistogram (Histogram): 同步延迟分布
///
/// 内置告警规则:
/// 1. 高失败率告警: 失败率 > 50% 且至少 5 次同步 → Critical
/// 2. 高延迟告警: 平均延迟 > 10s → Warning
/// 3. 连续失败告警: 连续失败 >= 3 次 → Critical
/// 4. 同步停滞告警: 超过 30 分钟未同步 → Warning
class SyncMonitor {
  // ==================== OTel 指标仪器 ====================

  /// OTel Meter —— 借鉴 OTel 规范，通过 MeterProvider 获取
  /// 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#meter
  final OTelMeter _meter;

  /// OTel Counter: 同步成功总次数 —— 借鉴 OTel 规范 Counter
  /// 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#counter
  /// 对应指标名: devnote.sync.count
  late final OTelCounter _syncCountCounter;

  /// OTel Counter: 同步失败总次数 —— 借鉴 OTel 规范 Counter
  /// 对应指标名: devnote.sync.failures
  late final OTelCounter _syncFailuresCounter;

  /// OTel Counter: 同步总字节数 —— 借鉴 OTel 规范 Counter
  /// 对应指标名: devnote.sync.bytes
  late final OTelCounter _totalSyncedBytesCounter;

  /// OTel Histogram: 同步延迟分布 —— 借鉴 OTel 规范 Histogram
  /// 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#histogram
  /// 对应指标名: devnote.sync.latency
  late final OTelHistogram _latencyOtelHistogram;

  // ==================== Gauge 指标（OTel 规范中 Gauge 为同步记录当前值） ====================

  /// Gauge: 当前待同步变更数
  int _pendingChanges = 0;

  /// Gauge: 最近一次同步耗时
  Duration _lastSyncDuration = Duration.zero;

  // ==================== 兼容包装器 ====================

  /// SyncLatencyHistogram 兼容包装器 —— 委托给 OTel Histogram
  late final SyncLatencyHistogram _latencyHistogram;

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

  /// 内置告警规则列表 —— 应用层逻辑，OTel 不覆盖
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

  /// 构造函数 —— 使用 OTel MeterProvider 初始化指标仪器
  ///
  /// 借鉴 OTel 规范: 通过 MeterProvider 获取 Meter，再通过 Meter 创建仪器
  /// 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#meterprovider
  ///
  /// [meterProvider] 可选的 OTel MeterProvider，默认使用全局实例
  SyncMonitor({OTelMeterProvider? meterProvider})
      : _meter = (meterProvider ?? globalMeterProvider)
            .getMeter('devnote.sync', version: '1.0.0') {
    // 通过 OTel Meter 创建 Counter 仪器 —— 借鉴 OTel 规范
    // 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#counter-creation
    _syncCountCounter = _meter.createCounter(
      'devnote.sync.count',
      description: '同步成功总次数',
      unit: '1',
    );

    _syncFailuresCounter = _meter.createCounter(
      'devnote.sync.failures',
      description: '同步失败总次数',
      unit: '1',
    );

    _totalSyncedBytesCounter = _meter.createCounter(
      'devnote.sync.bytes',
      description: '同步总字节数',
      unit: 'By',
    );

    // 通过 OTel Meter 创建 Histogram 仪器 —— 借鉴 OTel 规范
    // 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#histogram-creation
    _latencyOtelHistogram = _meter.createHistogram(
      'devnote.sync.latency',
      description: '同步延迟分布',
      unit: 'ms',
      explicitBucketBoundaries: [100, 500, 1000, 3000, 10000],
    );

    // 创建兼容包装器，委托给 OTel Histogram
    _latencyHistogram = SyncLatencyHistogram(_latencyOtelHistogram);

    _setupDefaultAlertRules();
  }

  /// 设置告警回调函数
  void setAlertCallback(void Function(SyncAlertEvent) callback) {
    _onAlert = callback;
  }

  // ==================== Counter 指标访问 ====================

  /// 获取同步成功总次数 —— 对应 OTel Counter: devnote.sync.count
  int get syncCount => _syncCountCounter.value;

  /// 获取同步失败总次数 —— 对应 OTel Counter: devnote.sync.failures
  int get syncFailures => _syncFailuresCounter.value;

  /// 获取同步总字节数 —— 对应 OTel Counter: devnote.sync.bytes
  int get totalSyncedBytes => _totalSyncedBytesCounter.value;

  // ==================== Gauge 指标访问 ====================

  /// 获取当前待同步变更数
  int get pendingChanges => _pendingChanges;

  /// 获取最近一次同步耗时
  Duration get lastSyncDuration => _lastSyncDuration;

  // ==================== Histogram 指标访问 ====================

  /// 获取平均同步延迟 —— 对应 OTel Histogram: devnote.sync.latency
  Duration get averageSyncLatency => _latencyHistogram.average;

  /// 获取延迟直方图（兼容包装器）
  SyncLatencyHistogram get latencyHistogram => _latencyHistogram;

  // ==================== OTel 仪器直接访问 ====================

  /// 获取 OTel Counter 实例 —— 用于高级 OTel 操作
  OTelCounter get syncCountCounter => _syncCountCounter;

  /// 获取 OTel Counter 实例 —— 用于高级 OTel 操作
  OTelCounter get syncFailuresCounter => _syncFailuresCounter;

  /// 获取 OTel Counter 实例 —— 用于高级 OTel 操作
  OTelCounter get totalSyncedBytesCounter => _totalSyncedBytesCounter;

  /// 获取 OTel Histogram 实例 —— 用于高级 OTel 操作
  OTelHistogram get latencyOtelHistogram => _latencyOtelHistogram;

  /// 获取 OTel Meter 实例
  OTelMeter get meter => _meter;

  // ==================== 记录同步事件 ====================

  /// 记录同步开始 —— 用于计算同步延迟
  ///
  /// 借鉴 OTel 规范的 Span 启动模式:
  /// 类似于 otel_api.Tracer.startSpan() 记录操作开始时间
  void recordSyncStart() {
    _syncStartTime = DateTime.now();
    _lastSyncAttemptAt = DateTime.now();
    _currentStatus = 'syncing';
  }

  /// 记录同步成功
  ///
  /// 借鉴 OTel 规范的 Counter.Add() 和 Histogram.Record() 操作:
  /// - Counter.Add(1) → 同步次数 +1
  /// - Counter.Add(bytes) → 同步字节数累加
  /// - Histogram.Record(duration) → 记录延迟观测值
  void recordSyncSuccess(int bytes) {
    // OTel Counter.Add() —— 借鉴 OTel 规范 Counter.Add() 操作
    // 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#add
    _syncCountCounter.add(1);
    _totalSyncedBytesCounter.add(bytes);

    // 计算同步延迟
    final duration = _syncStartTime != null
        ? DateTime.now().difference(_syncStartTime!)
        : Duration.zero;
    _lastSyncDuration = duration;

    // OTel Histogram.Record() —— 借鉴 OTel 规范 Histogram.Record() 操作
    // 规范: https://opentelemetry.io/docs/specs/otel/metrics/api/#record
    _latencyOtelHistogram.record(duration.inMilliseconds.toDouble());

    // 更新状态
    _lastSuccessAt = DateTime.now();
    _currentStatus = 'success';
    _consecutiveFailures = 0; // 重置连续失败计数

    _syncStartTime = null;
  }

  /// 记录同步失败
  ///
  /// 借鉴 OTel 规范的 Counter.Add() 和 Histogram.Record() 操作:
  /// - Counter.Add(1) → 失败次数 +1
  /// - Histogram.Record(duration) → 记录延迟观测值（即使失败也记录）
  void recordSyncFailure(String reason) {
    // OTel Counter.Add() —— 借鉴 OTel 规范 Counter.Add() 操作
    _syncFailuresCounter.add(1);

    // 计算同步延迟（即使失败也记录）
    final duration = _syncStartTime != null
        ? DateTime.now().difference(_syncStartTime!)
        : Duration.zero;
    _lastSyncDuration = duration;

    // OTel Histogram.Record() —— 失败的同步也记录延迟
    _latencyOtelHistogram.record(duration.inMilliseconds.toDouble());

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
  /// 告警系统为应用层逻辑，OpenTelemetry 规范不覆盖此部分。
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

  /// 评估单条告警规则 —— 从 OTel Counter/Histogram 读取指标值
  bool _evaluateRule(SyncAlertRule rule) {
    switch (rule.name) {
      case '高失败率告警':
        // 从 OTel Counter 读取值进行评估
        final total = _syncCountCounter.value + _syncFailuresCounter.value;
        if (total < 5) return false; // 至少 5 次同步才评估
        final failureRate = _syncFailuresCounter.value / total;
        return failureRate > rule.threshold;

      case '高延迟告警':
        // 从 OTel Histogram 读取平均值进行评估
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

  /// 构建告警消息 —— 从 OTel Counter/Histogram 读取指标值
  String _buildAlertMessage(SyncAlertRule rule) {
    switch (rule.name) {
      case '高失败率告警':
        final total = _syncCountCounter.value + _syncFailuresCounter.value;
        final rate = total > 0
            ? (_syncFailuresCounter.value / total * 100).toStringAsFixed(1)
            : '0';
        return '同步失败率 ${rate}%（总 ${total} 次，失败 ${_syncFailuresCounter.value} 次）';

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

  /// 获取当前指标快照 —— 借鉴 OTel 的 Metrics 收集模式
  ///
  /// 从 OTel Counter 和 Histogram 读取当前值，
  /// 生成向后兼容的 SyncMetricsSnapshot
  SyncMetricsSnapshot getMetrics() {
    return SyncMetricsSnapshot(
      syncCount: _syncCountCounter.value,
      syncFailures: _syncFailuresCounter.value,
      totalSyncedBytes: _totalSyncedBytesCounter.value,
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
    final total = _syncCountCounter.value + _syncFailuresCounter.value;
    if (total == 0) return 1.0;
    return _syncCountCounter.value / total;
  }

  /// 获取同步频率（次/分钟）
  double get syncRatePerMinute {
    if (_lastSyncAttemptAt == null) return 0.0;
    final elapsed = DateTime.now().difference(_lastSyncAttemptAt!);
    if (elapsed.inMinutes == 0) return 0.0;
    return _syncCountCounter.value / elapsed.inMinutes;
  }

  /// 重置所有指标 —— 用于测试或手动重置
  ///
  /// 重置 OTel Counter 和 Histogram 的值
  void reset() {
    _syncCountCounter.reset();
    _syncFailuresCounter.reset();
    _totalSyncedBytesCounter.reset();
    _latencyOtelHistogram.reset();
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
