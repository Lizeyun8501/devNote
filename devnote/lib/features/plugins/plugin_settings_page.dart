import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/plugins/bloc/plugin_bloc.dart';
import 'package:devnote/features/plugins/bloc/plugin_event.dart';
import 'package:devnote/features/plugins/bloc/plugin_state.dart';
import 'package:devnote/features/plugins/plugin_service.dart';
import 'package:devnote/features/plugins/widgets/permission_dialog.dart';

class PluginSettingsPage extends StatefulWidget {
  const PluginSettingsPage({super.key});

  @override
  State<PluginSettingsPage> createState() => _PluginSettingsPageState();
}

class _PluginSettingsPageState extends State<PluginSettingsPage> {
  @override
  void initState() {
    super.initState();
    context.read<PluginBloc>().add(const LoadPlugins());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件管理'),
      ),
      body: BlocBuilder<PluginBloc, PluginsState>(
        // P2-4: 仅在 state 类型变化或 plugins（已安装列表）变化时重建，
        // 避免 marketplacePlugins 变化触发已安装列表重建。
        buildWhen: (previous, current) {
          if (previous.runtimeType != current.runtimeType) return true;
          if (previous is PluginsLoaded && current is PluginsLoaded) {
            return previous.plugins != current.plugins;
          }
          return false;
        },
        builder: (context, state) {
          if (state is PluginsLoaded) {
            if (state.plugins.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.extension_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('暂无已安装插件', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.plugins.length,
              itemBuilder: (context, index) {
                final plugin = state.plugins[index];
                return _PluginListItem(
                  plugin: plugin,
                  onToggle: (enabled) {
                    if (enabled) {
                      context
                          .read<PluginBloc>()
                          .add(EnablePlugin(plugin.manifest.id));
                    } else {
                      context
                          .read<PluginBloc>()
                          .add(DisablePlugin(plugin.manifest.id));
                    }
                  },
                  onManagePermissions: () {
                    _showPermissionDialog(context, plugin);
                  },
                  onUninstall: () {
                    _confirmUninstall(context, plugin);
                  },
                );
              },
            );
          }

          if (state is PluginError) {
            return Center(child: Text('加载失败: ${state.message}'));
          }

          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  void _showPermissionDialog(BuildContext context, PluginEntry plugin) {
    showDialog(
      context: context,
      builder: (_) => PermissionDialog(
        pluginId: plugin.manifest.id,
        pluginName: plugin.manifest.name,
        requiredPermissions: plugin.manifest.permissions,
        grantedPermissions: plugin.grantedPermissions,
        onGrant: (permission) {
          context.read<PluginBloc>().add(GrantPermission(
                id: plugin.manifest.id,
                permission: permission,
              ));
        },
        onRevoke: (permission) {
          context.read<PluginBloc>().add(RevokePermission(
                id: plugin.manifest.id,
                permission: permission,
              ));
        },
      ),
    );
  }

  void _confirmUninstall(BuildContext context, PluginEntry plugin) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('卸载插件'),
        content: Text('确定要卸载 ${plugin.manifest.name} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              context
                  .read<PluginBloc>()
                  .add(UninstallPlugin(plugin.manifest.id));
              Navigator.pop(dialogContext);
            },
            child: const Text('卸载'),
          ),
        ],
      ),
    );
  }
}

class _PluginListItem extends StatelessWidget {
  const _PluginListItem({
    required this.plugin,
    required this.onToggle,
    required this.onManagePermissions,
    required this.onUninstall,
  });

  final PluginEntry plugin;
  final ValueChanged<bool> onToggle;
  final VoidCallback onManagePermissions;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final isEnabled = plugin.state == PluginLifecycleState.enabled;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plugin.manifest.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plugin.manifest.description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isEnabled,
                  onChanged: onToggle,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${plugin.manifest.author} · v${plugin.manifest.version}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.security, size: 16),
                  label: const Text('权限'),
                  onPressed: onManagePermissions,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('卸载'),
                  onPressed: onUninstall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
