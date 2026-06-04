import 'package:flutter/material.dart';
import 'conflict_resolver.dart';
import 'diff_viewer.dart';

enum MergeChoice {
  local,
  remote,
  custom,
}

class MergeEditor extends StatefulWidget {
  final ConflictInfo conflict;
  final ValueChanged<String> onResolved;

  const MergeEditor({
    super.key,
    required this.conflict,
    required this.onResolved,
  });

  @override
  State<MergeEditor> createState() => _MergeEditorState();
}

class _MergeEditorState extends State<MergeEditor> {
  MergeChoice _choice = MergeChoice.local;
  late TextEditingController _customController;

  @override
  void initState() {
    super.initState();
    _customController = TextEditingController(
      text: widget.conflict.localContent,
    );
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  String get _resolvedContent {
    switch (_choice) {
      case MergeChoice.local:
        return widget.conflict.localContent;
      case MergeChoice.remote:
        return widget.conflict.remoteContent;
      case MergeChoice.custom:
        return _customController.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildConflictHeader(context),
            const SizedBox(height: 16),
            _buildConflictTypeBadge(context),
            const SizedBox(height: 16),
            _buildDiffPreview(context),
            const SizedBox(height: 16),
            _buildChoiceSelector(context),
            if (_choice == MergeChoice.custom) ...[
              const SizedBox(height: 16),
              _buildCustomEditor(context),
            ],
            const SizedBox(height: 16),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictHeader(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Conflict: ${widget.conflict.blockId}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }

  Widget _buildConflictTypeBadge(BuildContext context) {
    final label = switch (widget.conflict.conflictType) {
      ConflictType.contentConflict => 'Content Conflict',
      ConflictType.moveConflict => 'Move Conflict',
      ConflictType.deleteModifyConflict => 'Delete/Modify Conflict',
    };

    final color = switch (widget.conflict.conflictType) {
      ConflictType.contentConflict => Colors.orange,
      ConflictType.moveConflict => Colors.blue,
      ConflictType.deleteModifyConflict => Colors.red,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }

  Widget _buildDiffPreview(BuildContext context) {
    return SizedBox(
      height: 200,
      child: DiffViewer(
        localContent: widget.conflict.localContent,
        remoteContent: widget.conflict.remoteContent,
      ),
    );
  }

  Widget _buildChoiceSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose resolution:',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        RadioListTile<MergeChoice>(
          title: const Text('Keep Local'),
          subtitle: Text(
            widget.conflict.localContent.length > 50
                ? '${widget.conflict.localContent.substring(0, 50)}...'
                : widget.conflict.localContent,
          ),
          value: MergeChoice.local,
          groupValue: _choice,
          onChanged: (value) => setState(() => _choice = value!),
        ),
        RadioListTile<MergeChoice>(
          title: const Text('Keep Remote'),
          subtitle: Text(
            widget.conflict.remoteContent.length > 50
                ? '${widget.conflict.remoteContent.substring(0, 50)}...'
                : widget.conflict.remoteContent,
          ),
          value: MergeChoice.remote,
          groupValue: _choice,
          onChanged: (value) => setState(() => _choice = value!),
        ),
        RadioListTile<MergeChoice>(
          title: const Text('Custom'),
          subtitle: const Text('Manually edit the merged content'),
          value: MergeChoice.custom,
          groupValue: _choice,
          onChanged: (value) => setState(() => _choice = value!),
        ),
      ],
    );
  }

  Widget _buildCustomEditor(BuildContext context) {
    return TextField(
      controller: _customController,
      maxLines: 8,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: 'Merged Content',
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.content_copy, size: 18),
              tooltip: 'Paste Local',
              onPressed: () {
                _customController.text = widget.conflict.localContent;
              },
            ),
            IconButton(
              icon: const Icon(Icons.cloud_download, size: 18),
              tooltip: 'Paste Remote',
              onPressed: () {
                _customController.text = widget.conflict.remoteContent;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () {
            widget.onResolved(_resolvedContent);
          },
          child: const Text('Resolve'),
        ),
      ],
    );
  }
}

class MergeEditorPage extends StatefulWidget {
  final ConflictResolver resolver;
  final VoidCallback onAllResolved;

  const MergeEditorPage({
    super.key,
    required this.resolver,
    required this.onAllResolved,
  });

  @override
  State<MergeEditorPage> createState() => _MergeEditorPageState();
}

class _MergeEditorPageState extends State<MergeEditorPage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final conflicts = widget.resolver.conflicts;
    if (conflicts.isEmpty) {
      return const SizedBox.shrink();
    }

    final conflict = conflicts[_currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text('Resolve Conflicts (${_currentIndex + 1}/${conflicts.length})'),
        actions: [
          TextButton(
            onPressed: () {
              widget.resolver.resolveAll(MergeStrategy.preferLocal);
              widget.onAllResolved();
            },
            child: const Text('Keep All Local'),
          ),
          TextButton(
            onPressed: () {
              widget.resolver.resolveAll(MergeStrategy.preferRemote);
              widget.onAllResolved();
            },
            child: const Text('Keep All Remote'),
          ),
        ],
      ),
      body: MergeEditor(
        conflict: conflict,
        onResolved: (content) {
          widget.resolver.resolveConflict(conflict.blockId, content);
          if (_currentIndex < conflicts.length - 1) {
            setState(() => _currentIndex++);
          } else {
            widget.onAllResolved();
          }
        },
      ),
    );
  }
}
