import 'package:flutter/material.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import '../../../core/di/injection.dart';
import 'services/version_history_service.dart';

class VersionHistoryPage extends StatefulWidget {
  final String noteId;
  final String currentContent;
  final Function(String content) onRestore;

  const VersionHistoryPage({
    super.key,
    required this.noteId,
    required this.currentContent,
    required this.onRestore,
  });

  @override
  State<VersionHistoryPage> createState() => _VersionHistoryPageState();
}

class _VersionHistoryPageState extends State<VersionHistoryPage> {
  final _service = getIt<VersionHistoryService>();
  List<VersionItem> _versions = [];
  VersionItem? _selectedVersion;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final versions = await _service.getNoteHistory(widget.noteId);
      setState(() {
        _versions = versions;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('版本历史'),
        actions: [
          if (_selectedVersion != null)
            TextButton.icon(
              icon: const Icon(Icons.restore, color: Colors.white),
              label: const Text('恢复此版本', style: TextStyle(color: Colors.white)),
              onPressed: _showRestoreConfirm,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('加载失败: $_error'))
              : _versions.isEmpty
                  ? const Center(child: Text('暂无版本历史'))
                  : Row(
                      children: [
                        // 左侧：版本列表
                        SizedBox(
                          width: 280,
                          child: _buildVersionList(),
                        ),
                        const VerticalDivider(width: 1),
                        // 右侧：版本内容预览
                        Expanded(
                          child: _selectedVersion != null
                              ? _buildVersionPreview()
                              : const Center(child: Text('选择一个版本查看')),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildVersionList() {
    return ListView.builder(
      itemCount: _versions.length,
      itemBuilder: (context, index) {
        final version = _versions[index];
        final isSelected = _selectedVersion?.version == version.version;
        final isLatest = index == 0;

        return ListTile(
          selected: isSelected,
          leading: Icon(
            isLatest ? Icons.history : Icons.history_toggle_off,
            color: isLatest ? Theme.of(context).colorScheme.primary : Colors.grey,
          ),
          title: Text(
            isLatest ? '当前版本 (v${version.version})' : '版本 v${version.version}',
            style: TextStyle(
              fontWeight: isLatest ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(_formatDateTime(version.createdAt)),
          trailing: isSelected
              ? const Icon(Icons.chevron_right)
              : null,
          onTap: () {
            setState(() => _selectedVersion = version);
          },
        );
      },
    );
  }

  Widget _buildVersionPreview() {
    final content = _selectedVersion!.content;
    final isLatest = _selectedVersion!.version == _versions.first.version;

    return Column(
      children: [
        // 版本信息栏
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Text(
                '版本 v${_selectedVersion!.version}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 16),
              Text(
                _formatDateTime(_selectedVersion!.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              if (!isLatest)
                Chip(
                  label: const Text('历史版本'),
                  backgroundColor: Colors.orange.withAlpha(30),
                ),
            ],
          ),
        ),
        // 内容预览
        Expanded(
          child: isLatest
              ? _buildContentViewer(content)
              : _buildDiffViewer(content),
        ),
      ],
    );
  }

  Widget _buildContentViewer(String content) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        content,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  Widget _buildDiffViewer(String historicalContent) {
    // 使用 diff_match_patch 生成差异视图
    final dmp = DiffMatchPatch();
    final diffs = dmp.diff(widget.currentContent, historicalContent);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: diffs.map((diff) {
            final text = diff.text;
            if (diff.operation == DIFF_INSERT) {
              return TextSpan(
                text: text,
                style: const TextStyle(
                  color: Colors.green,
                  backgroundColor: Color(0x3000C853),
                ),
              );
            } else if (diff.operation == DIFF_DELETE) {
              return TextSpan(
                text: text,
                style: const TextStyle(
                  color: Colors.red,
                  backgroundColor: Color(0x30F44336),
                  decoration: TextDecoration.lineThrough,
                ),
              );
            } else {
              return TextSpan(text: text);
            }
          }).toList(),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showRestoreConfirm() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复版本'),
        content: Text('确定要恢复到版本 v${_selectedVersion!.version} 吗？\n'
            '当前版本将被替换，但您可以在版本历史中找到它。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              widget.onRestore(_selectedVersion!.content);
              Navigator.pop(context); // 关闭对话框
              Navigator.pop(context); // 关闭版本历史页
            },
            child: const Text('恢复'),
          ),
        ],
      ),
    );
  }
}
