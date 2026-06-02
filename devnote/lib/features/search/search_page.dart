import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/search/bloc/search_bloc.dart';
import 'package:devnote/features/search/bloc/search_event.dart';
import 'package:devnote/features/search/bloc/search_state.dart';
import 'package:devnote/features/search/search_service.dart';
import 'package:devnote/features/search/widgets/search_result_card.dart';
import 'package:devnote/features/search/widgets/search_filter_panel.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SearchBloc(SearchService())
        ..add(const SearchHistoryRequested()),
      child: const _SearchView(),
    );
  }
}

class _SearchView extends StatefulWidget {
  const _SearchView();

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  late final TextEditingController _searchController;
  bool _showFilter = false;
  String? _selectedFolderId;
  List<String> _selectedTags = [];
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    context.read<SearchBloc>().add(SearchQueryChanged(query));
  }

  void _onSearchSubmitted(String query) {
    context.read<SearchBloc>().add(SearchSubmitted(query));
  }

  void _onHistoryItemTap(String query) {
    _searchController.text = query;
    context.read<SearchBloc>().add(SearchSubmitted(query));
  }

  void _onFilterReset() {
    setState(() {
      _selectedFolderId = null;
      _selectedTags = [];
      _startDate = null;
      _endDate = null;
    });
    context.read<SearchBloc>().add(const SearchFilterChanged());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
      ),
      body: Column(
        children: [
          _buildSearchBar(context),
          if (_showFilter) _buildFilterPanel(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              onSubmitted: _onSearchSubmitted,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '搜索笔记...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          context.read<SearchBloc>().add(const SearchQueryChanged(''));
                        },
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              Icons.tune,
              color: _showFilter ? Theme.of(context).colorScheme.primary : null,
            ),
            onPressed: () {
              setState(() {
                _showFilter = !_showFilter;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SearchFilterPanel(
        selectedFolderId: _selectedFolderId,
        selectedTags: _selectedTags,
        startDate: _startDate,
        endDate: _endDate,
        onFolderChanged: (folderId) {
          setState(() {
            _selectedFolderId = folderId;
          });
          context.read<SearchBloc>().add(SearchFilterChanged(
                folderId: folderId,
                tags: _selectedTags,
                startDate: _startDate,
                endDate: _endDate,
              ));
        },
        onTagsChanged: (tags) {
          setState(() {
            _selectedTags = tags;
          });
          context.read<SearchBloc>().add(SearchFilterChanged(
                folderId: _selectedFolderId,
                tags: tags,
                startDate: _startDate,
                endDate: _endDate,
              ));
        },
        onStartDateChanged: (date) {
          setState(() {
            _startDate = date;
          });
          context.read<SearchBloc>().add(SearchFilterChanged(
                folderId: _selectedFolderId,
                tags: _selectedTags,
                startDate: date,
                endDate: _endDate,
              ));
        },
        onEndDateChanged: (date) {
          setState(() {
            _endDate = date;
          });
          context.read<SearchBloc>().add(SearchFilterChanged(
                folderId: _selectedFolderId,
                tags: _selectedTags,
                startDate: _startDate,
                endDate: date,
              ));
        },
        onReset: _onFilterReset,
      ),
    );
  }

  Widget _buildBody() {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        if (state is SearchLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is SearchError) {
          return Center(child: Text('搜索出错: ${state.message}'));
        }
        if (state is SearchResults) {
          if (state.results.isEmpty && state.query.isNotEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '未找到 "${state.query}" 的相关结果',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            );
          }
          if (state.results.isNotEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '找到 ${state.results.length} 个结果',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                ...state.results.map((result) => SearchResultCard(
                      result: result,
                      query: state.query,
                      onTap: () {},
                    )),
              ],
            );
          }
          return _buildSearchHistory(state.searchHistory);
        }
        return _buildInitialView();
      },
    );
  }

  Widget _buildInitialView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '输入关键词搜索笔记',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchHistory(List<String> history) {
    if (history.isEmpty) return _buildInitialView();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '搜索历史',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            TextButton(
              onPressed: () {
                SearchService().clearSearchHistory();
                context.read<SearchBloc>().add(const SearchHistoryRequested());
              },
              child: const Text('清除'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...history.map((query) => ListTile(
              leading: const Icon(Icons.history, size: 20),
              title: Text(query),
              dense: true,
              onTap: () => _onHistoryItemTap(query),
            )),
      ],
    );
  }
}
