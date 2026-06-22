import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/whiteboard/bloc/whiteboard_bloc.dart';
import 'package:devnote/features/whiteboard/bloc/whiteboard_event.dart';
import 'package:devnote/features/whiteboard/bloc/whiteboard_state.dart';
import 'package:devnote/features/whiteboard/models/whiteboard_element.dart';
import 'package:devnote/features/whiteboard/whiteboard_service.dart';
import 'package:devnote/features/whiteboard/widgets/whiteboard_canvas.dart';
import 'package:devnote/features/whiteboard/widgets/whiteboard_toolbar.dart';

/// 白板页面 —— Excalidraw 风格的手绘画布
///
/// 通过 `/whiteboard/:noteId` 路由访问，加载/保存白板数据到
/// `whiteboard_$noteId` SharedPreferences key 中。
class WhiteboardPage extends StatelessWidget {
  final String noteId;

  const WhiteboardPage({super.key, required this.noteId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => WhiteboardBloc()..add(LoadWhiteboard(const [])),
      child: _WhiteboardView(noteId: noteId),
    );
  }
}

class _WhiteboardView extends StatefulWidget {
  final String noteId;

  const _WhiteboardView({required this.noteId});

  @override
  State<_WhiteboardView> createState() => _WhiteboardViewState();
}

class _WhiteboardViewState extends State<_WhiteboardView> {
  @override
  void initState() {
    super.initState();
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    try {
      final svc = getIt<WhiteboardService>();
      final elements = await svc.loadWhiteboard(widget.noteId);
      if (!mounted) return;
      context.read<WhiteboardBloc>().add(LoadWhiteboard(elements));
    } catch (_) {
      // 忽略加载失败，使用空画布
    }
  }

  Future<void> _save() async {
    final state = context.read<WhiteboardBloc>().state;
    if (state is! WhiteboardLoaded) return;
    try {
      final svc = getIt<WhiteboardService>();
      await svc.saveWhiteboard(widget.noteId, state.elements);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('白板已保存')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Future<void> _export() async {
    final bloc = context.read<WhiteboardBloc>();
    bloc.add(ExportWhiteboard());
    // 等待状态切换
    await Future.delayed(const Duration(milliseconds: 50));
    final state = bloc.state;
    final json = state is WhiteboardExported
        ? state.jsonString
        : (state is WhiteboardLoaded
            ? WhiteboardSerializer.encode(state.elements)
            : '');
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出白板'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(json.isEmpty ? '（空白板）' : json),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _onTextRequest(Offset position) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入文本'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(hintText: '输入文本内容'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    if (!mounted) return;
    final state = context.read<WhiteboardBloc>().state;
    if (state is! WhiteboardLoaded) return;
    final element = TextElement(
      id: const Uuid().v4(),
      x: position.dx,
      y: position.dy,
      text: text,
      strokeColor: state.strokeColor,
    );
    context.read<WhiteboardBloc>().add(AddElement(element));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('白板'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: '保存',
            onPressed: _save,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '导出',
            onPressed: _export,
          ),
        ],
      ),
      body: BlocBuilder<WhiteboardBloc, WhiteboardState>(
        builder: (context, state) {
          if (state is! WhiteboardLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          return Stack(
            children: [
              WhiteboardCanvas(
                elements: state.elements,
                selectedElementId: state.selectedElementId,
                currentTool: state.currentTool,
                strokeColor: state.strokeColor,
                strokeWidth: state.strokeWidth,
                showGrid: state.showGrid,
                onAddElement: (element) =>
                    context.read<WhiteboardBloc>().add(AddElement(element)),
                onUpdateElement: (id, element) => context
                    .read<WhiteboardBloc>()
                    .add(UpdateElement(id, element)),
                onDeleteElement: (id) =>
                    context.read<WhiteboardBloc>().add(DeleteElement(id)),
                onSelectElement: (id) =>
                    context.read<WhiteboardBloc>().add(SelectElement(id)),
                onCommitElement: (_) {
                  // 选中拖拽结束时触发一次历史快照
                  // 通过 Undo/Redo 栈管理在 AddElement/UpdateElement 中已处理
                },
                onTextRequest: _onTextRequest,
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Center(
                  child: WhiteboardToolbar(
                    currentTool: state.currentTool,
                    strokeColor: state.strokeColor,
                    strokeWidth: state.strokeWidth,
                    showGrid: state.showGrid,
                    canUndo: state.canUndo,
                    canRedo: state.canRedo,
                    onToolChanged: (tool) =>
                        context.read<WhiteboardBloc>().add(ChangeTool(tool)),
                    onColorChanged: (c) => context
                        .read<WhiteboardBloc>()
                        .add(ChangeStrokeColor(c)),
                    onStrokeWidthChanged: (w) => context
                        .read<WhiteboardBloc>()
                        .add(ChangeStrokeWidth(w)),
                    onUndo: () =>
                        context.read<WhiteboardBloc>().add(Undo()),
                    onRedo: () =>
                        context.read<WhiteboardBloc>().add(Redo()),
                    onClear: () {
                      showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('清空画布'),
                          content: const Text('确定要清空所有元素吗？此操作可通过撤销恢复。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('清空'),
                            ),
                          ],
                        ),
                      ).then((confirmed) {
                        if (confirmed == true) {
                          context
                              .read<WhiteboardBloc>()
                              .add(ClearCanvas());
                        }
                      });
                    },
                    onExport: _export,
                    onToggleGrid: () =>
                        context.read<WhiteboardBloc>().add(ToggleGrid()),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
