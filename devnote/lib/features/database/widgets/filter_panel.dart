import 'package:flutter/material.dart';
import 'package:devnote/features/database/bloc/database_state.dart';

class FilterPanel extends StatelessWidget {
  final List<DatabaseFieldModel> fields;
  final List<FilterModel> activeFilters;
  final ValueChanged<List<FilterModel>> onApply;

  const FilterPanel({
    super.key,
    required this.fields,
    required this.activeFilters,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final filters = List<FilterModel>.from(activeFilters);

    return StatefulBuilder(
      builder: (context, setState) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('筛选', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      if (fields.isNotEmpty) {
                        setState(() {
                          filters.add(FilterModel(
                            fieldId: fields.first.id,
                            operator: 'contains',
                          ));
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...filters.asMap().entries.map((entry) {
                final index = entry.key;
                final filter = entry.value;
                return _FilterRow(
                  fields: fields,
                  filter: filter,
                  onChanged: (f) {
                    setState(() {
                      filters[index] = f;
                    });
                  },
                  onRemoved: () {
                    setState(() {
                      filters.removeAt(index);
                    });
                  },
                );
              }),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => onApply(filters),
                  child: const Text('应用筛选'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterRow extends StatefulWidget {
  final List<DatabaseFieldModel> fields;
  final FilterModel filter;
  final ValueChanged<FilterModel> onChanged;
  final VoidCallback onRemoved;

  const _FilterRow({
    required this.fields,
    required this.filter,
    required this.onChanged,
    required this.onRemoved,
  });

  @override
  State<_FilterRow> createState() => _FilterRowState();
}

class _FilterRowState extends State<_FilterRow> {
  late final TextEditingController _valueController;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController(
      text: widget.filter.value?.toString() ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _FilterRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当外部 filter.value 变化（且与当前 controller 文本不同步）时同步到 controller，
    // 避免在 build 中创建新 controller 造成内存泄漏与输入焦点丢失。
    final newText = widget.filter.value?.toString() ?? '';
    if (_valueController.text != newText) {
      _valueController.text = newText;
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  void _emitValue(String v) {
    widget.onChanged(FilterModel(
      fieldId: widget.filter.fieldId,
      operator: widget.filter.operator,
      value: v,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: filter.fieldId,
              decoration: const InputDecoration(isDense: true, labelText: '字段'),
              items: widget.fields.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name))).toList(),
              onChanged: (v) {
                if (v != null) widget.onChanged(FilterModel(fieldId: v, operator: filter.operator, value: filter.value));
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: filter.operator,
              decoration: const InputDecoration(isDense: true, labelText: '条件'),
              items: const [
                DropdownMenuItem(value: 'contains', child: Text('包含')),
                DropdownMenuItem(value: 'equals', child: Text('等于')),
                DropdownMenuItem(value: 'not_equals', child: Text('不等于')),
                DropdownMenuItem(value: 'starts_with', child: Text('开头是')),
                DropdownMenuItem(value: 'is_empty', child: Text('为空')),
                DropdownMenuItem(value: 'is_not_empty', child: Text('不为空')),
              ],
              onChanged: (v) {
                if (v != null) widget.onChanged(FilterModel(fieldId: filter.fieldId, operator: v, value: filter.value));
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              decoration: const InputDecoration(isDense: true, labelText: '值'),
              controller: _valueController,
              onChanged: _emitValue,
            ),
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: widget.onRemoved),
        ],
      ),
    );
  }
}
