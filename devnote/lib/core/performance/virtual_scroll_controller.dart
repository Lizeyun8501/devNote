/// 虚拟滚动控制器与虚拟滚动视图
///
/// ## 已替换的开源模块
/// - **scrollable_positioned_list** ([pub.dev](https://pub.dev/packages/scrollable_positioned_list)):
///   Google 官方维护的虚拟滚动列表，已替代本自研实现。
///   优势：支持 scrollToIndex/jumpToIndex、ItemScrollController、ItemPositionsListener，
///   性能经过大规模验证，无需手动管理可见范围。
///
/// ## 推荐替代（暂未替换）
/// - **graphview** ([pub.dev](https://pub.dev/packages/graphview)):
///   已在知识图谱模块中替代自研 CustomPaint 渲染方案。
///   本文件的虚拟滚动功能暂无更高优先级的替代需求，保留作为备用方案。
///
/// ## 本文件的保留原因
/// - VirtualScrollController 仍作为备用方案保留
/// - 在 scrollable_positioned_list 不可用的场景（如 Web 平台）可回退使用
///
/// ## 借鉴的开源项目
/// - **react-virtual** ([GitHub](https://github.com/TanStack/virtual)): overscan 机制
/// - **Flutter SliverList**: 滚动状态机
///
/// 虚拟滚动（Virtualization）是一种"按需渲染"技术：对于可能包含成千上万条目的列表，
/// 完整构建所有 Widget 会消耗大量内存并阻塞首屏渲染。本实现仅构建"可见区域 + 少量
/// overscan"内的条目，显著降低内存占用与重建成本。
///
/// ## 实现说明
/// - 假设每个 item 高度相同（fixed-size），通过 `itemHeight * index` 计算位置。
/// - 使用 `ChangeNotifier` 模式，UI 在 `notifyListeners()` 后可重新构建。
/// - 内部使用 `Stack` + `Positioned` 直接放置可见 item，从而跳过 `ListView` 自身的
///   布局开销。
/// - 当前实现为"定高版本"，如需支持变高 item，可参考 react-virtual 的 `measureElement` 机制扩展。
library;

import 'package:flutter/widgets.dart';

/// 虚拟滚动控制器
///
/// 借鉴 react-virtual 的 `useVirtualizer` 状态结构与 Flutter `ScrollController` 的
/// 通知机制；负责维护滚动偏移、视口高度与可见索引区间，并通知监听者重建。
///
/// **实现来源**:
/// - [react-virtual](https://github.com/TanStack/virtual) — 可见索引计算与 overscan
/// - [Flutter SliverList](https://api.flutter.dev/flutter/widgets/SliverList-class.html) — 滚动状态机
class VirtualScrollController extends ChangeNotifier {
  double _scrollOffset = 0.0;
  double _viewportHeight = 0.0;
  double _contentHeight = 0.0;
  double _itemHeight = 48.0;
  int _itemCount = 0;
  int _firstVisibleIndex = 0;
  int _lastVisibleIndex = 0;
  /// 借鉴 react-virtual 的 overscan 机制：在可见区域上下额外预渲染的 item 数量，
  /// 以避免快速滚动时出现"白边"。
  static const int _overscanCount = 5;

  /// 当前滚动偏移（像素）
  double get scrollOffset => _scrollOffset;
  /// 视口高度（像素）
  double get viewportHeight => _viewportHeight;
  /// 第一个可见 item 的索引
  int get firstVisibleIndex => _firstVisibleIndex;
  /// 最后一个可见 item 的索引
  int get lastVisibleIndex => _lastVisibleIndex;
  /// item 总数
  int get itemCount => _itemCount;

  /// 配置 item 数量与单 item 高度
  ///
  /// 借鉴 react-virtual `useVirtualizer({ count, estimateSize })` 的 API 形式。
  void configure({required int itemCount, required double itemHeight}) {
    _itemCount = itemCount;
    _itemHeight = itemHeight;
    _contentHeight = itemCount * itemHeight;
    _updateVisibleRange();
    notifyListeners();
  }

  /// 视口尺寸变化时调用（通常由 `LayoutBuilder` 触发）
  void updateViewportHeight(double height) {
    _viewportHeight = height;
    _updateVisibleRange();
    notifyListeners();
  }

  /// 滚动偏移变化时调用（通常由 `ScrollController` 触发）
  void updateScrollOffset(double offset) {
    _scrollOffset = offset.clamp(0.0, _contentHeight - _viewportHeight);
    _updateVisibleRange();
    notifyListeners();
  }

  /// 重新计算可见区间的起止索引（含 overscan）
  ///
  /// 借鉴 react-virtual 中"根据滚动偏移 + 视口大小 + overscan 计算起止索引"的算法。
  void _updateVisibleRange() {
    if (_itemHeight <= 0 || _viewportHeight <= 0) return;
    _firstVisibleIndex = (_scrollOffset / _itemHeight).floor() - _overscanCount;
    _firstVisibleIndex = _firstVisibleIndex.clamp(0, _itemCount - 1);
    _lastVisibleIndex = ((_scrollOffset + _viewportHeight) / _itemHeight).ceil() + _overscanCount;
    _lastVisibleIndex = _lastVisibleIndex.clamp(0, _itemCount - 1);
  }

  /// 第一个可见 item 的索引（含 overscan）
  int get visibleStartIndex => _firstVisibleIndex;
  /// 最后一个可见 item 的索引（含 overscan）
  int get visibleEndIndex => _lastVisibleIndex;
  /// 总内容高度
  double get totalContentHeight => _contentHeight;

  /// 计算指定 item 相对滚动容器的纵向偏移
  double getItemOffset(int index) {
    return index * _itemHeight;
  }

  /// 平滑滚动到指定索引
  ///
  /// 借鉴 react-virtual `virtualizer.scrollToIndex(index)` API。
  void scrollToIndex(int index) {
    final offset = (index * _itemHeight).clamp(0.0, (_contentHeight - _viewportHeight).clamp(0.0, double.infinity));
    updateScrollOffset(offset);
  }

  /// 立即跳转到指定索引（无动画）
  void jumpToIndex(int index) {
    scrollToIndex(index);
  }
}

/// 虚拟滚动视图
///
/// 借鉴 Flutter `SliverList` + `SliverFixedExtentList` 的思路：
/// - 使用 `Stack` + `Positioned` 将每个 item 精确摆放到正确位置；
/// - `LayoutBuilder` 监听视口尺寸变化；
/// - 内部 `ScrollController` 监听滚动事件并把状态同步给 `VirtualScrollController`。
///
/// **实现来源**:
/// - [react-virtual](https://github.com/TanStack/virtual) — overscan 与编程式滚动
/// - [Flutter SliverList](https://api.flutter.dev/flutter/widgets/SliverList-class.html) — 滚动状态机
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
