import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../../core/di/injection.dart';
import '../services/math_ink_service.dart';

/// 手写公式输入对话框（P2-9）
///
/// 布局：
/// - 顶部：手写画布（300x200）
/// - 中部：识别结果展示（LaTeX 渲染）
/// - 底部：候选结果切换（左右箭头）、"插入"按钮、"清除"按钮、"重写"按钮
///
/// 手写画布支持多笔画绘制，每笔画结束后触发识别（防抖 500ms）。
class MathInkDialog extends StatefulWidget {
  /// 识别完成后调用，传入 LaTeX 字符串（不含 `$`/`$$` 定界符）
  final ValueChanged<String> onInsert;

  /// 可选：初始 LaTeX 内容（用于编辑现有公式）
  final String initialLatex;

  const MathInkDialog({
    super.key,
    required this.onInsert,
    this.initialLatex = '',
  });

  /// 便捷方法：以对话框形式弹出
  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onInsert,
    String initialLatex = '',
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => MathInkDialog(
        onInsert: onInsert,
        initialLatex: initialLatex,
      ),
    );
  }

  @override
  State<MathInkDialog> createState() => _MathInkDialogState();
}

class _MathInkDialogState extends State<MathInkDialog> {
  /// 已完成的笔画（每笔为 Offset 列表）
  final List<List<Offset>> _strokes = [];

  /// 当前正在绘制的笔画
  List<Offset> _currentStroke = [];

  /// 识别结果
  MathInkRecognitionResult _result = MathInkRecognitionResult.empty();

  /// 当前选中的候选索引
  int _candidateIndex = 0;

  /// 是否正在识别
  bool _isRecognizing = false;

  /// LaTeX 编辑控制器（允许用户手动编辑）
  late final TextEditingController _latexController;

  /// 防抖定时器
  Timer? _debounceTimer;

  /// 错误信息
  String? _error;

  @override
  void initState() {
    super.initState();
    _latexController = TextEditingController(text: widget.initialLatex);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _latexController.dispose();
    super.dispose();
  }

