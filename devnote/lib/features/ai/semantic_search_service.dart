// 语义搜索服务 —— Hybrid Retrieval 实现
//
// 借鉴 Obsidian Hybrid Retrieval 方案：BM25 关键词检索 + 向量语义检索 + RRF 融合
// 来源: https://github.com/obsidianmd/obsidian-clipper
//
// 检索流程：
// 1. FTS5 关键词检索（复用 DatabaseHelper.searchNotesFTS）→ BM25 排序
// 2. 向量语义检索（查询向量与笔记向量余弦相似度排序）
// 3. RRF（Reciprocal Rank Fusion）融合两路结果
//    公式: score = sum(1 / (k + rank_i))，k=60
//
// 向量存储：采用简单方案，向量以 JSON 形式持久化到 SharedPreferences
// （key 为 noteId，value 为向量列表）。进阶方案可改用 SQLite BLOB。

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:devnote/core/observability/app_logger.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/core/persistence/models/note_model.dart';
import 'package:devnote/features/ai/embedding_service.dart';
import 'package:devnote/features/ai/search_result.dart';
import 'package:devnote/features/search/search_service.dart' show HighlightModel;

/// 语义搜索服务
///
/// 重要约束：
/// 1. 不破坏现有 FTS5 搜索，语义搜索作为增强选项
/// 2. AI 未启用时降级为纯关键词检索
/// 3. 向量索引失败时降级为关键词检索，不抛异常
class SemanticSearchService {
  SemanticSearchService({
    required DatabaseHelper databaseHelper,
    required EmbeddingService embeddingService,
  })  : _db = databaseHelper,
        _embedding = embeddingService;

  final DatabaseHelper _db;
  final EmbeddingService _embedding;

  /// 向量索引持久化 key
  static const String _kVectorIndexKey = 'ai.vector_index';
  /// 向量版本号 key（嵌入模型变更时用于失效旧向量）
  static const String _kVectorModelKey = 'ai.vector_model';

  /// 内存中的向量索引：noteId -> 向量
  ///
  /// 首次访问时从 SharedPreferences 加载，索引笔记时更新并落盘。
  Map<String, List<double>> _vectors = {};
  bool _loaded = false;

  /// RRF 融合参数 k（标准值 60）
  static const int _rrfK = 60;

