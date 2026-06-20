import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'bloc/freeform_bloc.dart';
import 'models/freeform_element.dart';
import 'widgets/freeform_element_widget.dart';
import 'widgets/freeform_toolbar.dart';

class FreeformPage extends StatelessWidget {
  final String pageId;
  final String pageTitle;

  const FreeformPage({
    super.key,
    required this.pageId,
    required this.pageTitle,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          FreeformBloc(pageId: pageId)..add(LoadFreeformPage(pageId)),
      child: BlocBuilder<FreeformBloc, FreeformState>(
        builder: (context, state) {
          return Scaffold(
            appBar: AppBar(
              title: Text(pageTitle),
              actions: [
                FreeformToolbar(
                  currentTool: state is FreeformLoaded
                      ? state.currentTool
                      : FreeformTool.select,
                  onToolChanged: (tool) =>
                      context.read<FreeformBloc>().add(ChangeTool(tool)),
                  onAddElement: (type) =>
                      context.read<FreeformBloc>().add(AddElement(type)),
                  onUndo: () =>
                      context.read<FreeformBloc>().add(UndoFreeform()),
                  onRedo: () =>
                      context.read<FreeformBloc>().add(RedoFreeform()),
                ),
              ],
            ),
            body: state is FreeformLoaded
                ? _FreeformCanvas(
                    data: state.data,
                    selectedElementId: state.selectedElementId,
                    editingElementId: state.editingElementId,
                    onElementTap: (id) =>
                        context.read<FreeformBloc>().add(SelectElement(id)),
                    onElementDoubleTap: (id) => context
                        .read<FreeformBloc>()
                        .add(StartEditingElement(id)),
                    onElementChanged: (element) => context
                        .read<FreeformBloc>()
                        .add(UpdateElement(element)),
                    onElementDragEnd: () =>
                        context.read<FreeformBloc>().add(EndDragElement()),
                    onCanvasTap: (position) =>
                        context.read<FreeformBloc>().add(CanvasTap(position)),
                  )
                : const Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }
}

class _FreeformCanvas extends StatelessWidget {
  final FreeformPageData data;
  final String? selectedElementId;
  final String? editingElementId;
  final void Function(String)? onElementTap;
  final void Function(String)? onElementDoubleTap;
  final void Function(FreeformElement)? onElementChanged;
  final VoidCallback? onElementDragEnd;
  final void Function(Offset)? onCanvasTap;

  const _FreeformCanvas({
    required this.data,
    this.selectedElementId,
    this.editingElementId,
    this.onElementTap,
    this.onElementDoubleTap,
    this.onElementChanged,
    this.onElementDragEnd,
    this.onCanvasTap,
  });

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.25,
      maxScale: 4.0,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      child: GestureDetector(
        onTapUp: (details) => onCanvasTap?.call(details.localPosition),
        child: Container(
          width: data.canvasSize.width,
          height: data.canvasSize.height,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 网格背景
              CustomPaint(
                size: data.canvasSize,
                painter: _GridPainter(),
              ),
              // 元素列表（按 zIndex 排序）
              ...data.elements.map((element) {
                return FreeformElementWidget(
                  key: ValueKey(element.id),
                  element: element,
                  isSelected: element.id == selectedElementId,
                  isEditing: element.id == editingElementId,
                  onTap: () => onElementTap?.call(element.id),
                  onDoubleTap: () => onElementDoubleTap?.call(element.id),
                  onChanged: onElementChanged,
                  onDragUpdate: (delta) {
                    // 实时更新位置
                    onElementChanged?.call(
                      element.copyWith(
                        position: element.position + delta,
                      ),
                    );
                  },
                  onDragEnd: onElementDragEnd,
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.12)
      ..strokeWidth = 0.5;

    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
