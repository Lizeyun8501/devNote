import 'package:flutter/material.dart';

class PasswordDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final bool requireConfirm;

  const PasswordDialog({
    super.key,
    required this.title,
    this.confirmLabel = '确认',
    this.requireConfirm = true,
  });

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorText;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool _validate() {
    if (_passwordController.text.length < 6) {
      setState(() {
        _errorText = '密码长度至少6位';
      });
      return false;
    }
    if (widget.requireConfirm && _passwordController.text != _confirmController.text) {
      setState(() {
        _errorText = '两次输入的密码不一致';
      });
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '密码',
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              errorText: _errorText,
            ),
            onChanged: (_) {
              if (_errorText != null) {
                setState(() {
                  _errorText = null;
                });
              }
            },
          ),
          if (widget.requireConfirm) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: '确认密码',
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                  onPressed: () {
                    setState(() {
                      _obscureConfirm = !_obscureConfirm;
                    });
                  },
                ),
              ),
              onSubmitted: (_) {
                if (_validate()) {
                  Navigator.of(context).pop(_passwordController.text);
                }
              },
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_validate()) {
              Navigator.of(context).pop(_passwordController.text);
            }
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
