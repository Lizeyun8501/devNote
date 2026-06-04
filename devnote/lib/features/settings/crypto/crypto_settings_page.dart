import 'package:flutter/material.dart';
import 'package:devnote/core/di/injection.dart';
import 'crypto_service.dart';
import 'widgets/password_dialog.dart';
import 'widgets/encryption_status_card.dart';

class CryptoSettingsPage extends StatefulWidget {
  const CryptoSettingsPage({super.key});

  @override
  State<CryptoSettingsPage> createState() => _CryptoSettingsPageState();
}

class _CryptoSettingsPageState extends State<CryptoSettingsPage> {
  final CryptoService _cryptoService = getIt<CryptoService>();

  @override
  void initState() {
    super.initState();
    _cryptoService.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _handleEnableEncryption() async {
    final password = await showDialog<String>(
      context: context,
      builder: (context) => const PasswordDialog(
        title: '设置加密密码',
        confirmLabel: '启用',
      ),
    );

    if (password == null || !mounted) return;

    final success = await _cryptoService.enableEncryption(password);
    if (mounted) {
      setState(() {});
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('启用加密失败，密码长度至少6位')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加密已启用')),
        );
      }
    }
  }

  Future<void> _handleDisableEncryption() async {
    final password = await showDialog<String>(
      context: context,
      builder: (context) => const PasswordDialog(
        title: '验证密码',
        confirmLabel: '禁用加密',
        requireConfirm: false,
      ),
    );

    if (password == null || !mounted) return;

    final success = await _cryptoService.disableEncryption(password);
    if (mounted) {
      setState(() {});
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密码错误，无法禁用加密')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加密已禁用')),
        );
      }
    }
  }

  Future<void> _handleChangePassword() async {
    final oldPassword = await showDialog<String>(
      context: context,
      builder: (context) => const PasswordDialog(
        title: '输入当前密码',
        confirmLabel: '下一步',
        requireConfirm: false,
      ),
    );

    if (oldPassword == null || !mounted) return;

    final newPassword = await showDialog<String>(
      context: context,
      builder: (context) => const PasswordDialog(
        title: '设置新密码',
        confirmLabel: '修改',
      ),
    );

    if (newPassword == null || !mounted) return;

    final success = await _cryptoService.changePassword(oldPassword, newPassword);
    if (mounted) {
      setState(() {});
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密码修改失败，请检查当前密码是否正确')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密码已修改')),
        );
      }
    }
  }

  Future<void> _handleUnlock() async {
    final password = await showDialog<String>(
      context: context,
      builder: (context) => const PasswordDialog(
        title: '输入密码解锁',
        confirmLabel: '解锁',
        requireConfirm: false,
      ),
    );

    if (password == null || !mounted) return;

    final success = await _cryptoService.unlock(password);
    if (mounted) {
      setState(() {});
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密码错误')),
        );
      }
    }
  }

  void _handleLock() {
    _cryptoService.lock();
    setState(() {});
  }

  Future<void> _handleStrengthChange(CryptoStrength? strength) async {
    if (strength == null) return;
    await _cryptoService.setStrength(strength);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = _cryptoService.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('加密设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const EncryptionStatusCard(),
          const SizedBox(height: 24),
          _SectionTitle(title: '加密控制'),
          const SizedBox(height: 8),
          if (!state.isEnabled) ...[
            FilledButton.icon(
              onPressed: _handleEnableEncryption,
              icon: const Icon(Icons.lock),
              label: const Text('启用加密'),
            ),
          ] else ...[
            if (state.isUnlocked) ...[
              OutlinedButton.icon(
                onPressed: _handleLock,
                icon: const Icon(Icons.lock),
                label: const Text('锁定'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _handleChangePassword,
                icon: const Icon(Icons.key),
                label: const Text('修改密码'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _handleDisableEncryption,
                icon: const Icon(Icons.lock_open),
                label: const Text('禁用加密'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: _handleUnlock,
                icon: const Icon(Icons.lock_open),
                label: const Text('解锁'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _handleDisableEncryption,
                icon: const Icon(Icons.lock_open),
                label: const Text('禁用加密'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
          const SizedBox(height: 24),
          _SectionTitle(title: '加密算法'),
          const SizedBox(height: 8),
          RadioListTile<CryptoStrength>(
            title: const Text('标准'),
            subtitle: const Text('Argon2id 3次迭代，适合日常使用'),
            value: CryptoStrength.standard,
            groupValue: state.strength,
            onChanged: state.isEnabled ? null : _handleStrengthChange,
          ),
          RadioListTile<CryptoStrength>(
            title: const Text('高强度'),
            subtitle: const Text('Argon2id 6次迭代，更高安全性'),
            value: CryptoStrength.highStrength,
            groupValue: state.strength,
            onChanged: state.isEnabled ? null : _handleStrengthChange,
          ),
          const SizedBox(height: 24),
          _SectionTitle(title: '说明'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '加密说明',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• 启用加密后，笔记内容将以 XChaCha20-Poly1305 算法加密存储\n'
                    '• 密码使用 Argon2id 算法派生密钥\n'
                    '• 请妥善保管密码，忘记密码将无法恢复数据\n'
                    '• 修改加密强度需要先禁用再重新启用加密',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
