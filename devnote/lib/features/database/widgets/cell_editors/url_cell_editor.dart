import 'package:flutter/material.dart';

class UrlCellEditor extends StatelessWidget {
  final String value;
  final ValueChanged<String>? onChanged;

  const UrlCellEditor({
    super.key,
    required this.value,
    this.onChanged,
  });

  static void show(BuildContext context, {required String value, required ValueChanged<String> onSaved}) {
    final controller = TextEditingController(text: value);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑链接'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://'),
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
    if (value.isEmpty) return const Text('');
    return Text(
      value,
      style: TextStyle(color: Theme.of(context).colorScheme.primary),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
