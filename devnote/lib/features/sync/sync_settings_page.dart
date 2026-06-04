import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:devnote/features/sync/bloc/sync_bloc.dart';
import 'package:devnote/features/sync/bloc/sync_event.dart';
import 'package:devnote/features/sync/bloc/sync_state.dart';
import 'package:devnote/features/sync/crypto/e2e_setup_page.dart';
import 'package:devnote/features/sync/p2p/p2p_settings_page.dart';

class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  final _serverController = TextEditingController();
  final _syncHistory = <SyncHistoryEntry>[];
  static const String _keyServerAddress = 'sync_server_address';

  @override
  void initState() {
    super.initState();
    _loadServerAddress();
    _loadSyncHistory();
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _loadServerAddress() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString(_keyServerAddress) ?? '';
    _serverController.text = address;
  }

  Future<void> _loadSyncHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('sync_history') ?? [];
    setState(() {
      _syncHistory.clear();
      _syncHistory.addAll(
        history.map((h) => SyncHistoryEntry.fromJson(h)),
      );
    });
  }

  Future<void> _saveServerAddress() async {
    final address = _serverController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyServerAddress, address);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('服务器地址已保存')),
      );
    }
  }

  void _handleManualSync() {
    context.read<SyncBloc>().add(const StartSync());
    _addSyncHistoryEntry('手动同步');
  }

  Future<void> _addSyncHistoryEntry(String action) async {
    final entry = SyncHistoryEntry(
      time: DateTime.now(),
      action: action,
      status: '进行中',
    );
    setState(() {
      _syncHistory.insert(0, entry);
      if (_syncHistory.length > 20) {
        _syncHistory.removeLast();
      }
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'sync_history',
      _syncHistory.map((e) => e.toJson()).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('同步设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusCard(),
          const SizedBox(height: 24),
          _SectionTitle(title: '服务器配置'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _serverController,
                    decoration: const InputDecoration(
                      labelText: '服务器地址',
                      hintText: 'https://sync.devnote.app',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _saveServerAddress,
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionTitle(title: '自动同步'),
          const SizedBox(height: 8),
          BlocBuilder<SyncBloc, SyncState>(
            builder: (context, state) {
              return Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('自动同步'),
                      subtitle: const Text('定时自动同步数据'),
                      value: state.autoSyncEnabled,
                      onChanged: (value) {
                        context
                            .read<SyncBloc>()
                            .add(AutoSyncToggled(value));
                      },
                    ),
                    if (state.autoSyncEnabled) ...[
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('同步间隔'),
                        subtitle: Text('每 ${state.syncInterval.inMinutes} 分钟'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showIntervalPicker(context, state),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          _SectionTitle(title: '手动操作'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                BlocBuilder<SyncBloc, SyncState>(
                  builder: (context, state) {
                    final isSyncing = state is SyncInProgress;
                    return ListTile(
                      leading: isSyncing
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      title: const Text('立即同步'),
                      subtitle: isSyncing
                          ? const Text('同步中...')
                          : const Text('手动触发一次完整同步'),
                      onTap: isSyncing ? null : _handleManualSync,
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_upload),
                  title: const Text('推送更改'),
                  subtitle: const Text('将本地更改推送到服务器'),
                  onTap: () {
                    context.read<SyncBloc>().add(
                          const PushChanges({}),
                        );
                    _addSyncHistoryEntry('推送更改');
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_download),
                  title: const Text('拉取更改'),
                  subtitle: const Text('从服务器拉取最新更改'),
                  onTap: () {
                    context.read<SyncBloc>().add(const PullChanges());
                    _addSyncHistoryEntry('拉取更改');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionTitle(title: '同步历史'),
          const SizedBox(height: 8),
          Card(
            child: _syncHistory.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: Text('暂无同步记录'),
                    ),
                  )
                : Column(
                    children: _syncHistory.take(10).map((entry) {
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.history,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        title: Text(entry.action),
                        subtitle: Text(_formatTime(entry.time)),
                        trailing: Text(
                          entry.status,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 24),
          _SectionTitle(title: '高级设置'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.enhanced_encryption),
                  title: const Text('加密设置'),
                  subtitle: const Text('端到端加密同步配置'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const E2ESetupPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.wifi_tethering),
                  title: const Text('P2P 设置'),
                  subtitle: const Text('设备间直接同步配置'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const P2PSettingsPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('存储适配器'),
                  subtitle: const Text('配置 S3/WebDAV/Dropbox/OneDrive'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.push('/settings/sync/storage');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return BlocBuilder<SyncBloc, SyncState>(
      builder: (context, state) {
        final (icon, color, label) = switch (state) {
          SyncIdle() => (Icons.cloud_outlined, Colors.grey, '离线'),
          SyncInProgress() => (Icons.sync, Colors.blue, '同步中'),
          SyncCompleted(:final lastSyncTime) => (
              Icons.check_circle,
              Colors.green,
              '已同步 · ${_formatTime(lastSyncTime)}'
            ),
          SyncError(:final message) => (Icons.cloud_off, Colors.red, message),
          SyncConflict(:final conflicts) => (
              Icons.error_outline,
              Colors.orange,
              '${conflicts.length}个冲突'
            ),
          _ => (Icons.cloud_outlined, Colors.grey, '未知'),
        };

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (state is SyncInProgress)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                else
                  Icon(icon, color: color, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state is SyncCompleted ? '已同步' : label,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (state is SyncCompleted)
                        Text(
                          label,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
                if (state is SyncConflict)
                  FilledButton.tonal(
                    onPressed: () => context.go('/sync/conflicts'),
                    child: const Text('解决冲突'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showIntervalPicker(BuildContext context, SyncState state) {
    final intervals = [1, 5, 10, 15, 30, 60];
    showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('选择同步间隔'),
        children: intervals.map((minutes) {
          return SimpleDialogOption(
            onPressed: () {
              context
                  .read<SyncBloc>()
                  .add(SyncIntervalChanged(Duration(minutes: minutes)));
              Navigator.pop(dialogContext);
            },
            child: Text(
              minutes < 60 ? '$minutes 分钟' : '1 小时',
            ),
          );
        }).toList(),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }
}

class SyncHistoryEntry {
  final DateTime time;
  final String action;
  final String status;

  const SyncHistoryEntry({
    required this.time,
    required this.action,
    required this.status,
  });

  String toJson() => '${time.millisecondsSinceEpoch}|$action|$status';

  factory SyncHistoryEntry.fromJson(String json) {
    final parts = json.split('|');
    return SyncHistoryEntry(
      time: DateTime.fromMillisecondsSinceEpoch(int.parse(parts[0])),
      action: parts.length > 1 ? parts[1] : '',
      status: parts.length > 2 ? parts[2] : '',
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
