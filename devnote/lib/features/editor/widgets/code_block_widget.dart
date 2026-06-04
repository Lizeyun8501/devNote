import 'package:flutter/material.dart';

enum CodeTheme { vscodeDark, githubLight, monokai }

class CodeBlockWidget extends StatefulWidget {
  final String content;
  final String? language;
  final ValueChanged<String> onContentChanged;

  const CodeBlockWidget({
    super.key,
    required this.content,
    this.language,
    required this.onContentChanged,
  });

  @override
  State<CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<CodeBlockWidget> {
  late final TextEditingController _controller;
  bool _wrapText = false;
  CodeTheme _theme = CodeTheme.vscodeDark;

  static const Map<CodeTheme, _CodeThemeData> _themes = {
    CodeTheme.vscodeDark: _CodeThemeData(
      background: Color(0xFF1E1E1E),
      foreground: Color(0xFFD4D4D4),
      keyword: Color(0xFF569CD6),
      string: Color(0xFFCE9178),
      comment: Color(0xFF6A9955),
      number: Color(0xFFB5CEA8),
      function: Color(0xFFDCDCAA),
      operator: Color(0xFFD4D4D4),
      punctuation: Color(0xFFD4D4D4),
      identifier: Color(0xFF9CDCFE),
      lineNumber: Color(0xFF858585),
      lineNumberBackground: Color(0xFF1E1E1E),
    ),
    CodeTheme.githubLight: _CodeThemeData(
      background: Color(0xFFF6F8FA),
      foreground: Color(0xFF24292E),
      keyword: Color(0xFFD73A49),
      string: Color(0xFF032F62),
      comment: Color(0xFF6A737D),
      number: Color(0xFF005CC5),
      function: Color(0xFF6F42C1),
      operator: Color(0xFFD73A49),
      punctuation: Color(0xFF24292E),
      identifier: Color(0xFF24292E),
      lineNumber: Color(0xFF959DA5),
      lineNumberBackground: Color(0xFFF6F8FA),
    ),
    CodeTheme.monokai: _CodeThemeData(
      background: Color(0xFF272822),
      foreground: Color(0xFFF8F8F2),
      keyword: Color(0xFFF92672),
      string: Color(0xFFE6DB74),
      comment: Color(0xFF75715E),
      number: Color(0xFFAE81FF),
      function: Color(0xFFA6E22E),
      operator: Color(0xFFF92672),
      punctuation: Color(0xFFF8F8F2),
      identifier: Color(0xFFF8F8F2),
      lineNumber: Color(0xFF90908A),
      lineNumberBackground: Color(0xFF272822),
    ),
  };

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.content);
  }

  @override
  void didUpdateWidget(covariant CodeBlockWidget oldWidget) {
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

  List<_SyntaxToken> _tokenize(String line) {
    final keywords = _getKeywords(widget.language);
    final tokens = <_SyntaxToken>[];
    final chars = line.runes.toList();
    var i = 0;
    final isPython = keywords.contains('def');

    while (i < chars.length) {
      final ch = String.fromCharCode(chars[i]);

      if (!isPython && i + 1 < chars.length && ch == '/' && String.fromCharCode(chars[i + 1]) == '/') {
        tokens.add(_SyntaxToken(_TokenType.comment, line.substring(i)));
        break;
      }

      if (isPython && ch == '#') {
        tokens.add(_SyntaxToken(_TokenType.comment, line.substring(i)));
        break;
      }

      if (ch == '"' || ch == "'") {
        var end = i + 1;
        while (end < chars.length && String.fromCharCode(chars[end]) != ch) {
          if (String.fromCharCode(chars[end]) == '\\' && end + 1 < chars.length) {
            end += 2;
          } else {
            end += 1;
          }
        }
        if (end < chars.length) end += 1;
        tokens.add(_SyntaxToken(_TokenType.string, line.substring(i, end)));
        i = end;
        continue;
      }

      if (ch.trim().isEmpty) {
        var end = i;
        while (end < chars.length && String.fromCharCode(chars[end]).trim().isEmpty) {
          end += 1;
        }
        tokens.add(_SyntaxToken(_TokenType.whitespace, line.substring(i, end)));
        i = end;
        continue;
      }

      final rune = chars[i];
      if (rune >= 48 && rune <= 57) {
        var end = i;
        while (end < chars.length) {
          final c = chars[end];
          final s = String.fromCharCode(c);
          if ((c >= 48 && c <= 57) || s == '.' || s == '_') {
            end += 1;
          } else {
            break;
          }
        }
        tokens.add(_SyntaxToken(_TokenType.number, line.substring(i, end)));
        i = end;
        continue;
      }

      final isAlpha = (rune >= 65 && rune <= 90) || (rune >= 97 && rune <= 122) || ch == '_';
      if (isAlpha) {
        var end = i;
        while (end < chars.length) {
          final c = chars[end];
          final s = String.fromCharCode(c);
          final isAlphaNum = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || s == '_';
          if (isAlphaNum) {
            end += 1;
          } else {
            break;
          }
        }
        final word = line.substring(i, end);
        final tokenType = keywords.contains(word)
            ? _TokenType.keyword
            : (end < chars.length && String.fromCharCode(chars[end]) == '(' ? _TokenType.function : _TokenType.identifier);
        tokens.add(_SyntaxToken(tokenType, word));
        i = end;
        continue;
      }

      const opChars = {'+', '-', '*', '/', '%', '=', '<', '>', '!', '&', '|', '^', '~', '?', ':', '.'};
      if (opChars.contains(ch)) {
        var end = i + 1;
        while (end < chars.length && opChars.contains(String.fromCharCode(chars[end]))) {
          end += 1;
        }
        tokens.add(_SyntaxToken(_TokenType.operator, line.substring(i, end)));
        i = end;
        continue;
      }

      const punctChars = {'(', ')', '{', '}', '[', ']', ',', ';'};
      if (punctChars.contains(ch)) {
        tokens.add(_SyntaxToken(_TokenType.punctuation, ch));
        i += 1;
        continue;
      }

      tokens.add(_SyntaxToken(_TokenType.identifier, ch));
      i += 1;
    }

    return tokens;
  }

  List<String> _getKeywords(String? language) {
    switch (language?.toLowerCase()) {
      case 'rust':
        return ['fn', 'let', 'mut', 'if', 'else', 'match', 'loop', 'while', 'for', 'in', 'return', 'struct', 'enum', 'impl', 'trait', 'pub', 'use', 'mod', 'crate', 'self', 'super', 'where', 'type', 'const', 'static', 'ref', 'move', 'async', 'await', 'dyn', 'as', 'break', 'continue', 'true', 'false'];
      case 'python':
        return ['def', 'class', 'if', 'elif', 'else', 'for', 'while', 'return', 'import', 'from', 'as', 'try', 'except', 'finally', 'with', 'yield', 'lambda', 'pass', 'raise', 'and', 'or', 'not', 'in', 'is', 'True', 'False', 'None', 'global', 'nonlocal', 'assert', 'del', 'break', 'continue'];
      case 'javascript':
      case 'js':
      case 'typescript':
      case 'ts':
        return ['function', 'var', 'let', 'const', 'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'break', 'continue', 'return', 'class', 'extends', 'new', 'this', 'super', 'import', 'export', 'from', 'default', 'try', 'catch', 'finally', 'throw', 'typeof', 'instanceof', 'in', 'of', 'async', 'await', 'yield', 'void', 'delete', 'true', 'false', 'null', 'undefined'];
      default:
        return [];
    }
  }

  Color _getTokenColor(_TokenType type, _CodeThemeData theme) {
    switch (type) {
      case _TokenType.keyword:
        return theme.keyword;
      case _TokenType.string:
        return theme.string;
      case _TokenType.comment:
        return theme.comment;
      case _TokenType.number:
        return theme.number;
      case _TokenType.function:
        return theme.function;
      case _TokenType.operator:
        return theme.operator;
      case _TokenType.punctuation:
        return theme.punctuation;
      case _TokenType.identifier:
        return theme.identifier;
      case _TokenType.whitespace:
        return theme.foreground;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _themes[_theme]!;
    final lines = widget.content.split('\n');

    return Container(
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme),
          const Divider(height: 1, thickness: 1, color: Color(0xFF444444)),
          Row(
            children: [
              _buildLineNumbers(lines, theme),
              Expanded(
                child: _wrapText
                    ? _buildWrappedCode(lines, theme)
                    : _buildScrollableCode(lines, theme),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(_CodeThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          if (widget.language != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.foreground.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.language!.toUpperCase(),
                style: TextStyle(
                  color: theme.foreground,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const Spacer(),
          IconButton(
            icon: Icon(
              _wrapText ? Icons.wrap_text : Icons.format_align_left,
              size: 16,
              color: theme.foreground.withValues(alpha: 0.6),
            ),
            onPressed: () => setState(() => _wrapText = !_wrapText),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          PopupMenuButton<CodeTheme>(
            icon: Icon(
              Icons.palette,
              size: 16,
              color: theme.foreground.withValues(alpha: 0.6),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onSelected: (value) => setState(() => _theme = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: CodeTheme.vscodeDark, child: Text('VS Code Dark')),
              const PopupMenuItem(value: CodeTheme.githubLight, child: Text('GitHub Light')),
              const PopupMenuItem(value: CodeTheme.monokai, child: Text('Monokai')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLineNumbers(List<String> lines, _CodeThemeData theme) {
    return Container(
      width: 48,
      color: theme.lineNumberBackground,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(lines.length, (index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: theme.lineNumber,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildScrollableCode(List<String> lines, _CodeThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines.map((line) => _buildCodeLine(line, theme)).toList(),
      ),
    );
  }

  Widget _buildWrappedCode(List<String> lines, _CodeThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines.map((line) => _buildCodeLine(line, theme)).toList(),
      ),
    );
  }

  Widget _buildCodeLine(String line, _CodeThemeData theme) {
    final tokens = _tokenize(line);
    if (tokens.isEmpty) {
      return const SizedBox(height: 18);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RichText(
        text: TextSpan(
          children: tokens.map((token) {
            return TextSpan(
              text: token.text,
              style: TextStyle(
                color: _getTokenColor(token.type, theme),
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

enum _TokenType { keyword, string, comment, number, function, operator, punctuation, identifier, whitespace }

class _SyntaxToken {
  final _TokenType type;
  final String text;
  const _SyntaxToken(this.type, this.text);
}

class _CodeThemeData {
  final Color background;
  final Color foreground;
  final Color keyword;
  final Color string;
  final Color comment;
  final Color number;
  final Color function;
  final Color operator;
  final Color punctuation;
  final Color identifier;
  final Color lineNumber;
  final Color lineNumberBackground;

  const _CodeThemeData({
    required this.background,
    required this.foreground,
    required this.keyword,
    required this.string,
    required this.comment,
    required this.number,
    required this.function,
    required this.operator,
    required this.punctuation,
    required this.identifier,
    required this.lineNumber,
    required this.lineNumberBackground,
  });
}
