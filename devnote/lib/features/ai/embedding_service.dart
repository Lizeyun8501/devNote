// 文本向量化服务
//
// 借鉴 Obsidian Hybrid Retrieval 的向量化策略：
// 使用 nomic-embed-text 模型将笔记文本转为稠密向量，
// 配合 LRU 缓存避免对相同文本重复计算。
//
// 来源: https://github.com/obsidianmd/obsidian-clipper

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:devnote/features/ai/ollama_client.dart';
import 'package:devnote/core/observability/app_logger.dart';

/// 向量化服务
///
/// 设计要点：
/// 1. LRU 缓存：基于 LinkedHashMap 实现，容量上限 [_maxCacheSize]
/// 2. 批量向量化：串行调用 Ollama，避免并发请求压垮本地推理
/// 3. 文本预处理：截断超长文本，避免超出模型上下文窗口
class EmbeddingService {
  EmbeddingService({
    required OllamaClient ollamaClient,
    String embeddingModel = 'nomic-embed-text',
    int maxCacheSize = 512,
    int maxTextLength = 4000,
  })  : _ollama = ollamaClient,
        _embeddingModel = embeddingModel,
        _maxCacheSize = maxCacheSize,
        _maxTextLength = maxTextLength;

  final OllamaClient _ollama;
  String _embeddingModel;
  final int _maxCacheSize;
  final int _maxTextLength;

  /// LRU 缓存：key 为文本哈希，value 为向量
  ///
  /// LinkedHashMap 在访问/插入时按顺序保留，删除头部即淘汰最久未使用项。
  final LinkedHashMap<String, List<double>> _cache =
      LinkedHashMap<String, List<double>>();

  /// 当前嵌入模型名称
  String get embeddingModel => _embeddingModel;

  /// 动态切换嵌入模型（由设置页调用），同时清空缓存
  set embeddingModel(String value) {
    if (value.trim().isNotEmpty && value != _embeddingModel) {
      _embeddingModel = value.trim();
      _cache.clear();
    }
  }

  /// 单文本向量化
  ///
  /// 命中缓存时直接返回；否则调用 Ollama 计算并写入缓存。
  Future<List<double>> embed(String text) async {
    final normalized = _normalize(text);
    if (normalized.isEmpty) return const [];
    final key = _cacheKey(normalized);
    final cached = _cache[key];
    if (cached != null) {
      // 命中缓存：移动到末尾（LRU 最近使用）
      _cache.remove(key);
      _cache[key] = cached;
      return cached;
    }
    try {
      final vec = await _ollama.embed(
        text: normalized,
        model: _embeddingModel,
      );
      _putCache(key, vec);
      return vec;
    } catch (e) {
      AppLogger.w('EmbeddingService', '向量化失败', error: e);
      rethrow;
    }
  }

  /// 批量向量化
  ///
  /// 串行调用 [embed]，避免并发请求压垮本地 Ollama 推理。
  /// 任一条目失败时返回空向量，不影响其他条目。
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    final results = <List<double>>[];
    for (final text in texts) {
      try {
        final vec = await embed(text);
        results.add(vec);
      } catch (_) {
        results.add(const []);
      }
    }
    return results;
  }

  /// 计算两个向量的余弦相似度
  ///
  /// 返回值范围 [-1, 1]，越接近 1 越相似。
  /// 任一向量为空或维度不一致时返回 0。
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0.0;
    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }

  // ---------- 内部工具 ----------

  /// 文本预处理：去除多余空白并截断
  String _normalize(String text) {
    final trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.length <= _maxTextLength) return trimmed;
    return trimmed.substring(0, _maxTextLength);
  }

  /// 缓存键：使用简单哈希避免长文本作为 key
  String _cacheKey(String text) {
    final hashCode = text.hashCode;
    return '$hashCode:${text.length}';
  }

  /// 写入缓存并执行 LRU 淘汰
  void _putCache(String key, List<double> vec) {
    _cache[key] = vec;
    while (_cache.length > _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// 清空缓存
  void clearCache() {
    _cache.clear();
  }

  /// 将向量列表序列化为 JSON 字符串（用于持久化到 SharedPreferences）
  static String encodeVectors(Map<String, List<double>> vectors) {
    final map = vectors.map(
      (k, v) => MapEntry(k, v),
    );
    return jsonEncode(map);
  }

  /// 从 JSON 字符串反序列化向量
  static Map<String, List<double>> decodeVectors(String json) {
    if (json.isEmpty) return {};
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      return data.map(
        (k, v) => MapEntry(
          k,
          (v as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
        ),
      );
    } catch (_) {
      return {};
    }
  }
}
