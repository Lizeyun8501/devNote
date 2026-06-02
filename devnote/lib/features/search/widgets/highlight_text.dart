import 'package:flutter/material.dart';

class HighlightText extends StatelessWidget {
  final String text;
  final String highlightQuery;
  final TextStyle? style;
  final TextStyle? highlightStyle;
  final int maxLines;
  final TextOverflow overflow;

  const HighlightText({
    super.key,
    required this.text,
    required this.highlightQuery,
    this.style,
    this.highlightStyle,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  Widget build(BuildContext context) {
    if (highlightQuery.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final spans = _buildSpans(context);

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  List<TextSpan> _buildSpans(BuildContext context) {
    final effectiveHighlightStyle = highlightStyle ??
        style?.copyWith(
          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ) ??
        TextStyle(
          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        );

    final lowerText = text.toLowerCase();
    final lowerQuery = highlightQuery.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;

    while (start < lowerText.length) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start), style: style));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: style));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + highlightQuery.length),
        style: effectiveHighlightStyle,
      ));
      start = index + highlightQuery.length;
    }

    return spans;
  }
}
