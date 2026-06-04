import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:devnote/features/sync/bloc/sync_bloc.dart';
import 'package:devnote/features/sync/bloc/sync_event.dart';
import 'package:devnote/features/sync/bloc/sync_state.dart';

class SyncStatusWidget extends StatelessWidget {
  const SyncStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SyncBloc, SyncState>(
      builder: (context, state) {
        return InkWell(
          onTap: () => _showSyncDetails(context, state),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatusIcon(context, state),
                const SizedBox(width: 6),
                _buildStatusLabel(context, state),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusIcon(BuildContext context, SyncState state) {
    if (state is SyncInProgress) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.blue,
        ),
      );
    }

    final (icon, color) = switch (state) {
      SyncCompleted() => (Icons.check_circle, Colors.green),
      SyncConflict() => (Icons.error_outline, Colors.orange),
      SyncError() => (Icons.cloud_off, Colors.grey),
      SyncIdle() => (Icons.cloud_outlined, Colors.grey),
      SyncInProgress() => (Icons.sync, Colors.blue),
      _ => (Icons.cloud_outlined, Colors.grey),
    };

    return Icon(icon, size: 16, color: color);
  }

  Widget _buildStatusLabel(BuildContext context, SyncState state) {
    final label = switch (state) {
      SyncIdle() => '离线',
      SyncInProgress(:final pushCount, :final pullCount) =>
        '同步中 ↑$pushCount ↓$pullCount',
      SyncCompleted() => '已同步',
      SyncError(:final message) => '同步错误',
      SyncConflict(:final conflicts) => '${conflicts.length}个冲突',
      _ => '',
    };

    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }

  void _showSyncDetails(BuildContext context, SyncState state) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => _SyncDetailSheet(state: state),
    );
  }
}

class _SyncDetailSheet extends StatelessWidget {
  final SyncState state;

  const _SyncDetailSheet({required this.state});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '同步状态',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStatusRow(context),
          const SizedBox(height: 16),
          if (state is SyncCompleted)
            _buildLastSyncInfo(context, state as SyncCompleted),
          if (state is SyncError)
            _buildErrorInfo(context, state as SyncError),
          if (state is SyncConflict)
            _buildConflictInfo(context, state as SyncConflict),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    context.go('/settings/sync');
                  },
                  icon: const Icon(Icons.settings, size: 18),
                  label: const Text('同步设置'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: state is! SyncInProgress
                      ? () {
                          context.read<SyncBloc>().add(const StartSync());
                          Navigator.pop(context);
                        }
                      : null,
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('立即同步'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(BuildContext context) {
    final (icon, color, label) = switch (state) {
      SyncIdle() => (Icons.cloud_outlined, Colors.grey, '离线'),
      SyncInProgress() => (Icons.sync, Colors.blue, '同步中'),
      SyncCompleted() => (Icons.check_circle, Colors.green, '已同步'),
      SyncError() => (Icons.cloud_off, Colors.red, '同步错误'),
      SyncConflict() => (Icons.error_outline, Colors.orange, '存在冲突'),
      _ => (Icons.cloud_outlined, Colors.grey, '未知'),
    };

    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 12),
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _buildLastSyncInfo(BuildContext context, SyncCompleted completed) {
    final diff = DateTime.now().difference(completed.lastSyncTime);
    final timeAgo = diff.inMinutes < 1
        ? '刚刚'
        : diff.inHours < 1
            ? '${diff.inMinutes}分钟前'
            : diff.inDays < 1
                ? '${diff.inHours}小时前'
                : '${diff.inDays}天前';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.access_time,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              '上次同步: $timeAgo',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorInfo(BuildContext context, SyncError error) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              size: 16,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error.message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictInfo(BuildContext context, SyncConflict conflict) {
    return Card(
      color: Colors.orange.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.warning_amber, size: 16, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${conflict.conflicts.length}个冲突需要解决',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.orange.shade800,
                    ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/sync/conflicts');
              },
              child: const Text('解决'),
            ),
          ],
        ),
      ),
    );
  }
}
