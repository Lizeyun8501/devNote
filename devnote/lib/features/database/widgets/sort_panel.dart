import 'package:flutter/material.dart';
import 'package:devnote/features/database/bloc/database_state.dart';

class SortPanel extends StatelessWidget {
  final List<DatabaseFieldModel> fields;
  final List<SortModel> activeSorts;
  final ValueChanged<List<SortModel>> onApply;

  const SortPanel({
    super.key,
    required this.fields,
    required this.activeSorts,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final sorts = List<SortModel>.from(activeSorts);

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
                  Text('排序', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      if (fields.isNotEmpty) {
                        setState(() {
                          sorts.add(SortModel(
                            fieldId: fields.first.id,
                            direction: 'asc',
                          ));
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...sorts.asMap().entries.map((entry) {
                final index = entry.key;
                final sort = entry.value;
                return _SortRow(
                  fields: fields,
                  sort: sort,
                  onChanged: (s) {
                    setState(() {
                      sorts[index] = s;
                    });
                  },
                  onRemoved: () {
                    setState(() {
                      sorts.removeAt(index);
                    });
                  },
                );
              }),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => onApply(sorts),
                  child: const Text('应用排序'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SortRow extends StatelessWidget {
  final List<DatabaseFieldModel> fields;
  final SortModel sort;
  final ValueChanged<SortModel> onChanged;
  final VoidCallback onRemoved;

  const _SortRow({
    required this.fields,
    required this.sort,
    required this.onChanged,
    required this.onRemoved,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: sort.fieldId,
              decoration: const InputDecoration(isDense: true, labelText: '字段'),
              items: fields.map((f) => DropdownMenuItem(value: f.id, child: Text(f.name))).toList(),
              onChanged: (v) {
                if (v != null) onChanged(SortModel(fieldId: v, direction: sort.direction));
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: sort.direction,
              decoration: const InputDecoration(isDense: true, labelText: '方向'),
              items: const [
                DropdownMenuItem(value: 'asc', child: Text('升序')),
                DropdownMenuItem(value: 'desc', child: Text('降序')),
              ],
              onChanged: (v) {
                if (v != null) onChanged(SortModel(fieldId: sort.fieldId, direction: v));
              },
            ),
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: onRemoved),
        ],
      ),
    );
  }
}
