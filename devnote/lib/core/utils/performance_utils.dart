import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 性能优化工具
class PerformanceUtils {
  /// 延迟执行（避免阻塞 UI 线程）
  static void runAfterFrame(VoidCallback callback) {
    SchedulerBinding.instance.addPostFrameCallback((_) => callback());
  }

  /// 防抖函数
  static VoidCallback debounce(VoidCallback callback, Duration delay) {
    DateTime? lastRun;
    return () {
      final now = DateTime.now();
      if (lastRun == null || now.difference(lastRun!) > delay) {
        lastRun = now;
        callback();
      }
    };
  }

  /// 节流函数
  static VoidCallback throttle(VoidCallback callback, Duration interval) {
    DateTime? lastRun;
    return () {
      final now = DateTime.now();
      if (lastRun == null || now.difference(lastRun!) >= interval) {
        lastRun = now;
        callback();
      }
    };
  }

  /// 检查是否为移动设备
  static bool isMobile(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width < 600;
  }

  /// 检查是否为平板
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 1200;
  }

  /// 检查是否为桌面
  static bool isDesktop(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 1200;
  }

  /// 获取网格列数（根据屏幕宽度自适应）
  static int getGridColumns(BuildContext context, {double itemWidth = 200}) {
    final screenWidth = MediaQuery.of(context).size.width;
    return (screenWidth / itemWidth).floor().clamp(1, 6);
  }
}

/// 缓存 Widget 构建结果
class CachedWidgetBuilder<T> extends StatefulWidget {
  final T data;
  final Widget Function(BuildContext context, T data) builder;
  final bool Function(T oldData, T newData)? shouldRebuild;

  const CachedWidgetBuilder({
    super.key,
    required this.data,
    required this.builder,
    this.shouldRebuild,
  });

  @override
  State<CachedWidgetBuilder<T>> createState() => _CachedWidgetBuilderState<T>();
}

class _CachedWidgetBuilderState<T> extends State<CachedWidgetBuilder<T>> {
  Widget? _cachedWidget;
  T? _cachedData;

  @override
  Widget build(BuildContext context) {
    final shouldRebuild = widget.shouldRebuild != null
        ? widget.shouldRebuild!(_cachedData ?? widget.data, widget.data)
        : _cachedData != widget.data;

    if (shouldRebuild || _cachedWidget == null) {
      _cachedWidget = widget.builder(context, widget.data);
      _cachedData = widget.data;
    }
    return _cachedWidget!;
  }
}
