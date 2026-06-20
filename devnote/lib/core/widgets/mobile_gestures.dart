import 'package:flutter/material.dart';

/// 移动端手势优化工具
class MobileGestures {
  /// 最小滑动距离
  static const double minSwipeDistance = 50.0;

  /// 最大滑动时间
  static const Duration maxSwipeDuration = Duration(milliseconds: 500);

  /// 最小滑动速度
  static const double minSwipeVelocity = 300.0;

  /// 检测左滑手势
  static bool isSwipeLeft(DragEndDetails details) {
    return details.primaryVelocity != null &&
        details.primaryVelocity! < -minSwipeVelocity;
  }

  /// 检测右滑手势
  static bool isSwipeRight(DragEndDetails details) {
    return details.primaryVelocity != null &&
        details.primaryVelocity! > minSwipeVelocity;
  }

  /// 检测上滑手势
  static bool isSwipeUp(DragEndDetails details) {
    return details.primaryVelocity != null &&
        details.primaryVelocity! < -minSwipeVelocity;
  }

  /// 检测下滑手势
  static bool isSwipeDown(DragEndDetails details) {
    return details.primaryVelocity != null &&
        details.primaryVelocity! > minSwipeVelocity;
  }
}

/// 双击检测器
class DoubleTapDetector {
  final Duration timeout;
  final VoidCallback onDoubleTap;
  DateTime? _lastTap;

  DoubleTapDetector({
    this.timeout = const Duration(milliseconds: 300),
    required this.onDoubleTap,
  });

  void handleTap() {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < timeout) {
      onDoubleTap();
      _lastTap = null;
    } else {
      _lastTap = now;
    }
  }

  void reset() {
    _lastTap = null;
  }
}

/// 长按检测器
class LongPressDetector {
  final Duration minPressDuration;
  final VoidCallback onLongPress;

  LongPressDetector({
    this.minPressDuration = const Duration(milliseconds: 500),
    required this.onLongPress,
  });
}

/// 移动端友好的 FAB（浮动操作按钮）
class MobileFab extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String? label;
  final bool extended;

  const MobileFab({
    super.key,
    required this.onPressed,
    required this.icon,
    this.label,
    this.extended = false,
  });

  @override
  Widget build(BuildContext context) {
    if (extended && label != null) {
      return FloatingActionButton.extended(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label!),
      );
    }
    return FloatingActionButton(
      onPressed: onPressed,
      child: Icon(icon),
    );
  }
}
