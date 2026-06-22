import 'package:flutter/material.dart';
import 'package:devnote/core/di/injection.dart';
import 'models/note_template.dart';
import 'services/template_service.dart';

class TemplatePickerPage extends StatefulWidget {
  final Function(NoteTemplate) onTemplateSelected;

  const TemplatePickerPage({
    super.key,
    required this.onTemplateSelected,
  });

  @override
  State<TemplatePickerPage> createState() => _TemplatePickerPageState();
}

class _TemplatePickerPageState extends State<TemplatePickerPage> {
  final _templateService = getIt<TemplateService>();
  List<NoteTemplate> _templates = [];
  TemplateCategory? _selectedCategory;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    final templates = await _templateService.getAllTemplates();
    setState(() {
      _templates = templates;
      _loading = false;
    });
  }

  List<NoteTemplate> get _filteredTemplates {
    if (_selectedCategory == null) return _templates;
    return _templates.where((t) => t.category == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择模板'),
        actions: [
          IconButton(
            icon: const Icon(Icons.note_add),
            tooltip: '空白笔记',
            onPressed: () {
              final blank = _templates.firstWhere(
                (t) => t.id == 'builtin-blank',
                orElse: () => _templates.first,
              );
              widget.onTemplateSelected(blank);
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 分类筛选
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: TemplateCategory.values.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildCategoryChip(null, '全部');
                      }
                      final cat = TemplateCategory.values[index - 1];
                      return _buildCategoryChip(cat, cat.displayName);
                    },
                  ),
                ),
                // 模板列表
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 250,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _filteredTemplates.length,
                    itemBuilder: (context, index) {
                      final template = _filteredTemplates[index];
                      return _buildTemplateCard(template);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCategoryChip(TemplateCategory? category, String label) {
    final isSelected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() => _selectedCategory = isSelected ? null : category);
        },
      ),
    );
  }

  Widget _buildTemplateCard(NoteTemplate template) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          widget.onTemplateSelected(template);
          Navigator.pop(context);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_getCategoryIcon(template.category), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      template.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (template.isCustom)
                    const Icon(Icons.person, size: 16, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                template.description,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text(
                '${template.blocks.length} 个块',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 4),
              // 预览前几个块类型
              Wrap(
                spacing: 4,
                children: template.blocks.take(4).map((b) {
                  return Chip(
                    label: Text(b.type, style: const TextStyle(fontSize: 10)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getCategoryIcon(TemplateCategory category) {
    switch (category) {
      case TemplateCategory.meeting:
        return Icons.groups;
      case TemplateCategory.reading:
        return Icons.menu_book;
      case TemplateCategory.project:
        return Icons.assignment;
      case TemplateCategory.daily:
        return Icons.calendar_today;
      case TemplateCategory.todo:
        return Icons.checklist;
      case TemplateCategory.study:
        return Icons.school;
      case TemplateCategory.research:
        return Icons.science;
      case TemplateCategory.other:
        return Icons.description;
    }
  }
}
