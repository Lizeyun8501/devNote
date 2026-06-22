import 'package:flutter/material.dart';
import '../models/freeform_element.dart';

/// 单个自由画布元素的渲染 Widget
class FreeformElementWidget extends StatelessWidget {
  final FreeformElement element;
  final bool isSelected;
  final bool isEditing;
  final void Function(FreeformElement)? onChanged;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(Offset)? onDragUpdate;
  final VoidCallback? onDragEnd;

  const FreeformElementWidget({
    super.key,
    required this.element,
    this.isSelected = false,
    this.isEditing = false,
    this.onChanged,
    this.onTap,
    this.onDoubleTap,
    this.onDragUpdate,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: element.position.dx,
      top: element.position.dy,
      width: element.size.width,
      height: element.size.height,
      child: Transform.rotate(
        angle: element.rotation * 3.14159 / 180,
        child: GestureDetector(
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          onPanUpdate: (details) => onDragUpdate?.call(details.delta),
          onPanEnd: (_) => onDragEnd?.call(),
          child: Container(
            decoration: BoxDecoration(
              border: isSelected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : null,
              borderRadius: _getBorderRadius(),
              color: _getBackgroundColor(context),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.15),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  BorderRadius _getBorderRadius() {
    switch (element.type) {
      case FreeformElementType.stickyNote:
        return BorderRadius.circular(4);
      case FreeformElementType.image:
        return BorderRadius.circular(8);
      default:
        return BorderRadius.circular(4);
    }
  }

  Color? _getBackgroundColor(BuildContext context) {
    switch (element.type) {
      case FreeformElementType.stickyNote:
        return const Color(0xFFFFF9C4); // 便签黄色
      case FreeformElementType.text:
      case FreeformElementType.richText:
        return Colors.transparent;
      default:
        return null;
    }
  }

  Widget _buildContent(BuildContext context) {
    switch (element.type) {
      case FreeformElementType.text:
        return _buildText(context);
      case FreeformElementType.richText:
        return _buildRichText(context);
      case FreeformElementType.image:
        return _buildImage(context);
      case FreeformElementType.stickyNote:
        return _buildStickyNote(context);
      case FreeformElementType.drawing:
        return _buildDrawing(context);
      case FreeformElementType.audio:
        return _buildAudio(context);
      case FreeformElementType.link:
        return _buildLinkCard(context);
      case FreeformElementType.embed:
        return _buildEmbed(context);
    }
  }

  Widget _buildText(BuildContext context) {
    if (isEditing) {
      return TextField(
        controller: TextEditingController(text: element.content),
        maxLines: null,
        minLines: null,
        expands: true,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(8),
        ),
        style: Theme.of(context).textTheme.bodyMedium,
        onChanged: (text) => onChanged?.call(element.copyWith(content: text)),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        element.content,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  Widget _buildRichText(BuildContext context) {
    // 简化实现：显示纯文本，后续可集成 Markdown 渲染
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        element.content,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        element.content,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, size: 48),
        ),
      ),
    );
  }

  Widget _buildStickyNote(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isEditing)
            Expanded(
              child: TextField(
                controller: TextEditingController(text: element.content),
                maxLines: null,
                minLines: null,
                expands: true,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (text) =>
                    onChanged?.call(element.copyWith(content: text)),
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  element.content,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDrawing(BuildContext context) {
    // 手写绘图内容（SVG path 或点序列）
    return CustomPaint(
      size: element.size,
      painter: _DrawingPainter(element.content),
    );
  }

  Widget _buildAudio(BuildContext context) {
    return const Center(child: Icon(Icons.audio_file, size: 48));
  }

  Widget _buildLinkCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          const Icon(Icons.link, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              element.content,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmbed(BuildContext context) {
    return const Center(child: Icon(Icons.code, size: 48));
  }
}

class _DrawingPainter extends CustomPainter {
  final String svgPath;
  _DrawingPainter(this.svgPath);

  @override
  void paint(Canvas canvas, Size size) {
    // TODO: 解析 SVG path 并绘制
    // 简化实现：绘制占位框
    final paint = Paint()
      ..color = Colors.grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
