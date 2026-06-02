import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _darkMode = false;
  bool _autoSave = true;
  double _fontSize = 14.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          _SettingsSection(title: '外观', children: [
            SwitchListTile(
              title: const Text('深色模式'),
              subtitle: const Text('切换深色/浅色主题'),
              value: _darkMode,
              onChanged: (value) {
                setState(() {
                  _darkMode = value;
                });
              },
            ),
            ListTile(
              title: const Text('字体大小'),
              subtitle: Text('${_fontSize.toInt()} px'),
              trailing: SizedBox(
                width: 200,
                child: Slider(
                  value: _fontSize,
                  min: 12,
                  max: 24,
                  divisions: 6,
                  label: '${_fontSize.toInt()} px',
                  onChanged: (value) {
                    setState(() {
                      _fontSize = value;
                    });
                  },
                ),
              ),
            ),
          ]),
          _SettingsSection(title: '编辑器', children: [
            SwitchListTile(
              title: const Text('自动保存'),
              subtitle: const Text('编辑时自动保存笔记'),
              value: _autoSave,
              onChanged: (value) {
                setState(() {
                  _autoSave = value;
                });
              },
            ),
            ListTile(
              title: const Text('默认编辑模式'),
              subtitle: const Text('富文本'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ]),
          _SettingsSection(title: '数据', children: [
            ListTile(
              title: const Text('数据备份'),
              subtitle: const Text('导出笔记数据'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
            ListTile(
              title: const Text('清除缓存'),
              subtitle: const Text('清除本地缓存数据'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ]),
          _SettingsSection(title: '关于', children: [
            const ListTile(
              title: Text('版本'),
              subtitle: Text('0.1.0'),
            ),
            ListTile(
              title: const Text('开源许可'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                showLicensePage(
                  context: context,
                  applicationName: 'DevNote',
                  applicationVersion: '0.1.0',
                );
              },
            ),
          ]),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        ...children,
        const Divider(),
      ],
    );
  }
}
