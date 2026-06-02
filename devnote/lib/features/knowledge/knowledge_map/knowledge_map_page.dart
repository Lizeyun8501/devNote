import 'package:flutter/material.dart';
import 'package:devnote/features/knowledge/knowledge_map/knowledge_map_service.dart';

class KnowledgeMapPage extends StatefulWidget {
  const KnowledgeMapPage({super.key});

  @override
  State<KnowledgeMapPage> createState() => _KnowledgeMapPageState();
}

class _KnowledgeMapPageState extends State<KnowledgeMapPage> {
  final KnowledgeMapService _service = KnowledgeMapService();
  KnowledgeMapData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final data = await _service.getKnowledgeMap();
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('知识体系'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '学习目标',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_data?.goals.isEmpty ?? true)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('暂无学习目标'),
                      ),
                    )
                  else
                    ..._data!.goals.map((goal) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        goal.title,
                                        style: Theme.of(context).textTheme.titleSmall,
                                      ),
                                    ),
                                    Text(
                                      '${(goal.progress * 100).toStringAsFixed(0)}%',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context).colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: goal.progress,
                                    minHeight: 6,
                                  ),
                                ),
                                if (goal.tags.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 4,
                                    children: goal.tags
                                        .map((tag) => Chip(
                                              label: Text(
                                                tag,
                                                style: Theme.of(context).textTheme.labelSmall,
                                              ),
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              visualDensity: VisualDensity.compact,
                                            ))
                                        .toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )),
                  const SizedBox(height: 24),
                  Text(
                    '标签云',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_data?.tags.isEmpty ?? true)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('暂无标签'),
                      ),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _data!.tags.map((tag) {
                            final maxCount = _data!.tags
                                .map((t) => t.count)
                                .reduce((a, b) => a > b ? a : b);
                            final ratio = maxCount == 0 ? 0.5 : tag.count / maxCount;
                            final fontSize = 12.0 + ratio * 12.0;
                            return Text(
                              tag.name,
                              style: TextStyle(
                                fontSize: fontSize,
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5 + ratio * 0.5),
                                fontWeight: ratio > 0.5 ? FontWeight.bold : FontWeight.normal,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
