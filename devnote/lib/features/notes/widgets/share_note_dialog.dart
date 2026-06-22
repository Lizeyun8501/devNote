import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:devnote/core/config/app_config.dart';
import '../services/share_service.dart';

class ShareNoteDialog extends StatefulWidget {
  final String noteId;
  final String title;
  final String content;

  const ShareNoteDialog({
    super.key,
    required this.noteId,
    required this.title,
    required this.content,
  });

  @override
  State<ShareNoteDialog> createState() => _ShareNoteDialogState();
}

class _ShareNoteDialogState extends State<ShareNoteDialog> {
  final _shareService = getIt<ShareService>();
  final _passwordController = TextEditingController();
  bool _usePassword = false;
  int _expiryDays = 0; // 0 = 永不过期
  bool _creating = false;
  ShareResult? _result;
  String? _error;

  Future<void> _createShare() async {
    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      final result = await _shareService.createShare(
        noteId: widget.noteId,
        title: widget.title,
        content: widget.content,
        password: _usePassword ? _passwordController.text : null,
        expiresIn: _expiryDays > 0 ? Duration(days: _expiryDays) : null,
      );
      setState(() {
        _result = result;
        _creating = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _creating = false;
      });
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('分享笔记'),
      content: SizedBox(
        width: 400,
        child: _result != null
            ? _buildResultView(context)
            : _buildConfigView(context),
      ),
      actions: _result != null
          ? [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'))
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: _creating ? null : _createShare,
                child: _creating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('创建分享'),
              ),
            ],
    );
  }

  Widget _buildConfigView(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('错误: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        // 密码保护
        SwitchListTile(
          title: const Text('密码保护'),
          value: _usePassword,
          onChanged: (v) => setState(() => _usePassword = v),
          contentPadding: EdgeInsets.zero,
        ),
        if (_usePassword)
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '访问密码',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        const SizedBox(height: 16),
        // 有效期
        const Text('有效期'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
                label: const Text('永久'),
                selected: _expiryDays == 0,
                onSelected: (_) => setState(() => _expiryDays = 0)),
            ChoiceChip(
                label: const Text('7天'),
                selected: _expiryDays == 7,
                onSelected: (_) => setState(() => _expiryDays = 7)),
            ChoiceChip(
                label: const Text('30天'),
                selected: _expiryDays == 30,
                onSelected: (_) => setState(() => _expiryDays = 30)),
            ChoiceChip(
                label: const Text('90天'),
                selected: _expiryDays == 90,
                onSelected: (_) => setState(() => _expiryDays = 90)),
          ],
        ),
      ],
    );
  }

  Widget _buildResultView(BuildContext context) {
    final fullUrl = '$defaultSyncServerUrl${_result!.shareUrl}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 48),
        const SizedBox(height: 8),
        const Text('分享链接已创建',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        const Text('分享链接：'),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(fullUrl, style: const TextStyle(fontSize: 13)),
              ),
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: fullUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制到剪贴板')),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_result!.hasPassword)
          const Row(children: [
            Icon(Icons.lock, size: 16, color: Colors.orange),
            SizedBox(width: 4),
            Text('已启用密码保护', style: TextStyle(color: Colors.orange)),
          ]),
        if (_result!.expiresAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('过期时间：${_result!.expiresAt!.toLocal()}'),
          ),
      ],
    );
  }
}
