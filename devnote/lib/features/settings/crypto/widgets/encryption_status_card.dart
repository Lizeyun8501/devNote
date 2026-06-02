import 'package:flutter/material.dart';
import '../crypto_service.dart';

class EncryptionStatusCard extends StatelessWidget {
  const EncryptionStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cryptoService = CryptoService.instance;
    final state = cryptoService.state;

    final isEnabled = state.isEnabled;
    final isUnlocked = state.isUnlocked;

    Color statusColor;
    IconData statusIcon;
    String statusText;
    String statusDescription;

    if (!isEnabled) {
      statusColor = Theme.of(context).colorScheme.outline;
      statusIcon = Icons.lock_open;
      statusText = '未启用';
      statusDescription = '笔记数据未加密';
    } else if (isUnlocked) {
      statusColor = Theme.of(context).colorScheme.primary;
      statusIcon = Icons.lock_open;
      statusText = '已解锁';
      statusDescription = '加密已启用，数据可访问';
    } else {
      statusColor = Theme.of(context).colorScheme.error;
      statusIcon = Icons.lock;
      statusText = '已锁定';
      statusDescription = '请输入密码解锁';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '加密状态',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        statusDescription,
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
            if (isEnabled) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  _InfoChip(
                    label: '算法',
                    value: state.algorithm,
                  ),
                  const SizedBox(width: 16),
                  _InfoChip(
                    label: '密钥派生',
                    value: state.keyDerivation,
                  ),
                  const SizedBox(width: 16),
                  _InfoChip(
                    label: '强度',
                    value: state.strength == CryptoStrength.highStrength ? '高强度' : '标准',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
