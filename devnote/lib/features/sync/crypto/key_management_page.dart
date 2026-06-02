import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'e2e_crypto_service.dart';

class KeyManagementPage extends StatefulWidget {
  const KeyManagementPage({super.key});

  @override
  State<KeyManagementPage> createState() => _KeyManagementPageState();
}

class _KeyManagementPageState extends State<KeyManagementPage> {
  final E2ECryptoService _cryptoService = E2ECryptoService.instance;
  bool _isExporting = false;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _cryptoService.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _handleExport() async {
    final password = await showDialog<String>(
      context: context,
      builder: (context) => const _PasswordInputDialog(
        title: '导出密钥备份',
        hint: '设置备份加密密码',
      ),
    );

    if (password == null || !mounted) return;

    setState(() => _isExporting = true);

    final backup = await _cryptoService.exportKeyBackup(password);

    if (!mounted) return;
    setState(() => _isExporting = false);

    if (backup != null) {
      await Clipboard.setData(ClipboardData(text: backup));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密钥备份已复制到剪贴板')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出失败')),
        );
      }
    }
  }

  Future<void> _handleImport() async {
    final result = await showDialog<_ImportData>(
      context: context,
      builder: (context) => const _ImportBackupDialog(),
    );

    if (result == null || !mounted) return;

    setState(() => _isImporting = true);

    final success = await _cryptoService.importKeyBackup(
      result.backupData,
      result.password,
    );

    if (!mounted) return;
    setState(() => _isImporting = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密钥导入成功')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密钥导入失败，请检查备份数据和密码')),
      );
    }
  }

  Future<void> _handleKeyRotation() async {
    final password = await showDialog<String>(
      context: context,
      builder: (context) => const _PasswordInputDialog(
        title: '密钥轮换',
        hint: '输入当前密码以确认轮换',
      ),
    );

    if (password == null || !mounted) return;

    final success = await _cryptoService.rotateKey(password);
    if (mounted) {
      setState(() {});
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密钥已轮换')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密钥轮换失败')),
        );
      }
    }
  }

  Future<void> _handleDisable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('禁用端到端加密'),
        content: const Text('禁用后同步数据将不再加密，确定要继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('禁用'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _cryptoService.disable();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = _cryptoService.state;
    final isConfigured = state.status != E2ECryptoStatus.notConfigured;

    return Scaffold(
      appBar: AppBar(
        title: const Text('密钥管理'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusCard(context, state),
          const SizedBox(height: 24),
          if (isConfigured) ...[
            _SectionTitle(title: '当前密钥'),
            const SizedBox(height: 8),
            _buildCurrentKeyCard(context, state),
            const SizedBox(height: 24),
            if (state.previousKey != null) ...[
              _SectionTitle(title: '上一密钥'),
              const SizedBox(height: 8),
              _buildPreviousKeyCard(context, state),
              const SizedBox(height: 24),
            ],
            _SectionTitle(title: '密钥操作'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _isExporting ? null : _handleExport,
              icon: _isExporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: const Text('导出密钥备份'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isImporting ? null : _handleImport,
              icon: _isImporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: const Text('导入密钥备份'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _handleKeyRotation,
              icon: const Icon(Icons.sync),
              label: const Text('轮换密钥'),
            ),
            if (_cryptoService.needsKeyRotation()) ...[
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '密钥已超过轮换周期，建议尽快轮换',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _handleDisable,
              icon: const Icon(Icons.lock_open),
              label: const Text('禁用端到端加密'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '端到端加密未配置',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '请先完成端到端加密设置向导',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, E2ECryptoState state) {
    final statusColor = switch (state.status) {
      E2ECryptoStatus.notConfigured => Theme.of(context).colorScheme.outline,
      E2ECryptoStatus.configured => Theme.of(context).colorScheme.primary,
      E2ECryptoStatus.active => Colors.green,
      E2ECryptoStatus.keyRotating => Colors.orange,
      E2ECryptoStatus.error => Theme.of(context).colorScheme.error,
    };

    final statusText = switch (state.status) {
      E2ECryptoStatus.notConfigured => '未配置',
      E2ECryptoStatus.configured => '已配置',
      E2ECryptoStatus.active => '活跃',
      E2ECryptoStatus.keyRotating => '轮换中',
      E2ECryptoStatus.error => '错误',
    };

    final statusIcon = switch (state.status) {
      E2ECryptoStatus.notConfigured => Icons.lock_open,
      E2ECryptoStatus.configured => Icons.lock,
      E2ECryptoStatus.active => Icons.verified_user,
      E2ECryptoStatus.keyRotating => Icons.sync,
      E2ECryptoStatus.error => Icons.error,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('加密状态', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    '算法: ${state.algorithm}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusText,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentKeyCard(BuildContext context, E2ECryptoState state) {
    final key = state.currentKey;
    if (key == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.vpn_key, size: 20),
                const SizedBox(width: 8),
                Text('当前密钥', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '活跃',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _KeyInfoRow(label: '密钥ID', value: _truncateKeyId(key.keyId)),
            const SizedBox(height: 4),
            _KeyInfoRow(label: '创建时间', value: _formatDate(key.createdAt)),
            if (state.lastKeyRotation != null) ...[
              const SizedBox(height: 4),
              _KeyInfoRow(
                label: '上次轮换',
                value: _formatDate(state.lastKeyRotation!),
              ),
            ],
            const SizedBox(height: 4),
            _KeyInfoRow(
              label: '轮换周期',
              value: '${state.keyRotationIntervalDays} 天',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviousKeyCard(BuildContext context, E2ECryptoState state) {
    final key = state.previousKey;
    if (key == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.vpn_key_outlined, size: 20),
                const SizedBox(width: 8),
                Text('上一密钥', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '已替换',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _KeyInfoRow(label: '密钥ID', value: _truncateKeyId(key.keyId)),
            const SizedBox(height: 4),
            _KeyInfoRow(label: '创建时间', value: _formatDate(key.createdAt)),
          ],
        ),
      ),
    );
  }

  String _truncateKeyId(String keyId) {
    if (keyId.length <= 16) return keyId;
    return '${keyId.substring(0, 8)}...${keyId.substring(keyId.length - 8)}';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _KeyInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _KeyInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _PasswordInputDialog extends StatefulWidget {
  final String title;
  final String hint;

  const _PasswordInputDialog({required this.title, required this.hint});

  @override
  State<_PasswordInputDialog> createState() => _PasswordInputDialogState();
}

class _PasswordInputDialogState extends State<_PasswordInputDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        obscureText: _obscure,
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.hint,
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_controller.text.length < 6) {
              setState(() => _error = '密码长度至少6位');
              return;
            }
            Navigator.of(context).pop(_controller.text);
          },
          child: const Text('确认'),
        ),
      ],
    );
  }
}

class _ImportData {
  final String backupData;
  final String password;

  const _ImportData({required this.backupData, required this.password});
}

class _ImportBackupDialog extends StatefulWidget {
  const _ImportBackupDialog();

  @override
  State<_ImportBackupDialog> createState() => _ImportBackupDialogState();
}

class _ImportBackupDialogState extends State<_ImportBackupDialog> {
  final _backupController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _backupController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入密钥备份'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _backupController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '备份数据',
              hintText: '粘贴密钥备份字符串',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: '备份密码',
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_backupController.text.isEmpty || _passwordController.text.length < 6) return;
            Navigator.of(context).pop(_ImportData(
              backupData: _backupController.text,
              password: _passwordController.text,
            ));
          },
          child: const Text('导入'),
        ),
      ],
    );
  }
}
