import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:multi_split_view/multi_split_view.dart';
import 'package:wyw/pages/player/controller/player_split_geometry.dart';
import 'package:wyw/pages/player/widgets/player_split_divider.dart';
import 'package:wyw/utils/device.dart';

/// 分屏布局壳：把播放器容器内部切成「视频区 + 面板区」。
///
/// **几何与拖动交给 `multi_split_view`**（成熟组件）：热区、手势、坐标换算、
/// 夹取、双击复位都由它负责；我们只保留本项目特有的契约：
/// - 轴向随容器形状（横屏左右 / 竖屏上下）；
/// - 面板尺寸用本项目 [player_split_geometry] 的纯函数算 clamp 与默认档
///   （`Area.min/max` 交给组件执行）；
/// - 开合 360ms 动画（`disableAnimations` 时瞬时）；
/// - 拖动结果回调给 `PlayerPanelController` 做持久化。
///
/// ### 可见的线 = 1px 的布局槽位本身
/// 布局槽位宽度就是 `dividerThickness`，我们传 **1px**：视频区与面板区之间
/// 没有额外空隙，线正好落在交界上；热区由 `dividerHandleBuffer` 向两侧扩展
/// （拖动/悬停/双击都由组件处理）。悬停或拖动时线加粗到 3px——由
/// [PlayerSplitDividerLine] 用 `OverflowBox` 越过 1px 槽位绘制，不挤开相邻区域。
///
/// ### 状态归属
/// 组件内部的 `Area` 是**实时几何**的唯一持有者（拖动时它直接改 `size`）；
/// 本壳在拖动回调里把结果上报给 `PlayerPanelController`（持久化 + 其它 UI 读）。
/// 反向：可见性/比例变化时由本壳把目标尺寸写回 `Area`。
class PlayerSplitLayout extends StatefulWidget {
  const PlayerSplitLayout({
    super.key,
    required this.visible,
    required this.storedLandscapeWidth,
    required this.storedPortraitFraction,
    required this.disableAnimations,
    required this.onExtentChanged,
    required this.onExtentReset,
    required this.video,
    required this.panel,
  });

  /// 面板是否展开。
  final bool visible;

  /// 横屏记忆宽度（像素；`0` = 未自定义）。
  final double storedLandscapeWidth;

  /// 竖屏记忆占比（`0` = 未自定义）。
  final double storedPortraitFraction;

  /// 关闭动画（无障碍/性能设置）。
  final bool disableAnimations;

  /// 拖动后回调新的比例；单位随轴向（横屏像素 / 竖屏占比）。
  final void Function(SplitAxis axis, double stored) onExtentChanged;

  /// 双击复位。
  final void Function(SplitAxis axis) onExtentReset;

  final Widget video;
  final Widget panel;

  @override
  State<PlayerSplitLayout> createState() => _PlayerSplitLayoutState();
}

