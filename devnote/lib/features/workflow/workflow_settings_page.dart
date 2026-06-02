import 'package:flutter/material.dart';
import 'package:devnote/features/workflow/git_service.dart';

class WorkflowSettingsPage extends StatefulWidget {
  const WorkflowSettingsPage({super.key});

  @override
  State<WorkflowSettingsPage> createState() => _WorkflowSettingsPageState();
}

class _WorkflowSettingsPageState extends State<WorkflowSettingsPage> {
  final GitService _gitService = GitService();
  final TextEditingController _repoPathController = TextEditingController();
  final TextEditingController _watchDirController = TextEditingController();
  final TextEditingController _githubTokenController = TextEditingController();
  final TextEditingController _githubRepoController = TextEditingController();
  final TextEditingController _githubOwnerController = TextEditingController();

  bool _autoCommit = false;
  bool _gitInitialized = false;
  bool _githubEnabled = false;

  @override
  void dispose() {
    _repoPathController.dispose();
    _watchDirController.dispose();
    _githubTokenController.dispose();
    _githubRepoController.dispose();
    _githubOwnerController.dispose();
    super.dispose();
  }

  Future<void> _initGitRepo() async {
    try {
      await _gitService.init(_repoPathController.text);
      setState(() {
        _gitInitialized = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Git 仓库初始化成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('初始化失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('工作流设置'),
      ),
      body: ListView(
        children: [
          _SettingsSection(title: 'Git 版本管理', children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _repoPathController,
                decoration: const InputDecoration(
                  labelText: '仓库路径',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _gitInitialized ? null : _initGitRepo,
                  child: Text(_gitInitialized ? '已初始化' : '初始化仓库'),
                ),
              ),
            ),
            SwitchListTile(
              title: const Text('自动提交'),
              subtitle: const Text('笔记变更时自动创建提交'),
              value: _autoCommit,
              onChanged: (value) {
                setState(() {
                  _autoCommit = value;
                });
              },
            ),
          ]),
          _SettingsSection(title: '外部编辑器监控', children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _watchDirController,
                decoration: const InputDecoration(
                  labelText: '监控目录',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ]),
          _SettingsSection(title: 'GitHub 集成', children: [
            SwitchListTile(
              title: const Text('启用 GitHub 集成'),
              value: _githubEnabled,
              onChanged: (value) {
                setState(() {
                  _githubEnabled = value;
                });
              },
            ),
            if (_githubEnabled) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _githubTokenController,
                  decoration: const InputDecoration(
                    labelText: 'Access Token',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _githubOwnerController,
                  decoration: const InputDecoration(
                    labelText: 'Owner',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _githubRepoController,
                  decoration: const InputDecoration(
                    labelText: 'Repository',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        ...children,
        const Divider(),
      ],
    );
  }
}
