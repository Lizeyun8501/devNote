import 'package:flutter/widgets.dart';

class VirtualScrollController extends ChangeNotifier {
  double _scrollOffset = 0.0;
  double _viewportHeight = 0.0;
  double _contentHeight = 0.0;
  double _itemHeight = 48.0;
  int _itemCount = 0;
  int _firstVisibleIndex = 0;
  int _lastVisibleIndex = 0;
  static const int _overscanCount = 5;

  double get scrollOffset => _scrollOffset;
  double get viewportHeight => _viewportHeight;
  int get firstVisibleIndex => _firstVisibleIndex;
  int get lastVisibleIndex => _lastVisibleIndex;
  int get itemCount => _itemCount;

  void configure({required int itemCount, required double itemHeight}) {
    _itemCount = itemCount;
    _itemHeight = itemHeight;
    _contentHeight = itemCount * itemHeight;
    _updateVisibleRange();
    notifyListeners();
  }

  void updateViewportHeight(double height) {
    _viewportHeight = height;
    _updateVisibleRange();
    notifyListeners();
  }

  void updateScrollOffset(double offset) {
    _scrollOffset = offset.clamp(0.0, _contentHeight - _viewportHeight);
    _updateVisibleRange();
    notifyListeners();
  }

  void _updateVisibleRange() {
    if (_itemHeight <= 0 || _viewportHeight <= 0) return;
    _firstVisibleIndex = (_scrollOffset / _itemHeight).floor() - _overscanCount;
    _firstVisibleIndex = _firstVisibleIndex.clamp(0, _itemCount - 1);
    _lastVisibleIndex = ((_scrollOffset + _viewportHeight) / _itemHeight).ceil() + _overscanCount;
    _lastVisibleIndex = _lastVisibleIndex.clamp(0, _itemCount - 1);
  }

  int get visibleStartIndex => _firstVisibleIndex;
  int get visibleEndIndex => _lastVisibleIndex;
  double get totalContentHeight => _contentHeight;

  double getItemOffset(int index) {
    return index * _itemHeight;
  }

  void scrollToIndex(int index) {
    final offset = (index * _itemHeight).clamp(0.0, (_contentHeight - _viewportHeight).clamp(0.0, double.infinity));
    updateScrollOffset(offset);
  }

  void jumpToIndex(int index) {
    scrollToIndex(index);
  }
}

class VirtualScrollView extends StatefulWidget {
  final VirtualScrollController controller;
  final int itemCount;
  final double itemHeight;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final Widget? placeholder;

  const VirtualScrollView({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemHeight,
    required this.itemBuilder,
    this.placeholder,
  });

  @override
  State<VirtualScrollView> createState() => _VirtualScrollViewState();
}

class _VirtualScrollViewState extends State<VirtualScrollView> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    widget.controller.configure(
      itemCount: widget.itemCount,
      itemHeight: widget.itemHeight,
    );
  }

  @override
  void didUpdateWidget(VirtualScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount || oldWidget.itemHeight != widget.itemHeight) {
      widget.controller.configure(
        itemCount: widget.itemCount,
        itemHeight: widget.itemHeight,
      );
    }
  }

  void _onScroll() {
    widget.controller.updateScrollOffset(_scrollController.offset);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        widget.controller.updateViewportHeight(constraints.maxHeight);
        return SingleChildScrollView(
          controller: _scrollController,
          child: SizedBox(
            height: widget.controller.totalContentHeight,
            child: Stack(
              children: [
                for (int i = widget.controller.visibleStartIndex;
                    i <= widget.controller.visibleEndIndex;
                    i++)
                  Positioned(
                    top: widget.controller.getItemOffset(i),
                    left: 0,
                    right: 0,
                    height: widget.itemHeight,
                    child: widget.itemBuilder(context, i),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
