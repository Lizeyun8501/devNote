import 'package:flutter/material.dart';

class MarkdownRenderer extends StatelessWidget {
  final String markdown;

  const MarkdownRenderer({super.key, required this.markdown});

  @override
  Widget build(BuildContext context) {
    final spans = _parseInline(context, markdown);
    return SelectableText.rich(
      TextSpan(children: spans),
    );
  }

  List<InlineSpan> _parseInline(BuildContext context, String text) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();
    var i = 0;

    while (i < text.length) {
      if (i + 1 < text.length && text[i] == '*' && text[i + 1] == '*') {
        if (buffer.isNotEmpty) {
          spans.add(TextSpan(text: buffer.toString()));
          buffer.clear();
        }
        var end = text.indexOf('**', i + 2);
        if (end == -1) end = text.length;
        spans.add(TextSpan(
          text: text.substring(i + 2, end),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ));
        i = end + 2;
        continue;
      }
      if (text[i] == '*' && (i == 0 || text[i - 1] != '*')) {
        if (i + 1 < text.length && text[i + 1] != '*') {
          if (buffer.isNotEmpty) {
            spans.add(TextSpan(text: buffer.toString()));
            buffer.clear();
          }
          var end = text.indexOf('*', i + 1);
          if (end == -1) end = text.length;
          spans.add(TextSpan(
            text: text.substring(i + 1, end),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ));
          i = end + 1;
          continue;
        }
      }
      if (text[i] == '`') {
        if (buffer.isNotEmpty) {
          spans.add(TextSpan(text: buffer.toString()));
          buffer.clear();
        }
        var end = text.indexOf('`', i + 1);
        if (end == -1) end = text.length;
        spans.add(TextSpan(
          text: text.substring(i + 1, end),
          style: TextStyle(
            fontFamily: 'monospace',
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ));
        i = end + 1;
        continue;
      }
      buffer.write(text[i]);
      i++;
    }

    if (buffer.isNotEmpty) {
      spans.add(TextSpan(text: buffer.toString()));
    }

    return spans;
  }
}
