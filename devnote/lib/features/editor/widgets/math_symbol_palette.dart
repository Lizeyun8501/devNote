import 'package:flutter/material.dart';

/// 数学符号分类
enum MathSymbolCategory {
  basicOps('基础运算'),
  relations('关系符'),
  greekLower('希腊字母'),
  greekUpper('大写希腊'),
  arrows('箭头'),
  calc('求和积分'),
  radicals('根号对数'),
  sets('集合'),
  matrix('矩阵'),
  ;

  final String label;
  const MathSymbolCategory(this.label);
}

/// 数学符号条目
class MathSymbolEntry {
  /// 显示的符号（Unicode 字符）
  final String display;

  /// 插入到 LaTeX 中的文本
  final String latex;

  /// 关键词（用于搜索，包含符号名与别名）
  final List<String> keywords;

  const MathSymbolEntry({
    required this.display,
    required this.latex,
    this.keywords = const [],
  });
}

/// 各分类的符号表
const Map<MathSymbolCategory, List<MathSymbolEntry>> kMathSymbols = {
  MathSymbolCategory.basicOps: [
    MathSymbolEntry(display: '+', latex: '+', keywords: ['plus', '加']),
    MathSymbolEntry(display: '-', latex: '-', keywords: ['minus', '减']),
    MathSymbolEntry(display: '×', latex: '\\times', keywords: ['times', '乘']),
    MathSymbolEntry(display: '÷', latex: '\\div', keywords: ['div', '除']),
    MathSymbolEntry(display: '=', latex: '=', keywords: ['equal', '等于']),
    MathSymbolEntry(display: '≠', latex: '\\neq', keywords: ['neq', '不等于']),
    MathSymbolEntry(display: '≈', latex: '\\approx', keywords: ['approx', '约等于']),
    MathSymbolEntry(display: '±', latex: '\\pm', keywords: ['pm', '正负']),
    MathSymbolEntry(display: '∓', latex: '\\mp', keywords: ['mp']),
    MathSymbolEntry(display: '·', latex: '\\cdot', keywords: ['cdot', '点乘']),
  ],
  MathSymbolCategory.relations: [
    MathSymbolEntry(display: '<', latex: '<', keywords: ['lt', '小于']),
    MathSymbolEntry(display: '>', latex: '>', keywords: ['gt', '大于']),
    MathSymbolEntry(display: '≤', latex: '\\leq', keywords: ['leq', 'le', '小于等于']),
    MathSymbolEntry(display: '≥', latex: '\\geq', keywords: ['geq', 'ge', '大于等于']),
    MathSymbolEntry(display: '∈', latex: '\\in', keywords: ['in', '属于']),
    MathSymbolEntry(display: '∉', latex: '\\notin', keywords: ['notin', '不属于']),
    MathSymbolEntry(display: '⊂', latex: '\\subset', keywords: ['subset', '真子集']),
    MathSymbolEntry(display: '⊃', latex: '\\supset', keywords: ['supset']),
    MathSymbolEntry(display: '⊆', latex: '\\subseteq', keywords: ['subseteq']),
    MathSymbolEntry(display: '⊇', latex: '\\supseteq', keywords: ['supseteq']),
    MathSymbolEntry(display: '∝', latex: '\\propto', keywords: ['propto', '正比']),
  ],
  MathSymbolCategory.greekLower: [
    MathSymbolEntry(display: 'α', latex: '\\alpha', keywords: ['alpha']),
    MathSymbolEntry(display: 'β', latex: '\\beta', keywords: ['beta']),
    MathSymbolEntry(display: 'γ', latex: '\\gamma', keywords: ['gamma']),
    MathSymbolEntry(display: 'δ', latex: '\\delta', keywords: ['delta']),
    MathSymbolEntry(display: 'ε', latex: '\\epsilon', keywords: ['epsilon']),
    MathSymbolEntry(display: 'θ', latex: '\\theta', keywords: ['theta']),
    MathSymbolEntry(display: 'λ', latex: '\\lambda', keywords: ['lambda']),
    MathSymbolEntry(display: 'μ', latex: '\\mu', keywords: ['mu']),
    MathSymbolEntry(display: 'π', latex: '\\pi', keywords: ['pi']),
    MathSymbolEntry(display: 'σ', latex: '\\sigma', keywords: ['sigma']),
    MathSymbolEntry(display: 'φ', latex: '\\phi', keywords: ['phi']),
    MathSymbolEntry(display: 'ω', latex: '\\omega', keywords: ['omega']),
  ],
  MathSymbolCategory.greekUpper: [
    MathSymbolEntry(display: 'Α', latex: 'A', keywords: ['Alpha']),
    MathSymbolEntry(display: 'Β', latex: 'B', keywords: ['Beta']),
    MathSymbolEntry(display: 'Γ', latex: '\\Gamma', keywords: ['Gamma']),
    MathSymbolEntry(display: 'Δ', latex: '\\Delta', keywords: ['Delta']),
    MathSymbolEntry(display: 'Θ', latex: '\\Theta', keywords: ['Theta']),
    MathSymbolEntry(display: 'Λ', latex: '\\Lambda', keywords: ['Lambda']),
    MathSymbolEntry(display: 'Π', latex: '\\Pi', keywords: ['Pi']),
    MathSymbolEntry(display: 'Σ', latex: '\\Sigma', keywords: ['Sigma']),
    MathSymbolEntry(display: 'Φ', latex: '\\Phi', keywords: ['Phi']),
    MathSymbolEntry(display: 'Ω', latex: '\\Omega', keywords: ['Omega']),
  ],
  MathSymbolCategory.arrows: [
    MathSymbolEntry(display: '→', latex: '\\to', keywords: ['to', 'rightarrow', '右箭头']),
    MathSymbolEntry(display: '←', latex: '\\leftarrow', keywords: ['leftarrow', '左箭头']),
    MathSymbolEntry(display: '↔', latex: '\\leftrightarrow', keywords: ['leftrightarrow']),
    MathSymbolEntry(display: '⇒', latex: '\\Rightarrow', keywords: ['Rightarrow', '推出']),
    MathSymbolEntry(display: '⇔', latex: '\\Leftrightarrow', keywords: ['Leftrightarrow']),
    MathSymbolEntry(display: '↑', latex: '\\uparrow', keywords: ['uparrow']),
    MathSymbolEntry(display: '↓', latex: '\\downarrow', keywords: ['downarrow']),
    MathSymbolEntry(display: '↦', latex: '\\mapsto', keywords: ['mapsto']),
  ],
  MathSymbolCategory.calc: [
    MathSymbolEntry(display: '∑', latex: '\\sum', keywords: ['sum', '求和']),
    MathSymbolEntry(display: '∫', latex: '\\int', keywords: ['int', '积分']),
    MathSymbolEntry(display: '∮', latex: '\\oint', keywords: ['oint', '环路积分']),
    MathSymbolEntry(display: '∏', latex: '\\prod', keywords: ['prod', '乘积']),
    MathSymbolEntry(display: '∬', latex: '\\iint', keywords: ['iint', '二重积分']),
    MathSymbolEntry(display: '∭', latex: '\\iiint', keywords: ['iiint', '三重积分']),
    MathSymbolEntry(display: 'lim', latex: '\\lim', keywords: ['lim', '极限']),
  ],
  MathSymbolCategory.radicals: [
    MathSymbolEntry(display: '√', latex: '\\sqrt', keywords: ['sqrt', '根号']),
    MathSymbolEntry(display: '∛', latex: '\\sqrt[3]', keywords: ['cbrt', '三次根']),
    MathSymbolEntry(display: '∜', latex: '\\sqrt[4]', keywords: ['四次根']),
    MathSymbolEntry(display: 'log', latex: '\\log', keywords: ['log', '对数']),
    MathSymbolEntry(display: 'ln', latex: '\\ln', keywords: ['ln', '自然对数']),
    MathSymbolEntry(display: 'exp', latex: '\\exp', keywords: ['exp', '指数']),
  ],
  MathSymbolCategory.sets: [
    MathSymbolEntry(display: '∪', latex: '\\cup', keywords: ['cup', '并集']),
    MathSymbolEntry(display: '∩', latex: '\\cap', keywords: ['cap', '交集']),
    MathSymbolEntry(display: '∅', latex: '\\emptyset', keywords: ['emptyset', '空集']),
    MathSymbolEntry(display: '⊕', latex: '\\oplus', keywords: ['oplus']),
    MathSymbolEntry(display: '⊗', latex: '\\otimes', keywords: ['otimes']),
    MathSymbolEntry(display: '∀', latex: '\\forall', keywords: ['forall', '任意']),
    MathSymbolEntry(display: '∃', latex: '\\exists', keywords: ['exists', '存在']),
    MathSymbolEntry(display: 'ℕ', latex: '\\mathbb{N}', keywords: ['N', '自然数集']),
    MathSymbolEntry(display: 'ℤ', latex: '\\mathbb{Z}', keywords: ['Z', '整数集']),
    MathSymbolEntry(display: 'ℚ', latex: '\\mathbb{Q}', keywords: ['Q', '有理数集']),
    MathSymbolEntry(display: 'ℝ', latex: '\\mathbb{R}', keywords: ['R', '实数集']),
    MathSymbolEntry(display: 'ℂ', latex: '\\mathbb{C}', keywords: ['C', '复数集']),
  ],
  MathSymbolCategory.matrix: [
    MathSymbolEntry(display: '( )', latex: '\\left( \\right)', keywords: ['paren', '圆括号']),
    MathSymbolEntry(display: '[ ]', latex: '\\left[ \\right]', keywords: ['bracket', '方括号']),
    MathSymbolEntry(display: '{ }', latex: '\\left\\{ \\right\\}', keywords: ['brace', '花括号']),
    MathSymbolEntry(display: 'matrix', latex: '\\begin{matrix} \\\\ \\end{matrix}', keywords: ['matrix', '矩阵']),
    MathSymbolEntry(display: 'pmatrix', latex: '\\begin{pmatrix} \\\\ \\end{pmatrix}', keywords: ['pmatrix']),
    MathSymbolEntry(display: 'bmatrix', latex: '\\begin{bmatrix} \\\\ \\end{bmatrix}', keywords: ['bmatrix']),
    MathSymbolEntry(display: 'vmatrix', latex: '\\begin{vmatrix} \\\\ \\end{vmatrix}', keywords: ['vmatrix', '行列式']),
    MathSymbolEntry(display: 'cases', latex: '\\begin{cases} \\\\ \\end{cases}', keywords: ['cases', '分段函数']),
  ],
};

