import 'package:flutter/material.dart';

/// 支持滑动手势的笔记卡片
/// 左滑显示删除按钮，右滑显示收藏按钮
class SwipeableNoteCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleFavorite;
  final bool isFavorite;

  const SwipeableNoteCard({
    super.key,
    required this.child,
    this.onDelete,
    this.onToggleFavorite,
    this.isFavorite = false,
  });

  @override
  State<SwipeableNoteCard> createState() => _SwipeableNoteCardState();
}

class _SwipeableNoteCardState extends State<SwipeableNoteCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _animation;
  double _dragExtent = 0;
  static const double _actionThreshold = 80.0;
  static const double _maxDrag = 120.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() {
    _controller.reverse();
    setState(() => _dragExtent = 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _dragExtent += details.delta.dx;
          _dragExtent = _dragExtent.clamp(-_maxDrag, _maxDrag);
        });
      },
      onHorizontalDragEnd: (details) {
        if (_dragExtent < -_actionThreshold) {
          // 左滑触发删除
          widget.onDelete?.call();
          _reset();
        } else if (_dragExtent > _actionThreshold) {
          // 右滑触发收藏
          widget.onToggleFavorite?.call();
          _reset();
        } else {
          _reset();
        }
      },
      child: Stack(
        children: [
          // 背景操作按钮
          Positioned.fill(
            child: Row(
              children: [
                // 右滑显示的收藏按钮（左侧）
                if (_dragExtent > 0)
                  Expanded(
                    flex: _dragExtent > 0 ? (_dragExtent * 100 ~/ _maxDrag) : 0,
                    child: Container(
                      color: Colors.amber,
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.star, color: Colors.white),
                            SizedBox(height: 4),
                            Text('收藏', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                // 左滑显示的删除按钮（右侧）
                if (_dragExtent < 0)
                  Expanded(
                    flex: _dragExtent < 0 ? (-_dragExtent * 100 ~/ _maxDrag) : 0,
                    child: Container(
                      color: Colors.red,
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete, color: Colors.white),
                            SizedBox(height: 4),
                            Text('删除', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 前景内容
          Transform.translate(
            offset: Offset(_dragExtent, 0),
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}
