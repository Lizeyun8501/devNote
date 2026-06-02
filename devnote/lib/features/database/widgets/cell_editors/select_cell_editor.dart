import 'package:flutter/material.dart';

class SelectCellEditor extends StatelessWidget {
  final Map<String, dynamic> options;
  final dynamic value;
  final ValueChanged<dynamic>? onChanged;

  const SelectCellEditor({
    super.key,
    required this.options,
    this.value,
    this.onChanged,
  });

  static void show(BuildContext context, {required Map<String, dynamic> options, required dynamic value, required ValueChanged<dynamic> onSaved}) {
    final selectOptions = options['options'] as List<dynamic>? ?? [];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择'),
        children: selectOptions.map((opt) {
          final optValue = opt['value'] ?? opt['label'];
          final optLabel = opt['label'] ?? opt['value']?.toString() ?? '';
          return SimpleDialogOption(
            onPressed: () {
              onSaved(optValue);
              Navigator.of(ctx).pop();
            },
            child: Row(
              children: [
                if (optValue == value) const Icon(Icons.check, size: 18),
                const SizedBox(width: 8),
                Text(optLabel),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectOptions = options['options'] as List<dynamic>? ?? [];
    final match = selectOptions.where((o) => o['value'] == value).firstOrNull;
    if (match != null) {
      return Chip(label: Text(match['label'] ?? value?.toString() ?? ''));
    }
    return Text(value?.toString() ?? '');
  }
}
