// 协作者光标叠加 Widget
//
// 借鉴项目：
// - **Yjs y-prosemirror / y-monaco** ([GitHub](https://github.com/yjs)):
//   远程协作者光标叠加层，每个协作者用不同颜色 + 名称标签。
// - **Liveblocks** ([官网](https://liveblocks.io/)): presence 协议下的
//   光标 / 选区高亮渲染。
//
// 设计要点：
// 1. 接收 List<PresenceState>（来自 RealtimeCollabBloc 的 Connected 状态）
// 2. 通过 blockId 匹配当前编辑器中的 block，计算光标在 block 内的偏移位置
// 3. 每个协作者用基于 userId 哈希生成的稳定颜色
// 4. 光标位置用竖线 + 名称标签，选区用半透明高亮
// 5. 通过 Stack + Positioned 叠加在编辑器之上，不干扰本地编辑

import 'package:flutter/material.dart';

import 'package:devnote/features/sync/realtime/realtime_collab_service.dart';

/// 协作者光标叠加 Widget
///
/// 用法：将本 Widget 作为 Stack 的顶层子 Widget，传入当前在线协作者列表
/// 与 block 位置映射（blockId → 该 block 在编辑器视口中的 Rect）。
///
/// ```dart
/// Stack(
///   children: [
///     editorContent,
///     CollabCursorOverlay(
///       presences: state.presences,
///       blockRects: blockRects,
///     ),
///   ],
/// )
/// ```
class CollabCursorOverlay extends StatelessWidget {
  const CollabCursorOverlay({
    super.key,
    required this.presences,
    required this.blockRects,
    this.labelStyle,
  });

  /// 当前在线协作者列表（不含自己）
  final List<PresenceState> presences;

  /// block 位置映射：blockId → 该 block 在 Stack 坐标系中的 Rect
  ///
  /// 由编辑器通过 GlobalKey 测量后提供。若某 block 未测量（不在视口），
  /// 对应协作者的光标不渲染。
  final Map<String, Rect> blockRects;

  /// 名称标签文字样式（可选）
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    // 过滤出有光标且对应 block 在视口内的协作者
    final visibleCursors = <_CollabCursor>[];
    for (final presence in presences) {
      if (presence.cursor == null || presence.offset == null) continue;
      final rect = blockRects[presence.cursor!];
      if (rect == null) continue;
      visibleCursors.add(_CollabCursor(presence: presence, blockRect: rect));
    }

    return IgnorePointer(
      // 叠加层不拦截手势，确保本地编辑正常
      child: Stack(
        clipBehavior: Clip.none,
        children: visibleCursors.map((c) => _buildCursor(c)).toList(),
      ),
    );
  }

  /// 构建单个协作者的光标 + 选区 + 名称标签
  Widget _buildCursor(_CollabCursor cursor) {
    final presence = cursor.presence;
    final rect = cursor.blockRect;
    final color = Color(presence.color);

    // 简化定位：光标位于 block 左侧 + offset * 估算字符宽度
    // 实际生产中应由编辑器提供精确的字符坐标映射
    const charWidth = 7.0;
    const lineHeight = 20.0;
    final cursorX = rect.left + (presence.offset ?? 0) * charWidth;
    final cursorY = rect.top;

    return Positioned(
      left: cursorX,
      top: cursorY,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 名称标签（位于光标上方）
          if (presence.name.isNotEmpty)
            Transform.translate(
              offset: const Offset(0, -16),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(3),
                      topRight: Radius.circular(3),
                      bottomRight: Radius.circular(3),
                    ),
                  ),
                  child: Text(
                    presence.name,
                    style: labelStyle ??
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ),
            ),
          // 光标竖线
          Container(
            width: 2,
            height: lineHeight,
            color: color,
          ),
          // 选区高亮（length > 0 时显示）
          if (presence.length > 0)
            Transform.translate(
              offset: const Offset(2, -lineHeight),
              child: Container(
                width: presence.length * charWidth,
                height: lineHeight,
                color: color.withOpacity(0.25),
              ),
            ),
        ],
      ),
    );
  }
}

/// 内部辅助类：协作者光标 + 对应 block 的 Rect
class _CollabCursor {
  final PresenceState presence;
  final Rect blockRect;

  const _CollabCursor({required this.presence, required this.blockRect});
}

/// 协作者颜色生成工具
///
/// 借鉴 Yjs y-protocols/awareness 的颜色分配策略：对 userId 哈希后映射到
/// 色环，保证同一用户在不同设备上颜色一致。供外部 Widget 复用。
class CollabColor {
  CollabColor._();

  /// 基于 userId 生成稳定的 ARGB 颜色整数
  static int forUserId(String userId) {
    var hash = 0;
    for (final c in userId.codeUnits) {
      hash = (hash * 31 + c) & 0xFFFFFFFF;
    }
    final hue = hash % 360;
    return _hslToColor(hue, 0.65, 0.55);
  }

  /// HSL → ARGB 整数（与 RealtimeCollabService._hslToColor 一致）
  static int _hslToColor(num h, num s, num l) {
    final c = (1 - (2 * l - 1).abs()) * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = l - c / 2;
    num r, g, b;
    if (h < 60) {
      r = c;
      g = x;
      b = 0;
    } else if (h < 120) {
      r = x;
      g = c;
      b = 0;
    } else if (h < 180) {
      r = 0;
      g = c;
      b = x;
    } else if (h < 240) {
      r = 0;
      g = x;
      b = c;
    } else if (h < 300) {
      r = x;
      g = 0;
      b = c;
    } else {
      r = c;
      g = 0;
      b = x;
    }
    final ri = ((r + m) * 255).round();
    final gi = ((g + m) * 255).round();
    final bi = ((b + m) * 255).round();
    return (0xFF << 24) | (ri << 16) | (gi << 8) | bi;
  }
}
