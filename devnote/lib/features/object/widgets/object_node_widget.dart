import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:devnote/features/object/object_service.dart';

class ObjectNodeWidget extends StatelessWidget {
  final ObjectModel object;
  final ObjectTypeModel? objectType;
  final Offset position;
  final VoidCallback? onTap;

  const ObjectNodeWidget({
    super.key,
    required this.object,
    this.objectType,
    required this.position,
    this.onTap,
  });

  static void paintNode(Canvas canvas, Offset position, ObjectModel object, ObjectTypeModel? objectType) {
    const nodeSize = 120.0;
    const nodeHeight = 60.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: position, width: nodeSize, height: nodeHeight),
      const Radius.circular(8),
    );

    final paint = Paint()
      ..color = _getColorForType(objectType)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rect, paint);

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(rect, borderPaint);

    final name = object.properties['name']?.toString() ?? object.properties['title']?.toString() ?? objectType?.name ?? '对象';
    final tp = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 12))
      ..pushStyle(ui.TextStyle(color: Colors.white))
      ..addText(name);
    final paragraph = tp.build()..layout(ui.ParagraphConstraints(width: nodeSize - 16));
    canvas.drawParagraph(paragraph, Offset(position.dx - (nodeSize - 16) / 2, position.dy - paragraph.height / 2));
  }

  static Color _getColorForType(ObjectTypeModel? type) {
    if (type == null) return Colors.grey;
    final hash = type.id.hashCode;
    final colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.teal, Colors.pink];
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - 60,
      top: position.dy - 30,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 120,
          height: 60,
          decoration: BoxDecoration(
            color: _getColorForType(objectType),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: Text(
              object.properties['name']?.toString() ?? object.properties['title']?.toString() ?? objectType?.name ?? '对象',
              style: const TextStyle(color: Colors.white, fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
