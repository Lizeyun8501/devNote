import 'package:equatable/equatable.dart';

abstract class SearchEvent extends Equatable {
  const SearchEvent();

  @override
  List<Object?> get props => [];
}

class SearchQueryChanged extends SearchEvent {
  final String query;

  const SearchQueryChanged(this.query);

  @override
  List<Object?> get props => [query];
}

class SearchSubmitted extends SearchEvent {
  final String query;

  const SearchSubmitted(this.query);

  @override
  List<Object?> get props => [query];
}

class SearchFilterChanged extends SearchEvent {
  final String? folderId;
  final List<String> tags;
  final DateTime? startDate;
  final DateTime? endDate;

  const SearchFilterChanged({
    this.folderId,
    this.tags = const [],
    this.startDate,
    this.endDate,
  });

  @override
  List<Object?> get props => [folderId, tags, startDate, endDate];
}

class SearchHistoryRequested extends SearchEvent {
  const SearchHistoryRequested();
}

/// 语义搜索开关切换
///
/// 开启后使用 Hybrid Retrieval（BM25 + 向量 + RRF 融合），
/// 关闭后回退到纯 FTS5 关键词检索，不破坏现有搜索功能。
class SearchSemanticToggled extends SearchEvent {
  final bool enabled;

  const SearchSemanticToggled(this.enabled);

  @override
  List<Object?> get props => [enabled];
}
