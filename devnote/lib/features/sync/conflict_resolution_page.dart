import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:devnote/features/sync/bloc/sync_bloc.dart';
import 'package:devnote/features/sync/bloc/sync_event.dart';
import 'package:devnote/features/sync/bloc/sync_state.dart';
import 'package:devnote/features/sync/conflict/conflict_resolver.dart';
import 'package:devnote/features/sync/conflict/diff_viewer.dart';

class ConflictResolutionPage extends StatelessWidget {
  const ConflictResolutionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('冲突解决'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              final bloc = context.read<SyncBloc>();
              final state = bloc.state;
              if (state is! SyncConflict) return;

              final resolver = ConflictResolver();
              resolver.addConflicts(state.conflicts);

              switch (value) {
                case 'local':
                  resolver.resolveAll(MergeStrategy.preferLocal);
                  for (final conflict in state.conflicts) {
                    bloc.add(ResolveConflict(
                      blockId: conflict.blockId,
                      resolvedContent: conflict.localContent,
                    ));
                  }
                case 'remote':
                  resolver.resolveAll(MergeStrategy.preferRemote);
                  for (final conflict in state.conflicts) {
                    bloc.add(ResolveConflict(
                      blockId: conflict.blockId,
                      resolvedContent: conflict.remoteContent,
                    ));
                  }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'local',
                child: ListTile(
                  leading: Icon(Icons.phone_android),
                  title: Text('全部保留本地版本'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'remote',
                child: ListTile(
                  leading: Icon(Icons.cloud),
                  title: Text('全部保留远程版本'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: BlocBuilder<SyncBloc, SyncState>(
        builder: (context, state) {
          if (state is! SyncConflict) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '没有需要解决的冲突',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '所有冲突已解决',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            );
          }

          if (state.conflicts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '没有需要解决的冲突',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: state.conflicts.length,
            itemBuilder: (context, index) {
              return _ConflictCard(
                conflict: state.conflicts[index],
                index: index,
                total: state.conflicts.length,
              );
            },
          );
        },
      ),
    );
  }
}

class _ConflictCard extends StatefulWidget {
  final ConflictInfo conflict;
  final int index;
  final int total;

  const _ConflictCard({
    required this.conflict,
    required this.index,
    required this.total,
  });

  @override
  State<_ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends State<_ConflictCard> {
  bool _expanded = false;
  ConflictChoice _choice = ConflictChoice.local;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildConflictTypeIcon(context),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '冲突 ${widget.index + 1}/${widget.total}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Block: ${widget.conflict.blockId}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  _buildConflictTypeBadge(context),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDiffSection(context),
                  const SizedBox(height: 16),
                  Text(
                    '选择保留的版本',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _buildChoiceSelector(context),
                  const SizedBox(height: 16),
                  _buildActions(context),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConflictTypeIcon(BuildContext context) {
    final color = switch (widget.conflict.conflictType) {
      ConflictType.contentConflict => Colors.orange,
      ConflictType.moveConflict => Colors.blue,
      ConflictType.deleteModifyConflict => Colors.red,
    };

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.warning_amber_rounded, color: color, size: 24),
    );
  }

  Widget _buildConflictTypeBadge(BuildContext context) {
    final (label, color) = switch (widget.conflict.conflictType) {
      ConflictType.contentConflict => ('内容冲突', Colors.orange),
      ConflictType.moveConflict => ('移动冲突', Colors.blue),
      ConflictType.deleteModifyConflict => ('删除/修改冲突', Colors.red),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11),
      ),
    );
  }

  Widget _buildDiffSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildContentPreview(
                context,
                label: '本地版本',
                content: widget.conflict.localContent,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildContentPreview(
                context,
                label: '远程版本',
                content: widget.conflict.remoteContent,
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () {
              DiffViewerDialog.show(
                context: context,
                localContent: widget.conflict.localContent,
                remoteContent: widget.conflict.remoteContent,
                title: '差异对比 - ${widget.conflict.blockId}',
              );
            },
            icon: const Icon(Icons.compare, size: 16),
            label: const Text('查看详细差异'),
          ),
        ),
      ],
    );
  }

  Widget _buildContentPreview(
    BuildContext context, {
    required String label,
    required String content,
    required Color color,
  }) {
    final preview = content.length > 80
        ? '${content.substring(0, 80)}...'
        : content;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            preview.isEmpty ? '(空)' : preview,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceSelector(BuildContext context) {
    return Column(
      children: [
        RadioListTile<ConflictChoice>(
          title: const Text('保留本地版本'),
          value: ConflictChoice.local,
          groupValue: _choice,
          onChanged: (value) => setState(() => _choice = value!),
        ),
        RadioListTile<ConflictChoice>(
          title: const Text('保留远程版本'),
          value: ConflictChoice.remote,
          groupValue: _choice,
          onChanged: (value) => setState(() => _choice = value!),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FilledButton.icon(
          onPressed: () {
            final resolvedContent = switch (_choice) {
              ConflictChoice.local => widget.conflict.localContent,
              ConflictChoice.remote => widget.conflict.remoteContent,
            };
            context.read<SyncBloc>().add(ResolveConflict(
                  blockId: widget.conflict.blockId,
                  resolvedContent: resolvedContent,
                ));
          },
          icon: const Icon(Icons.check, size: 18),
          label: const Text('解决'),
        ),
      ],
    );
  }
}

enum ConflictChoice {
  local,
  remote,
}