class _PlayerSplitLayoutState extends State<PlayerSplitLayout>
    with SingleTickerProviderStateMixin {
  /// 面板区（像素 size）与视频区（flex 占满剩余）。
  ///
  /// `id` 稳定：组件用 `ValueKey(area.id)` 保住各自子树的状态，因此面板关闭
  /// 再打开时页签内的状态不丢（v1 一关就整棵销毁）。
  late final Area _panelArea =
      Area(size: 0, id: 'split-panel', data: 'panel');
  late final Area _videoArea =
      Area(flex: 1, id: 'split-video', data: 'video');
  late final MultiSplitViewController _controller =
      MultiSplitViewController(areas: [_videoArea, _panelArea]);

  /// 0 = 完全收起，1 = 完全展开。**只有开合走它**，拖动不经过它。
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: widget.disableAnimations
        ? Duration.zero
        : SplitPanelMetrics.openCloseDuration,
    value: widget.visible ? 1 : 0,
  );

  /// 最近一次 LayoutBuilder 实测的主轴长度与轴向。
  double _total = 0;
  SplitAxis _axis = SplitAxis.horizontal;
  bool _appliedOnce = false;

  /// 面板的**目标尺寸**（不含开合动画）：由持久化比例 + 容器实测尺寸算出。
  ///
  /// 面板内容始终按它布局（见 [_buildPanelArea]），开合动画只改变"可见多少"。
  double _extent = 0;

  /// 是否已排队一次延后应用（见 [_scheduleApply]）。
  bool _applyScheduled = false;

  @override
  void initState() {
    super.initState();
    _open.addListener(_applyExtent);
  }

  @override
  void didUpdateWidget(covariant PlayerSplitLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.disableAnimations && _open.duration != Duration.zero) {
      _open.duration = Duration.zero;
    }
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _open.forward();
      } else {
        _open.reverse();
      }
    } else if (widget.storedLandscapeWidth != oldWidget.storedLandscapeWidth ||
        widget.storedPortraitFraction != oldWidget.storedPortraitFraction) {
      // didUpdateWidget 本身处于 build 阶段，不能在这里写 Area（会 notify →
      // 组件 setState 被拒："cannot be marked as needing to build"）。
      _scheduleApply();
    }
  }

  /// 延后到 build 结束再改 `Area`。
  ///
  /// `Area.size` 会 `notifyListeners()` → `MultiSplitView` 内部 `setState`，因此在
  /// build / didUpdateWidget 里直接改会抛
  /// "This MultiSplitView widget cannot be marked as needing to build because the
  /// framework is already in the build phase"。
  void _scheduleApply() {
    if (_applyScheduled) {
      return;
    }
    _applyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyScheduled = false;
      if (mounted) {
        _applyExtent();
      }
    });
  }

  @override
  void dispose() {
    _open.removeListener(_applyExtent);
    _open.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 目标尺寸的纯计算（`_total`/`_axis`/持久化值 → 像素）。
  double _resolveExtent() {
    if (_total <= 0) {
      return 0;
    }
    return _axis == SplitAxis.horizontal
        ? resolvePanelWidth(
            availableWidth: _total,
            storedWidth: widget.storedLandscapeWidth,
          )
        : resolvePanelHeight(
            availableHeight: _total,
            storedFraction: widget.storedPortraitFraction,
          );
  }

  /// 把「开合进度 × 目标尺寸」写给面板区。
  ///
  /// **必须在 build 之外调用**：`Area.size` 会 `notifyListeners()`，在 build 里改
  /// 会触发 "setState() called during build"。
  void _applyExtent() {
    final extent = _resolveExtent();
    _extent = extent;
    if (_total <= 0) {
      return;
    }
    final range = _axis == SplitAxis.horizontal
        ? panelWidthRange(_total)
        : panelHeightRange(_total);
    final settledOpen = widget.visible && _open.value >= 1;
    // 动画期间与收起状态下放开下限：否则 0 尺寸会被 min 夹回去。
    final min = settledOpen ? range.min : 0.0;
    if (_panelArea.min != min) {
      _panelArea.min = min;
    }
    if (_panelArea.max != range.max) {
      _panelArea.max = range.max;
    }
    final target = extent * _open.value;
    if (_panelArea.size != target) {
      _panelArea.size = target;
    }
  }

  /// 拖动由组件执行，结果从面板区当前尺寸读回来上报（组件只给 index，不给增量）。
  void _reportDrag() {
    final size = _panelArea.size ?? 0;
    final isHorizontal = _axis == SplitAxis.horizontal;
    widget.onExtentChanged(
      _axis,
      isHorizontal ? size : size / math.max(1.0, _total),
    );
  }

  Widget _buildDivider(
    Axis dividerAxis,
    bool resizable,
    bool dragging,
    bool highlighted,
  ) {
    if (!widget.visible) {
      return const SizedBox.shrink();
    }
    return PlayerSplitDividerLine(
      axis: dividerAxis,
      active: dragging || highlighted,
    );
  }

  /// 面板区内容：**按目标尺寸布局 + 只裁剪可见部分**。
  ///
  /// 开合动画期间区域实际尺寸从 0 长到目标值。若把面板直接交给区域约束，面板会被
  /// 按 0.6px 这类尺寸布局 → 页签条 Row 溢出 39px、二级页 Column 溢出（真机上报过）。
  /// 这里用 `OverflowBox` 固定成目标尺寸、`ClipRect` 裁剪可见部分；顺带的好处是
  /// 面板内容在开合动画期间**完全不重排**。
  Widget _buildPanelArea(SplitAxis axis) {
    if (_extent <= 0) {
      return widget.panel;
    }
    final isHorizontal = axis == SplitAxis.horizontal;
    return ClipRect(
      child: OverflowBox(
        // 面板贴容器末端，展开时从末端"推出来"。
        alignment: isHorizontal
            ? Alignment.centerRight
            : Alignment.bottomCenter,
        minWidth: isHorizontal ? _extent : null,
        maxWidth: isHorizontal ? _extent : null,
        minHeight: isHorizontal ? null : _extent,
        maxHeight: isHorizontal ? null : _extent,
        child: widget.panel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hitSize = isDesktop()
        ? SplitPanelMetrics.dividerHitSizePointer
        : SplitPanelMetrics.dividerHitSizeTouch;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final axis = splitAxisFor(size);
        final total = axis == SplitAxis.horizontal ? size.width : size.height;
        final changed = axis != _axis || total != _total || !_appliedOnce;
        _axis = axis;
        _total = total;
        // 同一帧内先算出目标尺寸：面板内容本帧就按它布局（不 setState，纯赋值）。
        _extent = _resolveExtent();
        if (changed) {
          _appliedOnce = true;
          // 容器尺寸/轴向变化：build 结束后再改 Area（build 内改会 notify）。
          _scheduleApply();
        }
        final thickness =
            widget.visible ? SplitPanelMetrics.dividerThickness : 0.0;
        return MultiSplitViewTheme(
          data: MultiSplitViewThemeData(
            dividerThickness: thickness,
            // 热区向线两侧各扩一半，总热区 = 桌面 8 / 触摸 12。
            dividerHandleBuffer:
                widget.visible ? (hitSize - thickness) / 2 : 0,
          ),
          child: MultiSplitView(
            axis: axis == SplitAxis.horizontal
                ? Axis.horizontal
                : Axis.vertical,
            controller: _controller,
            // 收起时不可拖（也不显示热区/光标）。
            resizable: widget.visible,
            onDividerDragUpdate: (_) => _reportDrag(),
            onDividerDragEnd: (_) => _reportDrag(),
            onDividerDoubleTap: (_) => widget.onExtentReset(axis),
            dividerBuilder:
                (dividerAxis, index, resizable, dragging, highlighted, theme) =>
                    _buildDivider(dividerAxis, resizable, dragging, highlighted),
            builder: (context, area) => area.data == 'panel'
                ? _buildPanelArea(axis)
                : widget.video,
          ),
        );
      },
    );
  }
}
