// AI 语义搜索结果数据类
//
// 借鉴 Obsidian Hybrid Retrieval 的搜索结果结构：
// 同时携带原始分数、来源标签（关键词/语义/混合）和高亮信息，
// 便于 UI 层区分结果来源并展示匹配上下文。

// P1 修复 (P1-3): 改为从 core 层导入 HighlightModel，打破 ai ↔ search 循环依赖
import 'package:devnote/core/persistence/models/highlight_model.dart';
// 导入 SearchResultModel 用于 toSearchResultModel 转换
import 'package:devnote/features/search/search_service.dart' show SearchResultModel;

/// 搜索结果来源
///
/// - [keyword]：仅 FTS5 关键词检索（BM25）
/// - [semantic]：仅向量语义检索（余弦相似度）
/// - [hybrid]：BM25 + 向量经 RRF 融合后的混合结果
enum SearchResultSource { keyword, semantic, hybrid }

/// 语义搜索结果
///
/// 与 [SearchResultModel] 解耦，避免破坏现有搜索功能；
/// 通过 [toSearchResultModel] 可转换为现有搜索结果模型，
/// 供 SearchResultCard 等已有 Widget 复用渲染。
class SearchResult {
  /// 笔记 ID
  final String noteId;

  /// 笔记标题
  final String title;

  /// 命中片段（已截取的上下文摘要）
  final String snippet;

  /// 归一化后的最终得分（0.0 ~ 1.0，越高越相关）
  final double score;

  /// 结果来源（关键词 / 语义 / 混合）
  final SearchResultSource source;

  /// 关键词命中高亮区间列表
  final List<HighlightModel> highlights;

  /// 关键词检索子得分（BM25 归一化后），无关键词命中时为 null
  final double? keywordScore;

  /// 语义检索子得分（余弦相似度归一化后），无语义命中时为 null
  final double? semanticScore;

  const SearchResult({
    required this.noteId,
    required this.title,
    required this.snippet,
    required this.score,
    required this.source,
    this.highlights = const [],
    this.keywordScore,
    this.semanticScore,
  });

  /// 转换为现有 [SearchResultModel]，便于复用 SearchResultCard 渲染
  SearchResultModel toSearchResultModel() {
    return SearchResultModel(
      noteId: noteId,
      title: title,
      snippet: snippet,
      highlights: highlights,
      score: score,
    );
  }

  @override
  String toString() {
    return 'SearchResult(noteId: $noteId, title: $title, score: $score, '
        'source: $source, keyword: $keywordScore, semantic: $semanticScore)';
  }
}
