import 'package:flutter/material.dart';
import 'package:devnote/core/di/injection.dart';
import 'p2p_service.dart';

class DeviceListWidget extends StatefulWidget {
  const DeviceListWidget({super.key});

  @override
  State<DeviceListWidget> createState() => _DeviceListWidgetState();
}

class _DeviceListWidgetState extends State<DeviceListWidget> {
  final P2PService _p2pService = getIt<P2PService>();

  @override
  void initState() {
    super.initState();
    _p2pService.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _p2pService.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged(P2PState state) {
    if (mounted) setState(() {});
  }

  Future<void> _handleSync(P2PPeerInfo peer) async {
    await _p2pService.syncWithPeer(peer.peerId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('正在与 ${peer.displayName} 同步...')),
      );
    }
  }

  Future<void> _handleDisconnect(P2PPeerInfo peer) async {
    await _p2pService.disconnectPeer(peer.peerId);
  }

  @override
  Widget build(BuildContext context) {
    final peers = _p2pService.state.peers;

    if (peers.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                Icons.devices,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                '未发现设备',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '启动 P2P 节点后将自动发现附近设备',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: peers.map((peer) => _buildPeerTile(peer)).toList(),
    );
  }

  Widget _buildPeerTile(P2PPeerInfo peer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _buildStatusIcon(peer),
        title: Text(
          peer.displayName,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              peer.isOnline ? '在线' : '离线',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: peer.isOnline
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (peer.connectedAt != null)
              Text(
                '最后同步: ${_formatTime(peer.connectedAt!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (peer.isOnline)
              IconButton(
                icon: const Icon(Icons.sync),
                tooltip: '同步',
                onPressed: () => _handleSync(peer),
              ),
            if (peer.isOnline)
              IconButton(
                icon: const Icon(Icons.link_off),
                tooltip: '断开',
                onPressed: () => _handleDisconnect(peer),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(P2PPeerInfo peer) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: peer.isOnline
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Icon(
        peer.isOnline ? Icons.phone_android : Icons.phone_android_outlined,
        color: peer.isOnline
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}