  /// 加载持久化的向量索引
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedModel = prefs.getString(_kVectorModelKey) ?? '';
      // 嵌入模型变更时清空旧向量，避免维度不一致
      if (storedModel.isNotEmpty && storedModel != _embedding.embeddingModel) {
        await prefs.remove(_kVectorIndexKey);
        await prefs.setString(_kVectorModelKey, _embedding.embeddingModel);
        _vectors = {};
      } else {
        final json = prefs.getString(_kVectorIndexKey) ?? '';
        _vectors = EmbeddingService.decodeVectors(json);
        if (storedModel.isEmpty) {
          await prefs.setString(_kVectorModelKey, _embedding.embeddingModel);
        }
      }
    } catch (e) {
      AppLogger.w('SemanticSearchService', '加载向量索引失败', error: e);
      _vectors = {};
    }
    _loaded = true;
  }

  /// 持久化向量索引
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kVectorIndexKey,
        EmbeddingService.encodeVectors(_vectors),
      );
      await prefs.setString(_kVectorModelKey, _embedding.embeddingModel);
    } catch (e) {
      AppLogger.w('SemanticSearchService', '持久化向量索引失败', error: e);
    }
  }

  /// 索引单条笔记（计算并存储向量）
  ///
  /// 笔记内容为空时跳过；计算失败时记录日志但不抛异常。
  Future<void> indexNote(NoteModel note) async {
    await _ensureLoaded();
    final text = _noteText(note);
    if (text.trim().isEmpty) {
      _vectors.remove(note.id);
      await _persist();
      return;
    }
    try {
      final vec = await _embedding.embed(text);
      if (vec.isNotEmpty) {
        _vectors[note.id] = vec;
        await _persist();
      }
    } catch (e) {
      AppLogger.w(
        'SemanticSearchService',
        '索引笔记失败: ${note.id}',
        error: e,
      );
    }
  }

  /// 重建所有笔记索引
  ///
  /// 从数据库读取全部笔记，逐条计算向量并落盘。
  /// 返回成功索引的笔记数量。
  Future<int> reindexAll() async {
    await _ensureLoaded();
    _vectors.clear();
    try {
      final db = await _db.database;
      final rows = await db.query('notes');
      var count = 0;
      for (final row in rows) {
        try {
          final note = NoteModel.fromJson(row);
          final text = _noteText(note);
          if (text.trim().isEmpty) continue;
          final vec = await _embedding.embed(text);
          if (vec.isNotEmpty) {
            _vectors[note.id] = vec;
            count++;
          }
        } catch (_) {
          // 单条失败时跳过，继续处理其他笔记
          continue;
        }
      }
      await _persist();
      AppLogger.i('SemanticSearchService', '重建索引完成: $count 条笔记');
      return count;
    } catch (e) {
      AppLogger.e('SemanticSearchService', '重建索引失败', error: e);
      return 0;
    }
  }

  /// 语义搜索
  ///
  /// [hybrid] 为 true 时使用 Hybrid Retrieval（BM25 + 向量 + RRF）；
  /// 为 false 时仅使用向量语义检索。
  /// AI 未启用或向量索引为空时降级为纯关键词检索。
  Future<List<SearchResult>> search({
    required String query,
    int limit = 10,
    bool hybrid = true,
  }) async {
    if (query.trim().isEmpty) return const [];
    await _ensureLoaded();

    // 关键词检索（FTS5 + BM25）
    final keywordResults = await _keywordSearch(query, limit: limit * 2);

    // 向量检索
    final semanticResults = await _semanticSearch(query, limit: limit * 2);

    // 降级：无向量结果时直接返回关键词结果
    if (semanticResults.isEmpty) {
      return keywordResults.take(limit).toList();
    }

    // 降级：无关键词结果时直接返回向量结果
    if (keywordResults.isEmpty) {
      return semanticResults.take(limit).toList();
    }

    if (!hybrid) {
      return semanticResults.take(limit).toList();
    }

    // RRF 融合
    return _rrfFusion(keywordResults, semanticResults, limit: limit);
  }

  /// 仅关键词检索是否可用（不依赖 AI）
  ///
  /// 供 SearchBloc 判断是否启用语义搜索增强。
  Future<bool> isSemanticReady() async {
    await _ensureLoaded();
    return _vectors.isNotEmpty;
  }

  // ---------- 检索子流程 ----------

  /// FTS5 关键词检索
  ///
  /// 复用 DatabaseHelper.searchNotesFTS，返回带 BM25 排序的结果。
  Future<List<SearchResult>> _keywordSearch(
    String query, {
    required int limit,
  }) async {
    try {
      final rows = await _db.searchNotesFTS(query, limit: limit);
      final results = <SearchResult>[];
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final noteId = row['id'] as String? ?? '';
        final title = row['title'] as String? ?? '';
        final content = row['content'] as String? ?? '';
        // FTS5 按 rank 排序，rank 越小越相关；归一化为 0~1 的分数
        final rank = (row['rank'] as num?)?.toDouble() ?? 0.0;
        final score = _normalizeBm25(rank);
        results.add(SearchResult(
          noteId: noteId,
          title: title,
          snippet: _snippet(content, query),
          score: score,
          source: SearchResultSource.keyword,
          keywordScore: score,
          highlights: _buildHighlights(content, query),
        ));
      }
      return results;
    } catch (e) {
      AppLogger.w('SemanticSearchService', '关键词检索失败', error: e);
      return const [];
    }
  }

  /// 向量语义检索
  ///
  /// 计算查询向量与所有笔记向量的余弦相似度，按相似度降序返回。
  Future<List<SearchResult>> _semanticSearch(
    String query, {
    required int limit,
  }) async {
    if (_vectors.isEmpty) return const [];
    try {
      final queryVec = await _embedding.embed(query);
      if (queryVec.isEmpty) return const [];

      // 计算相似度并排序
      final scored = <MapEntry<String, double>>[];
      _vectors.forEach((noteId, vec) {
        final sim = EmbeddingService.cosineSimilarity(queryVec, vec);
        scored.add(MapEntry(noteId, sim));
      });
      scored.sort((a, b) => b.value.compareTo(a.value));

      // 取 top-N 并加载笔记内容
      final top = scored.take(limit).toList();
      final results = <SearchResult>[];
      for (final entry in top) {
        if (entry.value <= 0.0) continue;
        final note = await _loadNote(entry.key);
        if (note == null) continue;
        results.add(SearchResult(
          noteId: note.id,
          title: note.title,
          snippet: _snippet(note.content, query),
          score: entry.value,
          source: SearchResultSource.semantic,
          semanticScore: entry.value,
        ));
      }
      return results;
    } catch (e) {
      AppLogger.w('SemanticSearchService', '向量检索失败', error: e);
      return const [];
    }
  }

  /// RRF（Reciprocal Rank Fusion）融合
  ///
  /// 公式: score = sum(1 / (k + rank_i))，k=60
  /// 对每条结果按其在各路检索中的排名计算 RRF 分数，再归一化到 0~1。
  List<SearchResult> _rrfFusion(
    List<SearchResult> keywordResults,
    List<SearchResult> semanticResults, {
    required int limit,
  }) {
    // noteId -> 融合信息
    final fused = <String, _FusedEntry>{};

    for (var i = 0; i < keywordResults.length; i++) {
      final r = keywordResults[i];
      final entry = fused.putIfAbsent(r.noteId, () => _FusedEntry(r));
      entry.rrfScore += 1.0 / (_rrfK + i + 1);
      entry.keywordScore ??= r.keywordScore;
      // 保留关键词命中片段与高亮
      if (r.highlights.isNotEmpty) entry.highlights = r.highlights;
    }

    for (var i = 0; i < semanticResults.length; i++) {
      final r = semanticResults[i];
      final entry = fused.putIfAbsent(r.noteId, () => _FusedEntry(r));
      entry.rrfScore += 1.0 / (_rrfK + i + 1);
      entry.semanticScore ??= r.semanticScore;
    }

    // 计算最大 RRF 分数用于归一化
    final maxRrf = fused.values.fold<double>(0.0,
        (max, e) => e.rrfScore > max ? e.rrfScore : max);

    final merged = fused.values.map((e) {
      final normalized = maxRrf > 0 ? e.rrfScore / maxRrf : 0.0;
      return SearchResult(
        noteId: e.noteId,
        title: e.title,
        snippet: e.snippet,
        score: normalized,
        source: SearchResultSource.hybrid,
        highlights: e.highlights,
        keywordScore: e.keywordScore,
        semanticScore: e.semanticScore,
      );
    }).toList();

    merged.sort((a, b) => b.score.compareTo(a.score));
    return merged.take(limit).toList();
  }

  // ---------- 工具方法 ----------

  String _noteText(NoteModel note) {
    return '${note.title}\n${note.content}';
  }

  Future<NoteModel?> _loadNote(String noteId) async {
    try {
      final db = await _db.database;
      final rows = await db.query('notes', where: 'id = ?', whereArgs: [noteId]);
      if (rows.isEmpty) return null;
      return NoteModel.fromJson(rows.first);
    } catch (_) {
      return null;
    }
  }

  /// BM25 rank 归一化：rank 越小越相关，转换为 0~1 的分数
  ///
  /// FTS5 rank 通常为负值（越小越相关），这里使用 1/(1+|rank|) 归一化。
  double _normalizeBm25(double rank) {
    final abs = rank.abs();
    return 1.0 / (1.0 + abs);
  }

  /// 截取命中片段
  String _snippet(String content, String query) {
    if (content.isEmpty) return '';
    final idx = content.toLowerCase().indexOf(query.toLowerCase());
    if (idx < 0) {
      return content.length > 120 ? '${content.substring(0, 120)}...' : content;
    }
    final start = (idx - 40).clamp(0, content.length);
    final end = (idx + query.length + 80).clamp(0, content.length);
    final snippet = content.substring(start, end);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < content.length ? '...' : '';
    return '$prefix$snippet$suffix';
  }

  /// 构建关键词高亮区间
  List<HighlightModel> _buildHighlights(String content, String query) {
    final highlights = <HighlightModel>[];
    if (content.isEmpty || query.isEmpty) return highlights;
    var idx = content.toLowerCase().indexOf(query.toLowerCase());
    while (idx >= 0 && highlights.length < 5) {
      highlights.add(HighlightModel(
        start: idx,
        end: idx + query.length,
        text: content.substring(idx, idx + query.length),
      ));
      idx = content.toLowerCase().indexOf(query.toLowerCase(), idx + 1);
    }
    return highlights;
  }

  /// 清空向量索引（用于嵌入模型切换或重置）
  Future<void> clearIndex() async {
    await _ensureLoaded();
    _vectors.clear();
    await _persist();
  }

  /// 获取当前索引的笔记数量
  Future<int> get indexedCount async {
    await _ensureLoaded();
    return _vectors.length;
  }
}

/// RRF 融合过程中的临时条目
class _FusedEntry {
  final String noteId;
  final String title;
  final String snippet;
  double rrfScore;
  double? keywordScore;
  double? semanticScore;
  List<HighlightModel> highlights;

  _FusedEntry(SearchResult r)
      : noteId = r.noteId,
        title = r.title,
        snippet = r.snippet,
        rrfScore = 0.0,
        keywordScore = r.keywordScore,
        semanticScore = r.semanticScore,
        highlights = r.highlights;
}
