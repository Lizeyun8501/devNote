import 'package:flutter/material.dart';
import 'package:devnote/features/search/search_service.dart';
import 'package:devnote/features/search/widgets/highlight_text.dart';

class SearchResultCard extends StatelessWidget {
  final SearchResultModel result;
  final String query;
  final VoidCallback? onTap;

  const SearchResultCard({
    super.key,
    required this.result,
    required this.query,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HighlightText(
                text: result.title,
                highlightQuery: query,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                maxLines: 1,
              ),
              const SizedBox(height: 6),
              HighlightText(
                text: result.snippet,
                highlightQuery: query,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '相关度: ${(result.score * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
