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
