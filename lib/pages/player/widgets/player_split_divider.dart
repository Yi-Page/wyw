import 'package:flutter/material.dart';
import 'package:wyw/pages/player/controller/player_split_geometry.dart';

/// 分界线**可见的那条线**：交给 `multi_split_view` 的 `dividerBuilder` 渲染。
///
/// 它不处理任何手势——拖动、双击复位、鼠标光标都由 `multi_split_view` 自己负责
/// （这正是换成熟组件的原因：热区/手势/坐标换算不再由我们手搓）。
///
/// 布局槽位宽度 = `MultiSplitViewThemeData.dividerThickness`（我们传 1），
/// 也就是**这条线本身**：视频区与面板区之间没有额外空隙，线正好落在两者交界上。
/// 悬停/拖动时线加粗到 3px——用 `OverflowBox` 越过 1px 槽位绘制，不挤开相邻区域。
///
/// 加粗用 `TweenAnimationBuilder<double>` 补间**一个 double**，而不是
/// `AnimatedContainer`：后者会补间 `BoxConstraints`，横竖屏切换时 width/height
/// 在「有限 ↔ 无界」之间插值会触发框架断言
/// （`Cannot interpolate between finite constraints and unbounded constraints`）。
class PlayerSplitDividerLine extends StatelessWidget {
  const PlayerSplitDividerLine({
    super.key,
    required this.axis,
    required this.active,
  });

  /// 线的方向：`Axis.vertical` = 竖线（左右分屏）。
  final Axis axis;

  /// 悬停或拖动中（加粗 + 主题色）。
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isVerticalLine = axis == Axis.vertical;
    final target = active
        ? SplitPanelMetrics.dividerActiveThickness
        : SplitPanelMetrics.dividerThickness;
    final color = active ? colors.primary : colors.outlineVariant;
    return TweenAnimationBuilder<double>(
      // begin == end：首帧不播放动画；之后 end 变化时从当前值补间过去。
      tween: Tween<double>(begin: target, end: target),
      duration: const Duration(milliseconds: 150),
      builder: (context, thickness, child) {
        return SizedBox(
          width: isVerticalLine ? SplitPanelMetrics.dividerThickness : null,
          height: isVerticalLine ? null : SplitPanelMetrics.dividerThickness,
          child: OverflowBox(
            maxWidth: isVerticalLine ? thickness : null,
            maxHeight: isVerticalLine ? null : thickness,
            child: Center(
              child: SizedBox(
                width: isVerticalLine ? thickness : null,
                height: isVerticalLine ? null : thickness,
                child: ColoredBox(color: color),
              ),
            ),
          ),
        );
      },
    );
  }
}
