import 'package:flutter/material.dart';
import 'package:devnote/features/plugins/plugin_service.dart';

class PermissionDialog extends StatelessWidget {
  const PermissionDialog({
    super.key,
    required this.pluginId,
    required this.pluginName,
    required this.requiredPermissions,
    required this.grantedPermissions,
    required this.onGrant,
    required this.onRevoke,
  });

  final String pluginId;
  final String pluginName;
  final List<PluginPermission> requiredPermissions;
  final List<PluginPermission> grantedPermissions;
  final ValueChanged<PluginPermission> onGrant;
  final ValueChanged<PluginPermission> onRevoke;

  static const _permissionLabels = {
    PluginPermission.readNotes: '读取笔记',
    PluginPermission.writeNotes: '写入笔记',
    PluginPermission.accessNetwork: '访问网络',
    PluginPermission.accessFileSystem: '访问文件系统',
    PluginPermission.accessUI: '访问界面',
    PluginPermission.accessCanvas: '访问画布',
    PluginPermission.accessDatabase: '访问数据库',
  };

  static const _permissionDescriptions = {
    PluginPermission.readNotes: '允许插件读取笔记内容',
    PluginPermission.writeNotes: '允许插件修改笔记内容',
    PluginPermission.accessNetwork: '允许插件访问网络',
    PluginPermission.accessFileSystem: '允许插件访问文件系统',
    PluginPermission.accessUI: '允许插件操作界面元素',
    PluginPermission.accessCanvas: '允许插件访问画布功能',
    PluginPermission.accessDatabase: '允许插件直接访问数据库',
  };

  static const _permissionIcons = {
    PluginPermission.readNotes: Icons.description_outlined,
    PluginPermission.writeNotes: Icons.edit_outlined,
    PluginPermission.accessNetwork: Icons.language,
    PluginPermission.accessFileSystem: Icons.folder_outlined,
    PluginPermission.accessUI: Icons.widgets_outlined,
    PluginPermission.accessCanvas: Icons.draw_outlined,
    PluginPermission.accessDatabase: Icons.storage_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('$pluginName - 权限管理'),
      content: SizedBox(
        width: 400,
        child: ListView(
          shrinkWrap: true,
          children: PluginPermission.values.map((permission) {
            final isGranted = grantedPermissions.contains(permission);
            final isRequired = requiredPermissions.contains(permission);
            return SwitchListTile(
              secondary: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _permissionIcons[permission],
                    size: 20,
                  ),
                  if (isRequired) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: '插件必需权限',
                      child: Icon(
                        Icons.warning_amber,
                        size: 16,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              title: Text(_permissionLabels[permission] ?? permission.name),
              subtitle: Text(
                _permissionDescriptions[permission] ?? '',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              value: isGranted,
              onChanged: (value) {
                if (value) {
                  onGrant(permission);
                } else {
                  onRevoke(permission);
                }
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
