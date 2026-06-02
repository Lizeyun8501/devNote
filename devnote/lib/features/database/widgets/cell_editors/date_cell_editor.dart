import 'package:flutter/material.dart';

class DateCellEditor extends StatelessWidget {
  final String? value;
  final ValueChanged<String>? onChanged;

  const DateCellEditor({
    super.key,
    this.value,
    this.onChanged,
  });

  static void show(BuildContext context, {String? value, required ValueChanged<String> onSaved}) async {
    final initial = value != null ? DateTime.tryParse(value) : null;
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null) {
      onSaved(date.toIso8601String().split('T').first);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(value ?? '');
  }
}
