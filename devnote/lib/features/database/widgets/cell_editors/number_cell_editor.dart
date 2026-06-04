import 'package:flutter/material.dart';

class NumberCellEditor extends StatelessWidget {
  final String value;
  final ValueChanged<String>? onChanged;

  const NumberCellEditor({
    super.key,
    required this.value,
    this.onChanged,
  });

  static void show(BuildContext context, {required String value, required ValueChanged<String> onSaved}) {
    final controller = TextEditingController(text: value);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑数字'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () {
              onSaved(controller.text);
              Navigator.of(ctx).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Text(value, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]));
  }
}
