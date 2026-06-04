import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:diff_match_patch/diff_match_patch.dart' as dmp;

import 'package:devnote/features/sync/bloc/sync_bloc.dart';
import 'package:devnote/features/sync/bloc/sync_event.dart';
import 'package:devnote/features/sync/bloc/sync_state.dart';
import 'package:devnote/features/sync/conflict/conflict_resolver.dart';

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
          if (state is! SyncConflict || state.conflicts.isEmpty) {
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

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: state.conflicts.length,
            itemBuilder: (context, index) {
              return _ConflictDiffCard(
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

/// Per-block conflict resolution choice
enum BlockChoice {
  local,
  remote,
  unresolved,
}

/// Represents a diff block for per-block conflict resolution
class DiffBlock {
  final String localText;
  final String remoteText;
  final List<dmp.Diff> diffs;
  BlockChoice choice;

  DiffBlock({
    required this.localText,
    required this.remoteText,
    required this.diffs,
    this.choice = BlockChoice.unresolved,
  });

  String get resolvedText {
    switch (choice) {
      case BlockChoice.local:
        return localText;
      case BlockChoice.remote:
        return remoteText;
      case BlockChoice.unresolved:
        return localText;
    }
  }
}

class _ConflictDiffCard extends StatefulWidget {
  final ConflictInfo conflict;
  final int index;
  final int total;

  const _ConflictDiffCard({
    required this.conflict,
    required this.index,
    required this.total,
  });

  @override
  State<_ConflictDiffCard> createState() => _ConflictDiffCardState();
}

class _ConflictDiffCardState extends State<_ConflictDiffCard> {
  bool _expanded = false;
  List<DiffBlock> _diffBlocks = [];
  Map<int, BlockChoice> _blockChoices = {};

  @override
  void initState() {
    super.initState();
    _computeDiffBlocks();
  }

  void _computeDiffBlocks() {
    final differ = dmp.DiffMatchPatch();
    final diffs = differ.diff(widget.conflict.localContent, widget.conflict.remoteContent);

    final blocks = <DiffBlock>[];
    var localBuffer = StringBuffer();
    var remoteBuffer = StringBuffer();
    var hasDifference = false;

    for (final diff in diffs) {
      if (diff.operation == dmp.Operation.equal) {
        if (hasDifference && (localBuffer.isNotEmpty || remoteBuffer.isNotEmpty)) {
          blocks.add(DiffBlock(
            localText: localBuffer.toString(),
            remoteText: remoteBuffer.toString(),
            diffs: differ.diff(localBuffer.toString(), remoteBuffer.toString()),
          ));
          localBuffer.clear();
          remoteBuffer.clear();
          hasDifference = false;
        }
        // Add equal text to both
        localBuffer.write(diff.text);
        remoteBuffer.write(diff.text);
        // Flush equal block
        blocks.add(DiffBlock(
          localText: localBuffer.toString(),
          remoteText: remoteBuffer.toString(),
          diffs: [diff],
        ));
        localBuffer.clear();
        remoteBuffer.clear();
      } else if (diff.operation == dmp.Operation.delete) {
        localBuffer.write(diff.text);
        hasDifference = true;
      } else if (diff.operation == dmp.Operation.insert) {
        remoteBuffer.write(diff.text);
        hasDifference = true;
      }
    }

    // Flush remaining
    if (hasDifference && (localBuffer.isNotEmpty || remoteBuffer.isNotEmpty)) {
      blocks.add(DiffBlock(
        localText: localBuffer.toString(),
        remoteText: remoteBuffer.toString(),
        diffs: differ.diff(localBuffer.toString(), remoteBuffer.toString()),
      ));
    }

    setState(() {
      _diffBlocks = blocks;
      _blockChoices = {
        for (var i = 0; i < blocks.length; i++)
          i: blocks[i].diffs.length == 1 &&
                  blocks[i].diffs[0].operation == dmp.Operation.equal
              ? BlockChoice.local // Equal blocks default to local
              : BlockChoice.unresolved,
      };
    });
  }

  bool get _allResolved => _blockChoices.values.every(
        (c) => c != BlockChoice.unresolved,
      );

  String get _mergedContent {
    final buffer = StringBuffer();
    for (var i = 0; i < _diffBlocks.length; i++) {
      final choice = _blockChoices[i] ?? BlockChoice.local;
      switch (choice) {
        case BlockChoice.local:
          buffer.write(_diffBlocks[i].localText);
        case BlockChoice.remote:
          buffer.write(_diffBlocks[i].remoteText);
        case BlockChoice.unresolved:
          buffer.write(_diffBlocks[i].localText);
      }
    }
    return buffer.toString();
  }

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
                  _buildSideBySideDiff(context),
                  const SizedBox(height: 16),
                  _buildBulkActions(context),
                  const SizedBox(height: 12),
                  _buildPerBlockResolution(context),
                  const SizedBox(height: 16),
                  _buildResolveButton(context),
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

  Widget _buildSideBySideDiff(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '差异对比',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildDiffSide(
                context,
                label: '本地版本',
                content: widget.conflict.localContent,
                isLocal: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDiffSide(
                context,
                label: '远程版本',
                content: widget.conflict.remoteContent,
                isLocal: false,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDiffSide(
    BuildContext context, {
    required String label,
    required String content,
    required bool isLocal,
  }) {
    final differ = dmp.DiffMatchPatch();
    final diffs = differ.diff(
      widget.conflict.localContent,
      widget.conflict.remoteContent,
    );

    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: (isLocal ? Colors.blue : Colors.green).withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (isLocal ? Colors.blue : Colors.green).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (isLocal ? Colors.blue : Colors.green).withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isLocal ? Colors.blue : Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: _buildDiffSpans(context, diffs, isLocal),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffSpans(
    BuildContext context,
    List<dmp.Diff> diffs,
    bool isLocal,
  ) {
    final spans = <TextSpan>[];

    for (final diff in diffs) {
      Color? backgroundColor;
      Color? textColor;
      TextDecoration? decoration;

      if (diff.operation == dmp.Operation.equal) {
        backgroundColor = null;
        textColor = Theme.of(context).textTheme.bodySmall!.color;
      } else if (diff.operation == dmp.Operation.delete && isLocal) {
        backgroundColor = Colors.red.withValues(alpha: 0.2);
        textColor = Colors.red.shade800;
        decoration = TextDecoration.lineThrough;
      } else if (diff.operation == dmp.Operation.insert && !isLocal) {
        backgroundColor = Colors.green.withValues(alpha: 0.2);
        textColor = Colors.green.shade800;
      } else if (diff.operation == dmp.Operation.delete && !isLocal) {
        // Skip deletions on remote side
        continue;
      } else if (diff.operation == dmp.Operation.insert && isLocal) {
        // Skip insertions on local side
        continue;
      }

      spans.add(TextSpan(
        text: diff.text,
        style: TextStyle(
          color: textColor,
          backgroundColor: backgroundColor,
          decoration: decoration,
          fontSize: 12,
        ),
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
      softWrap: true,
    );
  }

  Widget _buildBulkActions(BuildContext context) {
    return Row(
      children: [
        Text(
          '快速操作：',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: () {
            setState(() {
              for (var i = 0; i < _diffBlocks.length; i++) {
                _blockChoices[i] = BlockChoice.local;
              }
            });
          },
          icon: const Icon(Icons.phone_android, size: 16),
          label: const Text('保留本地'),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: () {
            setState(() {
              for (var i = 0; i < _diffBlocks.length; i++) {
                _blockChoices[i] = BlockChoice.remote;
              }
            });
          },
          icon: const Icon(Icons.cloud, size: 16),
          label: const Text('保留远程'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              for (var i = 0; i < _diffBlocks.length; i++) {
                final block = _diffBlocks[i];
                // Equal blocks default to local, different blocks stay unresolved
                if (block.diffs.length == 1 &&
                    block.diffs[0].operation == dmp.Operation.equal) {
                  _blockChoices[i] = BlockChoice.local;
                } else {
                  _blockChoices[i] = BlockChoice.unresolved;
                }
              }
            });
          },
          icon: const Icon(Icons.merge, size: 16),
          label: const Text('自定义合并'),
        ),
      ],
    );
  }

  Widget _buildPerBlockResolution(BuildContext context) {
    final conflictBlocks = <int, DiffBlock>{};
    for (var i = 0; i < _diffBlocks.length; i++) {
      final block = _diffBlocks[i];
      // Only show blocks that have differences
      if (block.diffs.length != 1 ||
          block.diffs[0].operation != dmp.Operation.equal) {
        conflictBlocks[i] = block;
      }
    }

    if (conflictBlocks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          '无内容差异',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '逐块选择 (${conflictBlocks.length} 处差异)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ...conflictBlocks.entries.map((entry) {
          final idx = entry.key;
          final block = entry.value;
          final choice = _blockChoices[idx] ?? BlockChoice.unresolved;

          return _PerBlockSelector(
            block: block,
            blockIndex: idx,
            choice: choice,
            onChoiceChanged: (newChoice) {
              setState(() {
                _blockChoices[idx] = newChoice;
              });
            },
          );
        }),
      ],
    );
  }

  Widget _buildResolveButton(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (!_allResolved)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '还有未选择的差异块',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
        FilledButton.icon(
          onPressed: _allResolved
              ? () {
                  context.read<SyncBloc>().add(ResolveConflict(
                        blockId: widget.conflict.blockId,
                        resolvedContent: _mergedContent,
                      ));
                }
              : null,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('解决'),
        ),
      ],
    );
  }
}

class _PerBlockSelector extends StatelessWidget {
  final DiffBlock block;
  final int blockIndex;
  final BlockChoice choice;
  final ValueChanged<BlockChoice> onChoiceChanged;

  const _PerBlockSelector({
    required this.block,
    required this.blockIndex,
    required this.choice,
    required this.onChoiceChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: choice == BlockChoice.unresolved
              ? Colors.orange.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show the diff for this block
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildBlockContent(
                    context,
                    label: '本地',
                    text: block.localText,
                    color: Colors.blue,
                    isAdded: false,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildBlockContent(
                    context,
                    label: '远程',
                    text: block.remoteText,
                    color: Colors.green,
                    isAdded: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Choice buttons
            Row(
              children: [
                _buildChoiceChip(
                  context,
                  label: '保留本地',
                  value: BlockChoice.local,
                  color: Colors.blue,
                ),
                const SizedBox(width: 8),
                _buildChoiceChip(
                  context,
                  label: '保留远程',
                  value: BlockChoice.remote,
                  color: Colors.green,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockContent(
    BuildContext context, {
    required String label,
    required String text,
    required Color color,
    required bool isAdded,
  }) {
    final displayText = text.length > 100 ? '${text.substring(0, 100)}...' : text;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            displayText.isEmpty ? '(空)' : displayText,
            style: TextStyle(
              fontSize: 11,
              color: isAdded ? Colors.green.shade800 : Colors.red.shade800,
              decoration: isAdded ? null : (text.isNotEmpty ? TextDecoration.lineThrough : null),
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceChip(
    BuildContext context, {
    required String label,
    required BlockChoice value,
    required Color color,
  }) {
    final isSelected = choice == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: color.withValues(alpha: 0.2),
      side: BorderSide(
        color: isSelected ? color : Colors.grey.withValues(alpha: 0.3),
      ),
      labelStyle: TextStyle(
        color: isSelected ? color : null,
        fontSize: 12,
      ),
      onSelected: (_) => onChoiceChanged(value),
    );
  }
}
