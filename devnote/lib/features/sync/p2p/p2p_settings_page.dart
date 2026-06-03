import 'package:flutter/material.dart';
import 'package:devnote/core/di/injection.dart';

import 'p2p_service.dart';
import 'device_list_widget.dart';

class P2PSettingsPage extends StatefulWidget {
  const P2PSettingsPage({super.key});

  @override
  State<P2PSettingsPage> createState() => _P2PSettingsPageState();
}

class _P2PSettingsPageState extends State<P2PSettingsPage> {
  final P2PService _p2pService = getIt<P2PService>();
  final TextEditingController _signalingServerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _p2pService.addListener(_onStateChanged);
    _p2pService.initialize().then((_) {
      if (mounted) {
        _signalingServerController.text = _p2pService.state.signalingServerUrl ?? '';
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _p2pService.removeListener(_onStateChanged);
    _signalingServerController.dispose();
    super.dispose();
  }

  void _onStateChanged(P2PState state) {
    if (mounted) setState(() {});
  }

  Future<void> _handleToggleP2P(bool enabled) async {
    await _p2pService.setEnabled(enabled);
    if (mounted) setState(() {});
  }

  Future<void> _handleStartNode() async {
    await _p2pService.startNode();
    if (mounted) setState(() {});
  }

  Future<void> _handleStopNode() async {
    await _p2pService.stopNode();
    if (mounted) setState(() {});
  }

  Future<void> _handleDiscoverPeers() async {
    await _p2pService.discoverPeers();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在发现设备...')),
      );
    }
  }

  Future<void> _handleSaveSignalingServer() async {
    final url = _signalingServerController.text.trim();
    if (url.isEmpty) return;

    await _p2pService.setSignalingServer(url);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('信令服务器已更新')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _p2pService.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('P2P 同步'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusCard(state),
          const SizedBox(height: 24),
          _SectionTitle(title: 'P2P 同步'),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('启用 P2P 同步'),
            subtitle: const Text('通过 P2P 网络在设备间同步数据'),
            value: state.isEnabled,
            onChanged: _handleToggleP2P,
          ),
          if (state.isEnabled) ...[
            const SizedBox(height: 16),
            _SectionTitle(title: '节点控制'),
            const SizedBox(height: 8),
            if (state.status == P2PNodeStatus.running) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _handleStopNode,
                      icon: const Icon(Icons.stop),
                      label: const Text('停止节点'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _handleDiscoverPeers,
                      icon: const Icon(Icons.search),
                      label: const Text('发现设备'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: _handleStartNode,
                icon: const Icon(Icons.play_arrow),
                label: const Text('启动节点'),
              ),
            ],
          ],
          const SizedBox(height: 24),
          if (state.isEnabled) ...[
            _SectionTitle(title: '已连接设备'),
            const SizedBox(height: 8),
            const DeviceListWidget(),
            const SizedBox(height: 24),
          ],
          _SectionTitle(title: '信令服务器'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _signalingServerController,
                    decoration: const InputDecoration(
                      labelText: '服务器地址',
                      hintText: 'https://signal.devnote.app',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _handleSaveSignalingServer,
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ),
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
                    'P2P 同步说明',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• P2P 同步使用 libp2p 协议进行设备间直接通信\n'
                    '• 通过 Kademlia DHT 进行设备发现\n'
                    '• 使用 Noise 协议进行加密传输\n'
                    '• 通过信令服务器交换公钥和 NAT 穿透\n'
                    '• P2P 功能为可选功能，不影响核心同步流程',
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

  Widget _buildStatusCard(P2PState state) {
    final statusColor = switch (state.status) {
      P2PNodeStatus.running => Theme.of(context).colorScheme.primary,
      P2PNodeStatus.starting => Colors.orange,
      P2PNodeStatus.error => Theme.of(context).colorScheme.error,
      P2PNodeStatus.stopped => Theme.of(context).colorScheme.onSurfaceVariant,
    };

    final statusText = switch (state.status) {
      P2PNodeStatus.stopped => '已停止',
      P2PNodeStatus.starting => '启动中...',
      P2PNodeStatus.running => '运行中',
      P2PNodeStatus.error => '错误',
    };

    final onlineCount = state.peers.where((p) => p.isOnline).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  statusText,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: statusColor,
                      ),
                ),
                const Spacer(),
                if (state.status == P2PNodeStatus.running) ...[
                  Icon(
                    Icons.devices,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$onlineCount 设备在线',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
            if (state.localPeerId != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '本机 ID: ',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  Expanded(
                    child: Text(
                      state.localPeerId!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (state.lastError != null) ...[
              const SizedBox(height: 8),
              Text(
                state.lastError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
          ],
        ),
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
