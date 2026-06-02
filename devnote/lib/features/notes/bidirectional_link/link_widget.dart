import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:devnote/features/notes/bidirectional_link/link_service.dart';

class LinkWidget extends StatelessWidget {
  const LinkWidget({
    super.key,
    required this.link,
  });

  final LinkInfo link;

  @override
  Widget build(BuildContext context) {
    final hasTarget = link.noteId != null;

    return MouseRegion(
      cursor: hasTarget ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: hasTarget ? () => context.go('/notes/${link.noteId}') : null,
        child: Text(
          '[[${link.noteName}]]',
          style: TextStyle(
            color: hasTarget
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error.withValues(alpha: 0.7),
            decoration: hasTarget ? TextDecoration.underline : TextDecoration.none,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class LinkInlineSpan extends TextSpan {
  LinkInlineSpan({
    required LinkInfo link,
    VoidCallback? onTap,
  }) : super(
          text: '[[${link.noteName}]]',
          style: TextStyle(
            color: link.noteId != null ? const Color(0xFF1565C0) : const Color(0xFFE53935).withValues(alpha: 0.7),
            decoration: link.noteId != null ? TextDecoration.underline : TextDecoration.none,
          ),
          recognizer: null,
        );
}

class RichTextWithLinks extends StatelessWidget {
  const RichTextWithLinks({
    super.key,
    required this.text,
    required this.links,
  });

  final String text;
  final List<LinkInfo> links;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    final linkPattern = BidirectionalLinkService.linkPattern;
    var lastEnd = 0;

    for (final match in linkPattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }

      final noteName = match.group(1)?.trim() ?? '';
      final link = links.firstWhere(
        (l) => l.noteName == noteName,
        orElse: () => LinkInfo(noteName: noteName),
      );

      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(
          color: link.noteId != null
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error.withValues(alpha: 0.7),
          decoration: link.noteId != null ? TextDecoration.underline : TextDecoration.none,
        ),
      ));

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: spans,
      ),
    );
  }
}
