import 'package:flutter/material.dart';
import 'package:devnote/features/knowledge_graph/graph_service.dart';

class GraphFilterPanel extends StatefulWidget {
  final void Function(GraphFilterModel) onFilter;

  const GraphFilterPanel({super.key, required this.onFilter});

  @override
  State<GraphFilterPanel> createState() => _GraphFilterPanelState();
}

class _GraphFilterPanelState extends State<GraphFilterPanel> {
  final _searchController = TextEditingController();
  final Map<GraphNodeType, bool> _nodeTypeFilters = {
    GraphNodeType.note: true,
    GraphNodeType.tag: true,
    GraphNodeType.folder: true,
    GraphNodeType.canvas: true,
  };
  final _tagController = TextEditingController();
  List<String> _selectedTags = [];

  void _applyFilter() {
    final enabledTypes = _nodeTypeFilters.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    widget.onFilter(GraphFilterModel(
      nodeTypes: enabledTypes.length < 4 ? enabledTypes : null,
      tags: _selectedTags.isNotEmpty ? _selectedTags : null,
      searchQuery: _searchController.text.isNotEmpty ? _searchController.text : null,
    ));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '筛选',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: '搜索',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _applyFilter(),
          ),
          const SizedBox(height: 16),
          Text(
            '节点类型',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          ..._nodeTypeFilters.keys.map((type) {
            return CheckboxListTile(
              dense: true,
              title: Text(_typeLabel(type)),
              value: _nodeTypeFilters[type],
              onChanged: (value) {
                setState(() {
                  _nodeTypeFilters[type] = value ?? true;
                });
                _applyFilter();
              },
            );
          }),
          const SizedBox(height: 16),
          Text(
            '标签',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagController,
                  decoration: const InputDecoration(
                    labelText: '添加标签',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) {
                    if (value.isNotEmpty && !_selectedTags.contains(value)) {
                      setState(() {
                        _selectedTags.add(value);
                      });
                      _tagController.clear();
                      _applyFilter();
                    }
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  final value = _tagController.text;
                  if (value.isNotEmpty && !_selectedTags.contains(value)) {
                    setState(() {
                      _selectedTags.add(value);
                    });
                    _tagController.clear();
                    _applyFilter();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: _selectedTags.map((tag) {
              return Chip(
                label: Text(tag),
                onDeleted: () {
                  setState(() {
                    _selectedTags.remove(tag);
                  });
                  _applyFilter();
                },
              );
            }).toList(),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _applyFilter,
              child: const Text('应用筛选'),
            ),
          ),
        ],
      ),
    );
  }

  String _typeLabel(GraphNodeType type) {
    switch (type) {
      case GraphNodeType.note:
        return '笔记';
      case GraphNodeType.tag:
        return '标签';
      case GraphNodeType.folder:
        return '文件夹';
      case GraphNodeType.canvas:
        return '画布';
    }
  }
}
