import 'package:flutter/material.dart';
import 'package:devnote/features/workflow/git_service.dart';

class GitHistoryPage extends StatefulWidget {
  const GitHistoryPage({super.key});

  @override
  State<GitHistoryPage> createState() => _GitHistoryPageState();
}

class _GitHistoryPageState extends State<GitHistoryPage> {
  final GitService _gitService = GitService();
  List<GitCommitInfoModel> _commits = [];
  List<GitDiffEntryModel> _diffEntries = [];
  bool _loading = true;
  String? _selectedCommit;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final commits = await _gitService.log(maxCount: 50);
      setState(() {
        _commits = commits;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _showDiff(String commitHash) async {
    try {
      final diffs = await _gitService.diff(commitHash: commitHash);
      setState(() {
        _diffEntries = diffs;
        _selectedCommit = commitHash;
      });
    } catch (_) {}
  }

  Future<void> _checkout(String hash) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('版本回退'),
        content: Text('确定要回退到 $hash 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _gitService.checkout(hash);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已回退到指定版本')),
          );
          _loadHistory();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('回退失败: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Git 历史'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                Expanded(
                  flex: 1,
                  child: _commits.isEmpty
                      ? const Center(child: Text('暂无提交记录'))
                      : ListView.builder(
                          itemCount: _commits.length,
                          itemBuilder: (context, index) {
                            final commit = _commits[index];
                            final isSelected = _selectedCommit == commit.hash;
                            return ListTile(
                              selected: isSelected,
                              selectedTileColor:
                                  Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                              leading: CircleAvatar(
                                radius: 16,
                                child: Text(
                                  commit.hash.substring(0, 2).toUpperCase(),
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                              title: Text(commit.message),
                              subtitle: Text(
                                '${commit.author} · ${commit.date}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.undo, size: 18),
                                tooltip: '回退到此版本',
                                onPressed: () => _checkout(commit.hash),
                              ),
                              onTap: () => _showDiff(commit.hash),
                            );
                          },
                        ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 1,
                  child: _selectedCommit == null
                      ? const Center(child: Text('选择一个提交查看差异'))
                      : _diffEntries.isEmpty
                          ? const Center(child: Text('无差异信息'))
                          : ListView.builder(
                              itemCount: _diffEntries.length,
                              itemBuilder: (context, index) {
                                final diff = _diffEntries[index];
                                return ListTile(
                                  leading: Icon(
                                    diff.additions > 0
                                        ? Icons.add_circle_outline
                                        : diff.deletions > 0
                                            ? Icons.remove_circle_outline
                                            : Icons.edit_outlined,
                                    color: diff.additions > 0
                                        ? Colors.green
                                        : diff.deletions > 0
                                            ? Colors.red
                                            : null,
                                  ),
                                  title: Text(diff.file),
                                  subtitle: Text(
                                    '+${diff.additions} -${diff.deletions}',
                                    style: TextStyle(
                                      color: diff.additions > 0
                                          ? Colors.green
                                          : diff.deletions > 0
                                              ? Colors.red
                                              : null,
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
    );
  }
}
