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
    PluginPermission.readFolders: '读取文件夹',
    PluginPermission.writeFolders: '写入文件夹',
    PluginPermission.networkAccess: '网络访问',
    PluginPermission.fileSystem: '文件系统',
    PluginPermission.executeCode: '执行代码',
    PluginPermission.uiExtension: 'UI 扩展',
  };

  static const _permissionDescriptions = {
    PluginPermission.readNotes: '允许插件读取笔记内容',
    PluginPermission.writeNotes: '允许插件修改笔记内容',
    PluginPermission.readFolders: '允许插件读取文件夹结构',
    PluginPermission.writeFolders: '允许插件修改文件夹结构',
    PluginPermission.networkAccess: '允许插件访问网络',
    PluginPermission.fileSystem: '允许插件访问文件系统',
    PluginPermission.executeCode: '允许插件执行代码',
    PluginPermission.uiExtension: '允许插件扩展界面元素',
  };

  static const _permissionIcons = {
    PluginPermission.readNotes: Icons.description_outlined,
    PluginPermission.writeNotes: Icons.edit_outlined,
    PluginPermission.readFolders: Icons.folder_open,
    PluginPermission.writeFolders: Icons.create_new_folder_outlined,
    PluginPermission.networkAccess: Icons.language,
    PluginPermission.fileSystem: Icons.folder_outlined,
    PluginPermission.executeCode: Icons.terminal,
    PluginPermission.uiExtension: Icons.widgets_outlined,
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
