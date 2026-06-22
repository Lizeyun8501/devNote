import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 虚拟滚动列表
/// 只渲染可见区域的 item，大幅提升长列表性能
class VirtualListView<T> extends StatefulWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final double itemExtent; // 每个 item 的高度
  final Widget? separator;
  final EdgeInsets padding;
  final ScrollController? controller;
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final Widget? loadingIndicator;

  const VirtualListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.itemExtent,
    this.separator,
    this.padding = EdgeInsets.zero,
    this.controller,
    this.onLoadMore,
    this.hasMore = false,
    this.loadingIndicator,
  });

  @override
  State<VirtualListView<T>> createState() => _VirtualListViewState<T>();
}

class _VirtualListViewState<T> extends State<VirtualListView<T>> {
  late ScrollController _controller;
  static const double _overscan = 500; // 预渲染区域

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ScrollController();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onScroll() {
    if (widget.hasMore &&
        widget.onLoadMore != null &&
        _controller.position.pixels >=
            _controller.position.maxScrollExtent - 200) {
      widget.onLoadMore!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      child: CustomScrollView(
        controller: _controller,
        slivers: [
          if (widget.padding != EdgeInsets.zero)
            SliverPadding(padding: widget.padding),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= widget.items.length) {
                  return widget.loadingIndicator ??
                      const SizedBox(
                        height: 48,
                        child: Center(child: CircularProgressIndicator()),
                      );
                }
                return widget.itemBuilder(
                  context,
                  widget.items[index],
                  index,
                );
              },
              childCount: widget.hasMore
                  ? widget.items.length + 1
                  : widget.items.length,
            ),
          ),
        ],
      ),
    );
  }
}

/// 延迟加载 Widget
/// 用于优化移动端首屏加载性能
class DeferredWidget extends StatefulWidget {
  final WidgetBuilder builder;
  final Widget? placeholder;

  const DeferredWidget({
    super.key,
    required this.builder,
    this.placeholder,
  });

  @override
  State<DeferredWidget> createState() => _DeferredWidgetState();
}

class _DeferredWidgetState extends State<DeferredWidget> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // 延迟到下一帧加载，避免阻塞首屏渲染
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _loaded = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loaded) {
      return widget.builder(context);
    }
    return widget.placeholder ??
        const SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        );
  }
}
