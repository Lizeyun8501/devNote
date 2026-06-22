// P1 修复 (P1-3): 提取 HighlightModel 到 core 层，打破 ai ↔ search 循环依赖
//
// HighlightModel 是一个纯数据类（start/end/text 三字段 + fromJson），
// 被 search 和 ai 两个模块共同使用。原定义在 features/search/search_service.dart，
// 导致 ai 模块需要 import search 模块，形成循环依赖。
// 提取到 core 层后，两个模块都单向依赖 core，循环被打破。

/// 搜索高亮信息
///
/// 表示搜索结果中匹配关键词的位置区间 [start, end) 及匹配文本。
/// 被 search 模块（SearchResultModel）和 ai 模块（SearchResult）共同使用。
class HighlightModel {
  final int start;
  final int end;
  final String text;

  const HighlightModel({
    required this.start,
    required this.end,
    required this.text,
  });

  factory HighlightModel.fromJson(Map<String, dynamic> json) {
    return HighlightModel(
      start: json['start'] as int,
      end: json['end'] as int,
      text: json['text'] as String,
    );
  }
}