/// 公式符号面板（P2-9）
///
/// 分类显示常用数学符号，点击符号插入到当前 LaTeX 编辑位置。
/// 支持按符号名/别名搜索。
class MathSymbolPalette extends StatefulWidget {
  /// 符号插入回调
  ///
  /// 参数为符号的 LaTeX 表示，调用方负责将其插入到当前编辑位置。
  final ValueChanged<String> onInsertSymbol;

  /// 是否显示搜索框
  final bool showSearch;

  const MathSymbolPalette({
    super.key,
    required this.onInsertSymbol,
    this.showSearch = true,
  });

  @override
  State<MathSymbolPalette> createState() => _MathSymbolPaletteState();
}

class _MathSymbolPaletteState extends State<MathSymbolPalette>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: MathSymbolCategory.values.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 搜索过滤后的符号（跨所有分类）
  List<MathSymbolEntry> _searchResults() {
    if (_searchQuery.isEmpty) return [];
    final q = _searchQuery.toLowerCase();
    final results = <MathSymbolEntry>[];
    for (final entries in kMathSymbols.values) {
      for (final entry in entries) {
        if (entry.display.toLowerCase().contains(q) ||
            entry.latex.toLowerCase().contains(q) ||
            entry.keywords.any((k) => k.toLowerCase().contains(q))) {
          results.add(entry);
        }
      }
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // 搜索框
        if (widget.showSearch)
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索符号（如 alpha, sum, 求和）...',
                prefixIcon: Icon(Icons.search, size: 18),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                isDense: true,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim();
                });
              },
            ),
          ),

        // 搜索结果 / 分类标签 + 网格
        if (_searchQuery.isNotEmpty)
          Expanded(child: _buildSearchResults(theme))
        else ...[
          // 分类标签栏
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: MathSymbolCategory.values
                .map((c) => Tab(text: c.label))
                .toList(),
          ),
          // 分类内容
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: MathSymbolCategory.values
                  .map((c) => _buildCategoryGrid(c, theme))
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  /// 搜索结果网格
  Widget _buildSearchResults(ThemeData theme) {
    final results = _searchResults();
    if (results.isEmpty) {
      return Center(
        child: Text(
          '未找到匹配的符号',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 56,
        childAspectRatio: 1,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) => _buildSymbolButton(results[index], theme),
    );
  }

  /// 单个分类的符号网格
  Widget _buildCategoryGrid(MathSymbolCategory category, ThemeData theme) {
    final entries = kMathSymbols[category] ?? [];
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 56,
        childAspectRatio: 1,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) => _buildSymbolButton(entries[index], theme),
    );
  }

  /// 单个符号按钮
  Widget _buildSymbolButton(MathSymbolEntry entry, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Tooltip(
      message: '${entry.display}  →  ${entry.latex}',
      child: InkWell(
        onTap: () => widget.onInsertSymbol(entry.latex),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E32) : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isDark ? const Color(0xFF2D2D44) : const Color(0xFFE5E7EB),
            ),
          ),
          child: Text(
            entry.display,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
