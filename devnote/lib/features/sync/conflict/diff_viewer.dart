import 'package:flutter/material.dart';
import 'conflict_resolver.dart';

class DiffViewer extends StatelessWidget {
  final String localContent;
  final String remoteContent;
  final String localLabel;
  final String remoteLabel;

  const DiffViewer({
    super.key,
    required this.localContent,
    required this.remoteContent,
    this.localLabel = 'Local',
    this.remoteLabel = 'Remote',
  });

  @override
  Widget build(BuildContext context) {
    final resolver = ConflictResolver();
    final diffLines = resolver.computeDiff(localContent, remoteContent);

    return Column(
      children: [
        _buildHeader(context),
        const Divider(height: 1),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _buildSide(
                  context: context,
                  label: localLabel,
                  lines: diffLines,
                  isLocal: true,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _buildSide(
                  context: context,
                  label: remoteLabel,
                  lines: diffLines,
                  isLocal: false,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Expanded(
            child: Text(
              localLabel,
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              remoteLabel,
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSide({
    required BuildContext context,
    required String label,
    required List<DiffLine> lines,
    required bool isLocal,
  }) {
    return ListView.builder(
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        return _buildDiffLine(context, line, isLocal);
      },
    );
  }

  Widget _buildDiffLine(BuildContext context, DiffLine line, bool isLocal) {
    final text = isLocal ? line.localLine : line.remoteLine;
    if (text == null) {
      return const SizedBox.shrink();
    }

    Color backgroundColor;
    Color textColor;
    IconData? icon;

    switch (line.type) {
      case DiffType.equal:
        backgroundColor = Colors.transparent;
        textColor = Theme.of(context).textTheme.bodyMedium!.color!;
        icon = null;
        break;
      case DiffType.added:
        backgroundColor = Colors.green.withValues(alpha: 0.1);
        textColor = Colors.green.shade800;
        icon = Icons.add;
        break;
      case DiffType.removed:
        backgroundColor = Colors.red.withValues(alpha: 0.1);
        textColor = Colors.red.shade800;
        icon = Icons.remove;
        break;
    }

    final showHighlight = (line.type == DiffType.added && !isLocal) ||
        (line.type == DiffType.removed && isLocal);
    final showDimmed = (line.type == DiffType.added && isLocal) ||
        (line.type == DiffType.removed && !isLocal);

    return Container(
      color: showHighlight ? backgroundColor : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '${line.lineNumber}',
              style: TextStyle(
                color: Theme.of(context).disabledColor,
                fontSize: 12,
              ),
            ),
          ),
          if (showHighlight && icon != null)
            Icon(icon, size: 14, color: textColor)
          else
            const SizedBox(width: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: showDimmed ? Theme.of(context).disabledColor : textColor,
                decoration: showDimmed ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DiffViewerDialog extends StatelessWidget {
  final String localContent;
  final String remoteContent;
  final String title;

  const DiffViewerDialog({
    super.key,
    required this.localContent,
    required this.remoteContent,
    this.title = 'Differences',
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: DiffViewer(
                localContent: localContent,
                remoteContent: remoteContent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> show({
    required BuildContext context,
    required String localContent,
    required String remoteContent,
    String title = 'Differences',
  }) {
    return showDialog(
      context: context,
      builder: (context) => DiffViewerDialog(
        localContent: localContent,
        remoteContent: remoteContent,
        title: title,
      ),
    );
  }
}
