import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/performance/cache_manager.dart';
import 'package:devnote/core/bridge/ffi_bridge.dart';
import 'package:devnote/core/bridge/dispatch.dart';
import 'package:devnote/core/bridge/error.dart';
import 'package:devnote/features/settings/crypto/crypto_settings_page.dart';
import 'package:devnote/features/sync/p2p/p2p_settings_page.dart';

const String _kDefaultEditModeKey = 'settings.default_edit_mode';
const Map<String, String> _kEditModeLabels = {
  'rich': '富文本',
  'plain': '纯文本',
  'markdown': 'Markdown',
};

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _darkMode = false;
  bool _autoSave = true;
  double _fontSize = 14.0;
  String _defaultEditMode = 'rich';
  List<Map<String, dynamic>> _featureFlags = [];
  bool _featureFlagsLoading = true;
  String? _featureFlagsError;

  @override
  void initState() {
    super.initState();
    _loadDefaultEditMode();
    _loadFeatureFlags();
  }

  Future<void> _loadFeatureFlags() async {
    final bridge = getIt<FFIBridge>();
    if (!bridge.isAvailable) {
      if (!mounted) return;
      setState(() {
        _featureFlagsLoading = false;
        _featureFlagsError = 'Feature Flags 不可用（FFI 未初始化）';
      });
      return;
    }
    try {
      final dispatch = Dispatch();
      final result = await dispatch.asyncRequest('FeatureFlagEvent.ListFlags');
      if (result is Success<Uint8List, FlowyInternalError>) {
        if (!mounted) return;
        final decoded = String.fromCharCodes(result.value);
        final List<dynamic> flags = [];
        // Parse the JSON response
        try {
          final parsed = _parseJsonList(decoded);
          if (mounted) {
            setState(() {
              _featureFlags = parsed;
              _featureFlagsLoading = false;
              _featureFlagsError = null;
            });
          }
        } catch (_) {
          if (mounted) {
            setState(() {
              _featureFlags = [];
              _featureFlagsLoading = false;
              _featureFlagsError = null;
            });
          }
        }
      } else {
        if (!mounted) return;
        setState(() {
          _featureFlagsLoading = false;
          _featureFlagsError = (result as Failure<Uint8List, FlowyInternalError>).error.message;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _featureFlagsLoading = false;
        _featureFlagsError = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> _parseJsonList(String json) {
    final decoded = const JsonDecoder().convert(json);
    if (decoded is List) {
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<void> _toggleFeatureFlag(String key, bool value) async {
    final dispatch = Dispatch();
    try {
      await dispatch.asyncRequest('FeatureFlagEvent.SetFlag');
      if (!mounted) return;
      setState(() {
        final idx = _featureFlags.indexWhere((f) => f['key'] == key);
        if (idx >= 0) {
          _featureFlags[idx] = {..._featureFlags[idx], 'enabled': value};
        }
      });
    } catch (_) {
      // Silently fail - flag state remains unchanged
    }
  }

  Future<void> _loadDefaultEditMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kDefaultEditModeKey);
    if (stored == null) return;
    if (!mounted) return;
    setState(() {
      _defaultEditMode = stored;
    });
  }

  Future<void> _pickDefaultEditMode() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('选择默认编辑模式'),
          children: _kEditModeLabels.entries
              .map((entry) => RadioListTile<String>(
                    title: Text(entry.value),
                    value: entry.key,
                    groupValue: _defaultEditMode,
                    onChanged: (value) => Navigator.of(context).pop(value),
                  ))
              .toList(),
        );
      },
    );
    if (selected == null || selected == _defaultEditMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultEditModeKey, selected);
    if (!mounted) return;
    setState(() {
      _defaultEditMode = selected;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('默认编辑模式已更新为 ${_kEditModeLabels[selected]}')),
    );
  }

  Future<void> _confirmClearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定要清除本地缓存数据吗？这不会影响已保存的笔记。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    getIt<CacheManager>().clearAll();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('缓存已清除')),
    );
  }

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
              subtitle: Text(_kEditModeLabels[_defaultEditMode] ?? '富文本'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDefaultEditMode,
            ),
          ]),
          _SettingsSection(title: 'Feature Flags', children: [
            if (_featureFlagsLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_featureFlagsError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _featureFlagsError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              )
            else if (_featureFlags.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无可用的 Feature Flags'),
              )
            else
              ..._featureFlags.map((flag) => SwitchListTile(
                    title: Text(flag['name'] as String? ?? flag['key'] as String? ?? ''),
                    subtitle: Text(flag['description'] as String? ?? ''),
                    value: flag['enabled'] as bool? ?? false,
                    onChanged: (value) => _toggleFeatureFlag(flag['key'] as String, value),
                  )),
          ]),
          _SettingsSection(title: '数据', children: [
            ListTile(
              leading: Semantics(
                label: '同步设置',
                child: const Icon(Icons.sync),
              ),
              title: const Text('同步设置'),
              subtitle: const Text('配置数据同步和冲突解决'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                context.push('/settings/sync');
              },
            ),
            ListTile(
              leading: Semantics(
                label: '加密设置',
                child: const Icon(Icons.lock_outline),
              ),
              title: const Text('加密设置'),
              subtitle: const Text('管理笔记加密和密码'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CryptoSettingsPage()),
                );
              },
            ),
            ListTile(
              leading: Semantics(
                label: 'P2P 同步',
                child: const Icon(Icons.wifi_tethering),
              ),
              title: const Text('P2P 同步'),
              subtitle: const Text('设备间直接同步数据'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const P2PSettingsPage()),
                );
              },
            ),
            ListTile(
              leading: Semantics(
                label: '插件市场',
                child: const Icon(Icons.extension_outlined),
              ),
              title: const Text('插件市场'),
              subtitle: const Text('浏览和安装插件'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                context.push('/plugins/marketplace');
              },
            ),
            ListTile(
              leading: const Icon(Icons.widgets_outlined),
              title: const Text('插件管理'),
              subtitle: const Text('管理已安装的插件'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                context.push('/plugins/settings');
              },
            ),
            ListTile(
              title: const Text('导入导出'),
              subtitle: const Text('导入或导出笔记数据'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                context.push('/settings/import-export');
              },
            ),
            ListTile(
              title: const Text('数据备份'),
              subtitle: const Text('导出笔记数据'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                context.push('/settings/import-export');
              },
            ),
            ListTile(
              title: const Text('清除缓存'),
              subtitle: const Text('清除本地缓存数据'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _confirmClearCache,
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
