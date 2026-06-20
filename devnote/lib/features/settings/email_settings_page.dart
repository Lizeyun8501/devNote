import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class EmailSettingsPage extends StatefulWidget {
  const EmailSettingsPage({super.key});

  @override
  State<EmailSettingsPage> createState() => _EmailSettingsPageState();
}

class _EmailSettingsPageState extends State<EmailSettingsPage> {
  String? _emailAddr;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAlias();
  }

  Future<void> _loadAlias() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverUrl = prefs.getString('sync_server_url') ?? 'https://sync.devnote.app';
      final token = prefs.getString('auth_token') ?? '';

      final response = await http.get(
        Uri.parse('$serverUrl/api/v1/email/alias'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _emailAddr = data['email_addr'] as String?;
          _loading = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _regenerateAlias() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新生成邮箱地址'),
        content: const Text('重新生成后，旧邮箱地址将失效。确定继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('继续')),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final serverUrl = prefs.getString('sync_server_url') ?? 'https://sync.devnote.app';
      final token = prefs.getString('auth_token') ?? '';

      final response = await http.post(
        Uri.parse('$serverUrl/api/v1/email/alias/regenerate'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _emailAddr = data['email_addr'] as String?;
          _loading = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('邮件转笔记')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // 说明
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withAlpha(50),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          const Text('使用说明', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '1. 将邮件转发到下方的专属邮箱地址\n'
                        '2. 邮件内容将自动创建为新笔记\n'
                        '3. 笔记标题为邮件主题，正文为邮件内容\n'
                        '4. 支持纯文本和 HTML 邮件',
                        style: TextStyle(height: 1.5),
                      ),
                    ],
                  ),
                ),
                // 邮箱地址
                if (_emailAddr != null) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('专属邮箱地址', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(100)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.alternate_email, color: Colors.blue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SelectableText(
                            _emailAddr!,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _emailAddr!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制到剪贴板')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
                // 重新生成
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('重新生成邮箱地址'),
                  subtitle: const Text('旧地址将失效'),
                  onTap: _regenerateAlias,
                ),
              ],
            ),
    );
  }
}