  // ============================================================
  // 手写画布手势处理
  // ============================================================

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _currentStroke = [details.localPosition];
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _currentStroke.add(details.localPosition);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentStroke.isNotEmpty) {
      _strokes.add(List.of(_currentStroke));
      _currentStroke = [];
      _scheduleRecognition();
    }
    setState(() {});
  }

  /// 防抖 500ms 后触发识别
  void _scheduleRecognition() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), _performRecognition);
  }

  // ============================================================
  // 识别
  // ============================================================

  Future<void> _performRecognition() async {
    if (_strokes.isEmpty) return;
    setState(() {
      _isRecognizing = true;
      _error = null;
    });

    try {
      final service = getIt<MathInkService>();
      final result = await service.recognizeStrokes(_strokes);
      setState(() {
        _result = result;
        _candidateIndex = 0;
        _isRecognizing = false;
        final candidates = result.allCandidates;
        if (candidates.isNotEmpty) {
          _latexController.text = candidates.first;
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isRecognizing = false;
      });
    }
  }

  // ============================================================
  // 候选切换
  // ============================================================

  void _previousCandidate() {
    final candidates = _result.allCandidates;
    if (candidates.isEmpty) return;
    setState(() {
      _candidateIndex = (_candidateIndex - 1 + candidates.length) % candidates.length;
      _latexController.text = candidates[_candidateIndex];
    });
  }

  void _nextCandidate() {
    final candidates = _result.allCandidates;
    if (candidates.isEmpty) return;
    setState(() {
      _candidateIndex = (_candidateIndex + 1) % candidates.length;
      _latexController.text = candidates[_candidateIndex];
    });
  }

  // ============================================================
  // 操作按钮
  // ============================================================

  void _clearAll() {
    setState(() {
      _strokes.clear();
      _currentStroke = [];
      _result = MathInkRecognitionResult.empty();
      _candidateIndex = 0;
      _latexController.clear();
      _error = null;
    });
    _debounceTimer?.cancel();
  }

  void _rewrite() {
    // 仅清除笔迹，保留当前 LaTeX 作为参考
    setState(() {
      _strokes.clear();
      _currentStroke = [];
    });
    _debounceTimer?.cancel();
  }

  void _insert() {
    final latex = _latexController.text.trim();
    widget.onInsert(latex);
    Navigator.of(context).pop();
  }

  // ============================================================
  // UI 构建
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题
              Row(
                children: [
                  Icon(Icons.edit_note, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('手写公式识别', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  if (_isRecognizing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // 手写画布
              _buildCanvas(theme, isDark),
              const SizedBox(height: 12),

              // 识别结果展示
              _buildResultPreview(theme, isDark),
              const SizedBox(height: 8),

              // 候选切换
              _buildCandidateSwitcher(theme),
              const SizedBox(height: 8),

              // LaTeX 编辑框
              _buildLatexEditor(theme, isDark),
              const SizedBox(height: 8),

              // 错误提示
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '识别失败: $_error',
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                  ),
                ),

              // 操作按钮
              _buildActions(theme),
            ],
          ),
        ),
      ),
    );
  }

  /// 手写画布（300x200）
  Widget _buildCanvas(ThemeData theme, bool isDark) {
    return Container(
      width: 300,
      height: 200,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E32) : Colors.white,
        border: Border.all(
          color: isDark ? const Color(0xFF2D2D44) : const Color(0xFFE5E7EB),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: CustomPaint(
          painter: _InkCanvasPainter(
            strokes: _strokes,
            currentStroke: _currentStroke,
            strokeColor: theme.colorScheme.onSurface,
          ),
          size: const Size(300, 200),
        ),
      ),
    );
  }

  /// 识别结果 LaTeX 渲染
  Widget _buildResultPreview(ThemeData theme, bool isDark) {
    final latex = _latexController.text.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F0F1A) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? const Color(0xFF2D2D44) : const Color(0xFFE5E7EB),
        ),
      ),
      child: latex.isEmpty
          ? Text(
              '手写公式后将在此显示识别结果',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            )
          : Center(
              child: Math.tex(
                latex,
                textStyle: const TextStyle(fontSize: 18),
                mathStyle: MathStyle.display,
                onErrorFallback: (err) => Text(
                  'LaTeX 渲染失败: $err',
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
              ),
            ),
    );
  }

  /// 候选结果切换器
  Widget _buildCandidateSwitcher(ThemeData theme) {
    final candidates = _result.allCandidates;
    final hasCandidates = candidates.length > 1;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: hasCandidates ? _previousCandidate : null,
          tooltip: '上一个候选',
        ),
        Text(
          candidates.isEmpty
              ? '无候选'
              : '候选 ${_candidateIndex + 1} / ${candidates.length}',
          style: theme.textTheme.labelSmall,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: hasCandidates ? _nextCandidate : null,
          tooltip: '下一个候选',
        ),
      ],
    );
  }

  /// LaTeX 编辑框
  Widget _buildLatexEditor(ThemeData theme, bool isDark) {
    return TextField(
      controller: _latexController,
      maxLines: 2,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      decoration: InputDecoration(
        hintText: '可手动编辑 LaTeX...',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF0F0F1A) : Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.all(8),
        prefixIcon: const Icon(Icons.code, size: 16),
        prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
      onChanged: (value) {
        setState(() {});
      },
    );
  }

  /// 底部操作按钮
  Widget _buildActions(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: _clearAll,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('清除'),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: _rewrite,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('重写'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _latexController.text.trim().isEmpty ? null : _insert,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('插入'),
        ),
      ],
    );
  }
}

// ============================================================
// 笔迹绘制器
// ============================================================

class _InkCanvasPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;
  final Color strokeColor;

  _InkCanvasPainter({
    required this.strokes,
    required this.currentStroke,
    required this.strokeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = strokeColor
      ..strokeWidth = 2.0
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      _drawStroke(canvas, stroke, paint);
    }
    if (currentStroke.isNotEmpty) {
      _drawStroke(canvas, currentStroke, paint);
    }
  }

  void _drawStroke(Canvas canvas, List<Offset> stroke, Paint paint) {
    if (stroke.length < 2) {
      // 单点：画一个小圆
      if (stroke.isNotEmpty) {
        canvas.drawCircle(stroke.first, 1.5, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
      }
      return;
    }
    final path = ui.Path()..moveTo(stroke.first.dx, stroke.first.dy);
    for (var i = 1; i < stroke.length; i++) {
      path.lineTo(stroke[i].dx, stroke[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _InkCanvasPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.currentStroke != currentStroke ||
        oldDelegate.strokeColor != strokeColor;
  }
}
