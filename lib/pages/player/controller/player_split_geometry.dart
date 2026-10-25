/// 播放器分屏面板的几何计算。
///
/// 纯函数，不依赖 widget 树与全局状态，便于单测；契约见
/// `docs/player-split-panel-plan.md` §1.2。
///
/// 为什么单独一个文件：v1 把 clamp 常数散在页面里写了两遍且互不一致
/// （拖动用 `280 / W-420`、自动档用 `320 / 420`），这里收敛成唯一事实源。
///
/// **单位说明（重要）**：两个方向的持久化单位不同，所以这里**不提供**
/// 含糊的 `resolveExtent(axis, ratio)`——横屏用 [resolvePanelWidth]（参数是
/// 像素宽度），竖屏用 [resolvePanelHeight]（参数是容器高度占比）。调用方本来
/// 就要按轴向分支（Row / Column），单位因此始终显式。
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 分屏轴向。
enum SplitAxis {
  /// 横屏：左右切分，面板在右；尺寸单位是像素宽度。
  horizontal,

  /// 竖屏：上下切分，面板在下；尺寸单位是像素高度。
  vertical,
}

/// 某个方向上尺寸的合法区间（像素，含端点）。
@immutable
class SplitPanelRange {
  const SplitPanelRange(this.min, this.max);

  final double min;
  final double max;

  /// 可用空间太小时区间退化成一点（面板占满可用空间）。
  bool get isDegenerate => max <= min;

  /// 把 [value] 收进本区间。
  double clamp(double value) => clampDouble(value, min, max);

  @override
  String toString() => 'SplitPanelRange($min, $max)';

  @override
  bool operator ==(Object other) =>
      other is SplitPanelRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}

/// 把 [value] 收进 `[lowerLimit, upperLimit]`。
///
/// 不用 `num.clamp`：它返回 `num`，在需要 `double` 的位置要额外转换。
double clampDouble(double value, double lowerLimit, double upperLimit) =>
    math.min(math.max(value, lowerLimit), upperLimit);

/// 分屏契约里的全部尺寸常数（唯一事实源，禁止在别处重写）。
abstract final class SplitPanelMetrics {
  /// 横屏面板宽度下限（像素）。
  static const double landscapePanelMin = 280;

  /// 横屏面板宽度上限（像素）。
  static const double landscapePanelMax = 640;

  /// 横屏时视频区期望保底宽度。
  static const double landscapeVideoMinPreferred = 420;

  /// 窗口过窄时的视频区保底宽度（第一档退化）。
  static const double landscapeVideoMinNarrow = 240;

  /// 窗口极窄时的视频区最小宽度（第二档退化，之后面板不再让位）。
  static const double landscapeVideoMinFloor = 160;

  /// 横屏"自动档"（记忆值 0）的宽度范围。
  static const double autoMin = 320;
  static const double autoMax = 420;

  /// 横屏"自动档"取可用宽度的比例。
  static const double landscapeAutoFraction = 1 / 3;

  /// 竖屏面板高度占比范围。
  static const double portraitMinFraction = 0.30;
  static const double portraitMaxFraction = 0.70;

  /// 竖屏面板高度默认占比。
  static const double portraitDefaultFraction = 0.45;

  /// 面板开合动画时长。
  static const Duration openCloseDuration = Duration(milliseconds: 360);

  /// 分界线可见线宽 / 悬停拖动时的加粗线宽。
  static const double dividerThickness = 1;
  static const double dividerActiveThickness = 3;

  /// 分界线热区宽度：桌面 / 触摸（按输入类型取）。
  static const double dividerHitSizePointer = 8;
  static const double dividerHitSizeTouch = 12;

  /// 拖动比例的落盘防抖。
  static const Duration ratioPersistDebounce = Duration(milliseconds: 300);
}

/// 容器接近方形时按横屏处理（`width >= height`）。
SplitAxis splitAxisFor(Size size) =>
    size.width >= size.height ? SplitAxis.horizontal : SplitAxis.vertical;

