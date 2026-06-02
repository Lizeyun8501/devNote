import 'package:flutter/material.dart';
import 'package:devnote/features/workflow/git_service.dart';

class GitStatusIndicator extends StatefulWidget {
  const GitStatusIndicator({super.key});

  @override
  State<GitStatusIndicator> createState() => _GitStatusIndicatorState();
}

class _GitStatusIndicatorState extends State<GitStatusIndicator> {
  final GitService _gitService = GitService();
  GitStatusModel? _status;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await _gitService.status();
      if (mounted) {
        setState(() {
          _status = status;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_status == null) {
      return const SizedBox.shrink();
    }

    final hasChanges = _status!.hasChanges;
    final totalChanges = _status!.modified.length +
        _status!.added.length +
        _status!.deleted.length +
        _status!.untracked.length;

    return Tooltip(
      message: hasChanges
          ? '$totalChanges 个文件有变更'
          : '工作区干净',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: hasChanges
              ? Theme.of(context).colorScheme.errorContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasChanges ? Icons.circle : Icons.check_circle_outline,
              size: 12,
              color: hasChanges
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              hasChanges ? '$totalChanges' : 'clean',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: hasChanges
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
