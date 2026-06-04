// 代码语法高亮组件 —— 借鉴 flutter_highlight 替代自研 tokenizer
// 原自研 tokenizer 仅支持 3 种语言（Rust、Python、JS/TS）的基础关键字匹配，
// 现替换为 flutter_highlight，支持 190+ 语言和 87 种主题。
// 来源: https://pub.dev/packages/flutter_highlight
import 'package:flutter/material.dart';
// 借鉴 flutter_highlight 核心库，提供 highlight.parse() 语法解析
// 来源: https://pub.dev/packages/flutter_highlight
import 'package:flutter_highlight/flutter_highlight.dart';
// 借鉴 flutter_highlight 内置主题，替代自研的 3 套配色方案
// 来源: https://pub.dev/packages/flutter_highlight
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/vs2015.dart';
// 借鉴 highlight 包的 Node 类型，用于遍历语法树生成 TextSpan
import 'package:highlight/highlight.dart';

/// 代码主题枚举 —— 保留原有的公开 API 名称，内部映射到 flutter_highlight 内置主题
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

  // 借鉴 flutter_highlight 内置主题映射，替代自研 _CodeThemeData
  // 来源: https://pub.dev/packages/flutter_highlight
  static const Map<CodeTheme, Map<String, TextStyle>> _highlightThemes = {
    CodeTheme.vscodeDark: vs2015Theme,
    CodeTheme.githubLight: githubTheme,
    CodeTheme.monokai: monokaiSublimeTheme,
  };

  // 每个主题对应的背景色，用于容器和行号区域
  static const Map<CodeTheme, _ThemeMeta> _themeMeta = {
    CodeTheme.vscodeDark: _ThemeMeta(
      background: Color(0xFF1E1E1E),
      foreground: Color(0xFFD4D4D4),
      lineNumber: Color(0xFF858585),
      lineNumberBackground: Color(0xFF1E1E1E),
    ),
    CodeTheme.githubLight: _ThemeMeta(
      background: Color(0xFFF6F8FA),
      foreground: Color(0xFF24292E),
      lineNumber: Color(0xFF959DA5),
      lineNumberBackground: Color(0xFFF6F8FA),
    ),
    CodeTheme.monokai: _ThemeMeta(
      background: Color(0xFF272822),
      foreground: Color(0xFFF8F8F2),
      lineNumber: Color(0xFF90908A),
      lineNumberBackground: Color(0xFF272822),
    ),
  };

  // 语言名称映射 —— 将用户传入的语言标识转换为 flutter_highlight 支持的语言标识
  // flutter_highlight 支持 190+ 语言，详见:
  // https://github.com/pd4d10/highlight/tree/master/highlight/lib/languages
  static String _mapLanguage(String? language) {
    if (language == null) return 'plaintext';
    switch (language.toLowerCase()) {
      case 'js':
        return 'javascript';
      case 'ts':
        return 'typescript';
      case 'py':
        return 'python';
      case 'rb':
        return 'ruby';
      case 'sh':
      case 'bash':
        return 'bash';
      case 'yml':
        return 'yaml';
      case 'md':
        return 'markdown';
      case 'kt':
        return 'kotlin';
      case 'objc':
        return 'objectivec';
      case 'c++':
      case 'cpp':
        return 'cpp';
      case 'c#':
      case 'csharp':
        return 'cs';
      case 'golang':
        return 'go';
      default:
        return language.toLowerCase();
    }
  }

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

  // 借鉴 flutter_highlight 的 highlight.parse() 替代自研 _tokenize 方法
  // 将语法解析结果（Node 树）转换为按行分割的 TextSpan 列表
  // 来源: https://pub.dev/packages/flutter_highlight
  List<List<TextSpan>> _buildHighlightedLines(String code, Map<String, TextStyle> theme) {
    final lang = _mapLanguage(widget.language);
    final result = highlight.parse(code, language: lang);

    // 将 Node 树扁平化为 (文本, 样式类名) 对列表
    final flatTokens = <_FlatToken>[];
    void visitNodes(List<Node> nodes, [String? parentClass]) {
      for (final node in nodes) {
        final className = node.className ?? parentClass;
        if (node.value != null) {
          flatTokens.add(_FlatToken(node.value!, className));
        }
        if (node.children != null) {
          visitNodes(node.children!, className);
        }
      }
    }

    if (result.nodes != null) {
      visitNodes(result.nodes!);
    }

    // 按换行符分割为多行 TextSpan
    final lines = <List<TextSpan>>[];
    var currentLine = <TextSpan>[];
    final baseStyle = TextStyle(fontFamily: 'monospace', fontSize: 13);

    for (final token in flatTokens) {
      final parts = token.text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) {
          // 遇到换行符，结束当前行
          lines.add(currentLine);
          currentLine = <TextSpan>[];
        }
        if (parts[i].isNotEmpty) {
          final style = token.className != null && theme.containsKey(token.className)
              ? baseStyle.merge(theme[token.className])
              : baseStyle;
          currentLine.add(TextSpan(text: parts[i], style: style));
        }
      }
    }
    // 添加最后一行
    lines.add(currentLine);

    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final themeMeta = _themeMeta[_theme]!;
    final highlightTheme = _highlightThemes[_theme]!;
    final highlightedLines = _buildHighlightedLines(widget.content, highlightTheme);

    return Container(
      decoration: BoxDecoration(
        color: themeMeta.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(themeMeta),
          const Divider(height: 1, thickness: 1, color: Color(0xFF444444)),
          Row(
            children: [
              _buildLineNumbers(highlightedLines.length, themeMeta),
              Expanded(
                child: _wrapText
                    ? _buildWrappedCode(highlightedLines, themeMeta)
                    : _buildScrollableCode(highlightedLines, themeMeta),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(_ThemeMeta themeMeta) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          if (widget.language != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: themeMeta.foreground.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.language!.toUpperCase(),
                style: TextStyle(
                  color: themeMeta.foreground,
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
              color: themeMeta.foreground.withValues(alpha: 0.6),
            ),
            onPressed: () => setState(() => _wrapText = !_wrapText),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          PopupMenuButton<CodeTheme>(
            icon: Icon(
              Icons.palette,
              size: 16,
              color: themeMeta.foreground.withValues(alpha: 0.6),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onSelected: (value) => setState(() => _theme = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: CodeTheme.vscodeDark, child: Text('VS Code Dark')),
              const PopupMenuItem(value: CodeTheme.githubLight, child: Text('GitHub Light')),
              const PopupMenuItem(value: CodeTheme.monokai, child: Text('Monokai Sublime')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLineNumbers(int lineCount, _ThemeMeta themeMeta) {
    return Container(
      width: 48,
      color: themeMeta.lineNumberBackground,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(lineCount, (index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: themeMeta.lineNumber,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildScrollableCode(List<List<TextSpan>> highlightedLines, _ThemeMeta themeMeta) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: highlightedLines.map((lineSpans) => _buildCodeLine(lineSpans)).toList(),
      ),
    );
  }

  Widget _buildWrappedCode(List<List<TextSpan>> highlightedLines, _ThemeMeta themeMeta) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: highlightedLines.map((lineSpans) => _buildCodeLine(lineSpans)).toList(),
      ),
    );
  }

  // 借鉴 flutter_highlight 的语法解析结果渲染代码行
  // 替代原 _buildCodeLine + _tokenize 的自研方案
  Widget _buildCodeLine(List<TextSpan> lineSpans) {
    if (lineSpans.isEmpty) {
      return const SizedBox(height: 18);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RichText(
        text: TextSpan(
          children: lineSpans,
        ),
      ),
    );
  }
}

/// 扁平化的语法 token —— 借鉴 flutter_highlight 的 Node 结构简化而来
/// 用于将 Node 树转换为按行分割的中间表示
class _FlatToken {
  final String text;
  final String? className;
  const _FlatToken(this.text, this.className);
}

/// 主题元数据 —— 保留背景色、前景色、行号色等 UI 配色
/// 语法高亮的具体 token 颜色由 flutter_highlight 内置主题提供
class _ThemeMeta {
  final Color background;
  final Color foreground;
  final Color lineNumber;
  final Color lineNumberBackground;

  const _ThemeMeta({
    required this.background,
    required this.foreground,
    required this.lineNumber,
    required this.lineNumberBackground,
  });
}