// ============================ 横屏：面板宽度 ============================

/// 横屏面板宽度的合法区间：`280 ~ min(640, 可用宽 − 视频区保底)`。
///
/// 窗口过窄时视频区保底从 420 依次退化到 240、160，避免区间为空导致面板
/// 挤掉整个视频区。
SplitPanelRange panelWidthRange(double availableWidth) {
  var videoMin = SplitPanelMetrics.landscapeVideoMinPreferred;
  if (availableWidth - SplitPanelMetrics.landscapePanelMin < videoMin) {
    videoMin = SplitPanelMetrics.landscapeVideoMinNarrow;
  }
  if (availableWidth - SplitPanelMetrics.landscapePanelMin < videoMin) {
    videoMin = SplitPanelMetrics.landscapeVideoMinFloor;
  }
  final max = math.min(
    SplitPanelMetrics.landscapePanelMax,
    math.max(0.0, availableWidth - videoMin),
  );
  // 退化时 min 跟着 max 走，保证区间非空。
  final min = math.min(SplitPanelMetrics.landscapePanelMin, max);
  return SplitPanelRange(min, max);
}

/// 横屏默认面板宽度（"自动档"）：`clamp(可用宽 / 3, 320, 420)`，再收进区间。
double defaultPanelWidth(double availableWidth) {
  return panelWidthRange(availableWidth).clamp(
    clampDouble(
      availableWidth * SplitPanelMetrics.landscapeAutoFraction,
      SplitPanelMetrics.autoMin,
      SplitPanelMetrics.autoMax,
    ),
  );
}

/// 横屏：记忆的 [storedWidth]（像素；`<= 0` 表示自动档）→ 实际面板宽度。
double resolvePanelWidth({
  required double availableWidth,
  required double storedWidth,
}) {
  if (storedWidth <= 0) return defaultPanelWidth(availableWidth);
  return panelWidthRange(availableWidth).clamp(storedWidth);
}

/// 横屏：窗口变化后记忆宽度是否已越界（越界需落盘修正，否则下次拖动
/// 会从旧的大值起跳）。
bool panelWidthOutOfRange({
  required double availableWidth,
  required double storedWidth,
}) {
  // 自动档永远合法。
  if (storedWidth <= 0) return false;
  final range = panelWidthRange(availableWidth);
  return storedWidth < range.min || storedWidth > range.max;
}

// ============================ 竖屏：面板高度 ============================

/// 竖屏面板高度的合法区间（像素）：`可用高 × 30% ~ 可用高 × 70%`。
SplitPanelRange panelHeightRange(double availableHeight) {
  return SplitPanelRange(
    availableHeight * SplitPanelMetrics.portraitMinFraction,
    availableHeight * SplitPanelMetrics.portraitMaxFraction,
  );
}

/// 竖屏默认面板高度：`可用高 × 45%`，再收进区间。
double defaultPanelHeight(double availableHeight) {
  return panelHeightRange(availableHeight).clamp(
    availableHeight * SplitPanelMetrics.portraitDefaultFraction,
  );
}

/// 竖屏：记忆的 [storedFraction]（容器高度占比，如 `0.45`；`<= 0` 表示用默认）
/// → 实际面板高度（像素）。
double resolvePanelHeight({
  required double availableHeight,
  required double storedFraction,
}) {
  if (storedFraction <= 0) return defaultPanelHeight(availableHeight);
  return panelHeightRange(availableHeight).clamp(
    availableHeight * storedFraction,
  );
}

/// 竖屏：窗口变化后记忆占比是否已越界。
bool panelHeightFractionOutOfRange({
  required double availableHeight,
  required double storedFraction,
}) {
  if (storedFraction <= 0) return false;
  return storedFraction < SplitPanelMetrics.portraitMinFraction ||
      storedFraction > SplitPanelMetrics.portraitMaxFraction;
}
