import 'package:flutter/material.dart';
import 'package:devnote/core/observability/app_logger.dart';
import 'package:devnote/features/workflow/git_service.dart';

class CommitDialog extends StatefulWidget {
  const CommitDialog({super.key});

  @override
  State<CommitDialog> createState() => _CommitDialogState();
}

class _CommitDialogState extends State<CommitDialog> {
  final GitService _gitService = GitService();
  final TextEditingController _messageController = TextEditingController();
  GitStatusModel? _status;
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await _gitService.status();
      if (mounted) {
        setState(() {
          _status = status;
        });
      }
    } catch (e) {
      // 加载 git status 失败，静默失败不阻塞 UI
      AppLogger.w('Git', 'Git status load failed', error: e);
    }
  }

  Future<void> _commit() async {
    if (_messageController.text.trim().isEmpty) return;

    setState(() {
      _committing = true;
    });

    try {
      await _gitService.commit(_messageController.text.trim());
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提交失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _committing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('提交变更'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: '提交信息',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              autofocus: true,
            ),
            const SizedBox(height: 16),
            Text(
              '变更文件',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (_status == null)
              const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
            else if (!_status!.hasChanges)
              const Text('没有待提交的变更')
            else ...[
              if (_status!.added.isNotEmpty)
                _FileList(title: '新增', files: _status!.added, color: Colors.green),
              if (_status!.modified.isNotEmpty)
                _FileList(title: '修改', files: _status!.modified, color: Colors.orange),
              if (_status!.deleted.isNotEmpty)
                _FileList(title: '删除', files: _status!.deleted, color: Colors.red),
              if (_status!.untracked.isNotEmpty)
                _FileList(title: '未跟踪', files: _status!.untracked, color: Colors.grey),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _committing ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _committing || _messageController.text.trim().isEmpty ? null : _commit,
          child: _committing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('提交'),
        ),
      ],
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList({
    required this.title,
    required this.files,
    required this.color,
  });

  final String title;
  final List<String> files;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '$title (${files.length})',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        ...files.map((file) => Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text(
                file,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )),
      ],
    );
  }
}
