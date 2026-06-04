import 'package:flutter/material.dart';
import 'package:devnote/features/canvas/canvas_service.dart';

class CanvasToolbar extends StatelessWidget {
  final VoidCallback onAddNote;
  final VoidCallback onAddImage;
  final VoidCallback onAddFile;
  final VoidCallback onAddLink;
  final VoidCallback onAddGroup;
  final void Function(LayoutType type) onAutoLayout;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;
  final VoidCallback onSave;

  const CanvasToolbar({
    super.key,
    required this.onAddNote,
    required this.onAddImage,
    required this.onAddFile,
    required this.onAddLink,
    required this.onAddGroup,
    required this.onAutoLayout,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: '添加节点',
          onSelected: (value) {
            switch (value) {
              case 'note':
                onAddNote();
              case 'image':
                onAddImage();
              case 'file':
                onAddFile();
              case 'link':
                onAddLink();
              case 'group':
                onAddGroup();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'note', child: Row(children: [Icon(Icons.note_outlined, size: 18), SizedBox(width: 8), Text('笔记')])),
            const PopupMenuItem(value: 'image', child: Row(children: [Icon(Icons.image_outlined, size: 18), SizedBox(width: 8), Text('图片')])),
            const PopupMenuItem(value: 'file', child: Row(children: [Icon(Icons.insert_drive_file_outlined, size: 18), SizedBox(width: 8), Text('文件')])),
            const PopupMenuItem(value: 'link', child: Row(children: [Icon(Icons.link, size: 18), SizedBox(width: 8), Text('链接')])),
            const PopupMenuItem(value: 'group', child: Row(children: [Icon(Icons.crop_free, size: 18), SizedBox(width: 8), Text('分组')])),
          ],
        ),
        PopupMenuButton<LayoutType>(
          icon: const Icon(Icons.auto_fix_high_outlined),
          tooltip: '自动布局',
          onSelected: onAutoLayout,
          itemBuilder: (context) => [
            const PopupMenuItem(value: LayoutType.grid, child: Text('网格布局')),
            const PopupMenuItem(value: LayoutType.force, child: Text('力导向布局')),
            const PopupMenuItem(value: LayoutType.hierarchical, child: Text('层次布局')),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.zoom_in),
          tooltip: '放大',
          onPressed: onZoomIn,
        ),
        IconButton(
          icon: const Icon(Icons.zoom_out),
          tooltip: '缩小',
          onPressed: onZoomOut,
        ),
        IconButton(
          icon: const Icon(Icons.fit_screen_outlined),
          tooltip: '重置缩放',
          onPressed: onZoomReset,
        ),
        IconButton(
          icon: const Icon(Icons.save_outlined),
          tooltip: '保存',
          onPressed: onSave,
        ),
      ],
    );
  }
}
