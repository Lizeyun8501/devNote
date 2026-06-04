import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class LatexBlockWidget extends StatefulWidget {
  final String content;
  final ValueChanged<String> onContentChanged;

  const LatexBlockWidget({
    super.key,
    required this.content,
    required this.onContentChanged,
  });

  @override
  State<LatexBlockWidget> createState() => _LatexBlockWidgetState();
}

class _LatexBlockWidgetState extends State<LatexBlockWidget> {
  late final TextEditingController _controller;
  bool _isEditing = false;
  bool _isDisplay = true;

  String _stripDelimiters(String latex) {
    final trimmed = latex.trim();
    if (trimmed.startsWith('\$\$') && trimmed.endsWith('\$\$') && trimmed.length > 4) {
      return trimmed.substring(2, trimmed.length - 2).trim();
    }
    if (trimmed.startsWith('\\[') && trimmed.endsWith('\\]') && trimmed.length > 4) {
      return trimmed.substring(2, trimmed.length - 2).trim();
    }
    if (trimmed.startsWith('\\(') && trimmed.endsWith('\\)') && trimmed.length > 4) {
      _isDisplay = false;
      return trimmed.substring(2, trimmed.length - 2).trim();
    }
    if (trimmed.startsWith('\$') && trimmed.endsWith('\$') && trimmed.length > 2) {
      _isDisplay = false;
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.content);
  }

  @override
  void didUpdateWidget(covariant LatexBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content && _controller.text != widget.content) {
      _controller.text = widget.content;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E32) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF2D2D44) : const Color(0xFFE5E7EB),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.functions,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                _isDisplay ? 'LaTeX (Display)' : 'LaTeX (Inline)',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _isEditing ? Icons.visibility : Icons.edit,
                  size: 16,
                ),
                onPressed: () {
                  setState(() {
                    _isEditing = !_isEditing;
                  });
                  if (!_isEditing) {
                    widget.onContentChanged(_controller.text);
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isEditing)
            TextField(
              controller: _controller,
              maxLines: null,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Enter LaTeX formula...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF0F0F1A) : Colors.white,
                isDense: true,
                contentPadding: const EdgeInsets.all(8),
              ),
              onChanged: widget.onContentChanged,
            )
          else
            _buildLatexPreview(context),
        ],
      ),
    );
  }

  Widget _buildLatexPreview(BuildContext context) {
    final formula = _stripDelimiters(widget.content);
    if (formula.isEmpty) {
      return Text(
        'Empty formula',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _isDisplay
          ? Center(
              child: Math.tex(
                formula,
                textStyle: const TextStyle(fontSize: 18),
                mathStyle: MathStyle.display,
                onErrorFallback: (err) => _buildError(context, err.toString()),
              ),
            )
          : Math.tex(
              formula,
              textStyle: const TextStyle(fontSize: 16),
              mathStyle: MathStyle.text,
              onErrorFallback: (err) => _buildError(context, err.toString()),
            ),
    );
  }

  Widget _buildError(BuildContext context, String error) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        error,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
