import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'e2e_crypto_service.dart';

class E2ESetupPage extends StatefulWidget {
  const E2ESetupPage({super.key});

  @override
  State<E2ESetupPage> createState() => _E2ESetupPageState();
}

class _E2ESetupPageState extends State<E2ESetupPage> {
  final _pageController = PageController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _backupPasswordController = TextEditingController();

  int _currentPage = 0;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _obscureBackup = true;
  bool _isGenerating = false;
  bool _isExporting = false;
  String? _errorText;
  String? _backupKey;

  static const int _totalPages = 3;

  @override
  void dispose() {
    _pageController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _backupPasswordController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage++);
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPage--);
    }
  }

  Future<void> _handleGenerateKeyPair() async {
    if (_passwordController.text.length < 6) {
      setState(() => _errorText = '密码长度至少6位');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorText = '两次输入的密码不一致');
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorText = null;
    });

    final success = await E2ECryptoService.instance.generateKeyPair(
      _passwordController.text,
    );

    if (!mounted) return;

    setState(() => _isGenerating = false);

    if (success) {
      _nextPage();
    } else {
      setState(() => _errorText = '密钥对生成失败');
    }
  }

  Future<void> _handleBackupKey() async {
    if (_backupPasswordController.text.length < 6) {
      setState(() => _errorText = '备份密码长度至少6位');
      return;
    }

    setState(() {
      _isExporting = true;
      _errorText = null;
    });

    final backup = await E2ECryptoService.instance.exportKeyBackup(
      _backupPasswordController.text,
    );

    if (!mounted) return;

    setState(() => _isExporting = false);

    if (backup != null) {
      setState(() => _backupKey = backup);
    } else {
      setState(() => _errorText = '备份导出失败');
    }
  }

  void _handleCopyBackupKey() {
    if (_backupKey != null) {
      Clipboard.setData(ClipboardData(text: _backupKey!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('恢复密钥已复制到剪贴板')),
      );
    }
  }

  void _handleFinish() {
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('端到端加密设置'),
        leading: _currentPage > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _previousPage,
              )
            : null,
      ),
      body: Column(
        children: [
          _buildProgressIndicator(),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStep1GenerateKeyPair(),
                _buildStep2SetPassword(),
                _buildStep3BackupRecovery(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: List.generate(_totalPages, (index) {
          final isActive = index <= _currentPage;
          final isCurrent = index == _currentPage;
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(left: index > 0 ? 4 : 0),
              decoration: BoxDecoration(
                color: isActive
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
              child: isCurrent
                  ? Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    )
                  : null,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStep1GenerateKeyPair() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Icon(
              Icons.enhanced_encryption,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '生成密钥对',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '端到端加密将确保只有您可以访问您的数据。\n'
              '密钥对将用于加密同步数据，私钥永远不会离开此设备。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '服务器端只存储加密数据',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '密钥从不离开客户端',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '使用 XChaCha20-Poly1305 加密算法',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '使用 X25519 密钥交换协议',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _nextPage,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('开始设置'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2SetPassword() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Icon(
              Icons.password,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '设置加密密码',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '此密码将用于保护您的加密密钥。\n'
              '请务必牢记此密码，忘记后将无法恢复数据。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '加密密码',
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: '确认密码',
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isGenerating ? null : _handleGenerateKeyPair,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.vpn_key),
              label: Text(_isGenerating ? '生成中...' : '生成密钥对'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3BackupRecovery() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Icon(
              Icons.backup,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '备份恢复密钥',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '强烈建议备份您的恢复密钥。\n'
              '如果丢失设备或忘记密码，恢复密钥是找回数据的唯一方式。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 32),
          if (_backupKey == null) ...[
            TextField(
              controller: _backupPasswordController,
              obscureText: _obscureBackup,
              decoration: InputDecoration(
                labelText: '备份加密密码',
                suffixIcon: IconButton(
                  icon: Icon(_obscureBackup ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureBackup = !_obscureBackup),
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isExporting ? null : _handleBackupKey,
                icon: _isExporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file),
                label: Text(_isExporting ? '导出中...' : '导出恢复密钥'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _handleFinish,
                child: const Text('跳过备份'),
              ),
            ),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '恢复密钥',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _backupKey!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _handleCopyBackupKey,
                        icon: const Icon(Icons.copy),
                        label: const Text('复制到剪贴板'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
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
                        '请将恢复密钥保存到安全的地方，切勿分享给他人',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _handleFinish,
                icon: const Icon(Icons.check),
                label: const Text('完成设置'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
