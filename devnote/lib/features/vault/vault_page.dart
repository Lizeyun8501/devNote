// P1-7: Vault 保险库页面
// 对标 Notesnook 的 Vault 功能：管理敏感笔记的二次加密
// 提供设置密码、解锁、查看/移出保险库笔记的完整 UI

import 'package:flutter/material.dart';

import '../../../core/di/injection.dart';
import 'services/vault_service.dart';

class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  final _vaultService = getIt<VaultService>();
  List<VaultNote> _notes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkVaultStatus();
  }

  Future<void> _checkVaultStatus() async {
    final isSet = await _vaultService.isVaultSet();
    if (!isSet) {
      // 首次使用，引导设置密码
      if (mounted) {
        _showSetupDialog();
      }
    } else if (!_vaultService.isUnlocked) {
      // 需要解锁
      if (mounted) {
        _showUnlockDialog();
      }
    } else {
      _loadNotes();
    }
  }

  Future<void> _loadNotes() async {
    final notes = await _vaultService.getVaultNotes();
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  void _showSetupDialog() {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('设置保险库密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '保险库密码用于加密敏感笔记。请牢记此密码，丢失后无法恢复。',
              style: TextStyle(color: Colors.orange),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '确认密码',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              if (passwordController.text != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('两次密码不一致')),
                );
                return;
              }
              if (passwordController.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('密码至少 6 位')),
                );
                return;
              }
              await _vaultService.setupVault(passwordController.text);
              if (context.mounted) Navigator.pop(context);
              _loadNotes();
            },
            child: const Text('设置'),
          ),
        ],
      ),
    );
  }

  void _showUnlockDialog() {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('解锁保险库'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '密码',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) async {
            final success = await _vaultService.unlock(passwordController.text);
            if (success) {
              if (context.mounted) Navigator.pop(context);
              _loadNotes();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('密码错误')),
              );
            }
          },
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              final success = await _vaultService.unlock(passwordController.text);
              if (success) {
                if (context.mounted) Navigator.pop(context);
                _loadNotes();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('密码错误')),
                );
              }
            },
            child: const Text('解锁'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _vaultService.checkAutoLock();

    return Scaffold(
      appBar: AppBar(
        title: const Text('保险库'),
        actions: [
          if (_vaultService.isUnlocked)
            IconButton(
              icon: const Icon(Icons.lock),
              tooltip: '锁定',
              onPressed: () {
                _vaultService.lock();
                setState(() {
                  _notes = [];
                  _loading = true;
                });
                _showUnlockDialog();
              },
            ),
        ],
      ),
      body: !_vaultService.isUnlocked
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('保险库已锁定'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.lock_open),
                    label: const Text('解锁'),
                    onPressed: _showUnlockDialog,
                  ),
                ],
              ),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _notes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.security, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('保险库为空'),
                          const SizedBox(height: 8),
                          Text(
                            '将笔记标记为敏感即可加入保险库',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _notes.length,
                      itemBuilder: (context, index) {
                        final note = _notes[index];
                        return ListTile(
                          leading: const Icon(Icons.lock),
                          title: Text(note.title),
                          subtitle: Text('添加于 ${_formatDate(note.addedAt)}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _removeNote(note.id),
                          ),
                          onTap: () => _viewNote(note),
                        );
                      },
                    ),
    );
  }

  void _viewNote(VaultNote note) async {
    final content = await _vaultService.getFromVault(note.id);
    if (content == null) return;
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note.title),
        content: SingleChildScrollView(
          child: SelectableText(content),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _removeNote(String noteId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移出保险库'),
        content: const Text('确定要将此笔记移出保险库吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移出'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _vaultService.removeFromVault(noteId);
      _loadNotes();
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
