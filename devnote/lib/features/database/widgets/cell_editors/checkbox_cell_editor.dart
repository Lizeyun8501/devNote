import 'package:flutter/material.dart';

class CheckboxCellEditor extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const CheckboxCellEditor({
    super.key,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Checkbox(
      value: value,
      onChanged: (v) => onChanged?.call(v ?? false),
    );
  }
}
