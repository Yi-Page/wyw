import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/pages/player/controller/player_split_geometry.dart';
import 'package:wyw/pages/player/widgets/player_split_divider.dart';
import 'package:wyw/pages/player/widgets/player_split_layout.dart';

/// 挂载测试宿主并**把测试窗口设成宿主尺寸**。
///
/// 必须显式设 surface size：flutter_test 默认窗口 800×600，宿主里的
/// `SizedBox(1200)` 会被约束到 800，几何断言会全部错位。
Future<_HarnessState> _pumpHarness(
  WidgetTester tester,
  _Harness harness,
) async {
  await tester.binding.setSurfaceSize(harness.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(harness);
  await tester.pumpAndSettle();
  final key = harness.key! as GlobalKey<_HarnessState>;
  return key.currentState!;
}

_Harness _harness({
  required bool visible,
  Size size = const Size(1200, 675),
  double landscapeWidth = 0,
  double portraitFraction = 0,
  bool disableAnimations = false,
}) {
  return _Harness(
    key: GlobalKey<_HarnessState>(),
    visible: visible,
    size: size,
    landscapeWidth: landscapeWidth,
    portraitFraction: portraitFraction,
    disableAnimations: disableAnimations,
  );
}

/// 面板当前可见尺寸 = 交界线的外沿到容器末端。
///
/// 布局槽位就是那条 1px 的线（`dividerThickness`），面板紧贴它的外侧，
/// 因此用线的 `right` / `bottom` 作为面板起点。
double _panelExtent(
  WidgetTester tester,
  double total, {
  required bool horizontal,
}) {
  final line = tester.getRect(find.byType(PlayerSplitDividerLine));
  return horizontal ? total - line.right : total - line.bottom;
}

/// 拖动分界线：多步移动 + 每步 pump。
///
/// 拖动本身由 `multi_split_view` 处理（这正是换成熟组件的目的），这里只负责
/// 把指针移动喂进去；断言只依赖「方向 / 单位 / 饱和值」，不依赖精确像素。
Future<void> _dragDivider(WidgetTester tester, Offset total) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(PlayerSplitDividerLine)),
  );
  await tester.pump();
  const steps = 10;
  final step = Offset(total.dx / steps, total.dy / steps);
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(step);
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('PlayerSplitLayout 可见性与轴向', () {
    testWidgets('收起时不显示分界线，但面板仍挂载（关闭再打开不丢状态）', (tester) async {
      await _pumpHarness(tester, _harness(visible: false));

      expect(find.byType(PlayerSplitDividerLine), findsNothing);
      // 面板子树仍在树里：v1 一关就整棵销毁，页签状态全丢。
      expect(find.byKey(_Harness.panelKey), findsOneWidget);
      // 视频区占满容器（收起时线的槽位宽度为 0）。
      expect(tester.getSize(find.byKey(_Harness.videoKey)).width, 1200);
      expect(tester.takeException(), isNull);
    });

    testWidgets('展开时横屏左右切分：视频 + 线 + 面板 = 容器宽（无空隙）', (tester) async {
      await _pumpHarness(tester, _harness(visible: true));

      final line = tester.getRect(find.byType(PlayerSplitDividerLine));
      // 槽位就是那条线本身：1px，不占额外布局宽度。
      expect(line.width, SplitPanelMetrics.dividerThickness);
      // 自动档：容器宽 1200 → 1200/3 = 400。
      expect(_panelExtent(tester, 1200, horizontal: true), closeTo(400, 0.5));
      // 回归：曾经用 8px 独立槽位 + 透明底 → 视频与面板之间出现黑色分隔带。
      final videoWidth = tester.getSize(find.byKey(_Harness.videoKey)).width;
      final panelWidth = tester.getSize(find.byKey(_Harness.panelKey)).width;
      expect(
        videoWidth + line.width + panelWidth,
        closeTo(1200, 0.5),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('竖屏上下切分：面板高为容器高的 45%', (tester) async {
      await _pumpHarness(
        tester,
        _harness(visible: true, size: const Size(675, 1200)),
      );

      final line = tester.getRect(find.byType(PlayerSplitDividerLine));
      expect(line.height, SplitPanelMetrics.dividerThickness);
      expect(
        _panelExtent(tester, 1200, horizontal: false),
        closeTo(1200 * 0.45, 0.5),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('PlayerSplitLayout 记忆值夹取', () {
    testWidgets('横屏记忆值超出上限时夹到 min(640, 容器宽-420)', (tester) async {
      await _pumpHarness(
        tester,
        _harness(
          visible: true,
          size: const Size(900, 600),
          landscapeWidth: 700,
        ),
      );

      // 契约：上限 = min(640, 900-420) = 480。
      expect(_panelExtent(tester, 900, horizontal: true), closeTo(480, 0.5));
    });

    testWidgets('横屏记忆值低于下限时夹到 280', (tester) async {
      await _pumpHarness(
        tester,
        _harness(
          visible: true,
          size: const Size(900, 600),
          landscapeWidth: 100,
        ),
      );

      expect(_panelExtent(tester, 900, horizontal: true), closeTo(280, 0.5));
    });

    testWidgets('竖屏记忆占比超出 70% 时夹到 70%', (tester) async {
      await _pumpHarness(
        tester,
        _harness(
          visible: true,
          size: const Size(675, 1000),
          portraitFraction: 0.95,
        ),
      );

      expect(
        _panelExtent(tester, 1000, horizontal: false),
        closeTo(1000 * 0.70, 0.5),
      );
    });
  });

  group('PlayerSplitLayout 拖动', () {
    testWidgets('横屏向左拖 → 面板变大，且回调值是像素', (tester) async {
      final state = await _pumpHarness(tester, _harness(visible: true));

      await _dragDivider(tester, const Offset(-50, 0));

      expect(state.changes, isNotEmpty);
      final last = state.changes.last;
      expect(last.axis, SplitAxis.horizontal);
      // 方向：面板变大（自动档起始 400）。
      expect(last.stored, greaterThan(400));
      // 单位：横屏存像素，不会是 0~1 的占比。
      expect(last.stored, greaterThan(1));
      expect(last.stored, lessThanOrEqualTo(640));
    });

    testWidgets('拖动不丢增量：上报值累计等于总位移（跟手）', (tester) async {
      final state = await _pumpHarness(tester, _harness(visible: true));

      await _dragDivider(tester, const Offset(-100, 0));

      // 起始 400，向左共 100 → 500（组件内部按整数坐标修正，留 5px 容差）。
      expect(state.changes.last.stored, closeTo(500, 5));
      expect(
        _panelExtent(tester, 1200, horizontal: true),
        closeTo(state.changes.last.stored, 1),
      );
    });

    testWidgets('横屏向右拖过头时停在 280（面板下限）', (tester) async {
      final state = await _pumpHarness(
        tester,
        _harness(visible: true, size: const Size(900, 600)),
      );

      await _dragDivider(tester, const Offset(600, 0));

      expect(state.changes.last.stored, closeTo(280, 1));
    });

    testWidgets('竖屏向上拖 → 面板变大，且回调值是占比', (tester) async {
      final state = await _pumpHarness(
        tester,
        _harness(visible: true, size: const Size(675, 1000)),
      );

      await _dragDivider(tester, const Offset(0, -90));

      final last = state.changes.last;
      expect(last.axis, SplitAxis.vertical);
      // 方向：面板变大（起始 45%）。
      expect(last.stored, greaterThan(0.45));
      // 单位：竖屏存占比，不会是像素。
      expect(last.stored, lessThan(1));
    });

    testWidgets('竖屏向上拖过头时停在 70%', (tester) async {
      final state = await _pumpHarness(
        tester,
        _harness(visible: true, size: const Size(675, 1000)),
      );

      await _dragDivider(tester, const Offset(0, -2000));

      expect(state.changes.last.stored, closeTo(0.70, 0.002));
    });
  });

  group('PlayerSplitLayout 双击复位', () {
    testWidgets('双击分界线 → 回调复位该轴向', (tester) async {
      final state = await _pumpHarness(
        tester,
        _harness(visible: true, landscapeWidth: 500),
      );

      await tester.tap(find.byType(PlayerSplitDividerLine));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(PlayerSplitDividerLine));
      await tester.pumpAndSettle();

      expect(state.resets, [SplitAxis.horizontal]);
      // 复位后回到自动档。
      expect(_panelExtent(tester, 1200, horizontal: true), closeTo(400, 0.5));
    });
  });

  group('PlayerSplitLayout 动画开关', () {
    testWidgets('disableAnimations 时开合瞬时完成', (tester) async {
      final state = await _pumpHarness(
        tester,
        _harness(visible: false, disableAnimations: true),
      );

      state.setVisible(true);
      // 只 pump 一帧，不 settle：动画时长应为 0。
      await tester.pump();
      await tester.pump();

      expect(find.byType(PlayerSplitDividerLine), findsOneWidget);
      expect(_panelExtent(tester, 1200, horizontal: true), closeTo(400, 0.5));
    });

    testWidgets('默认动画下开合是渐进的（一帧后尚未到位）', (tester) async {
      final state = await _pumpHarness(tester, _harness(visible: false));

      state.setVisible(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(
        _panelExtent(tester, 1200, horizontal: true),
        lessThan(400 - 1),
      );

      await tester.pumpAndSettle();
      expect(_panelExtent(tester, 1200, horizontal: true), closeTo(400, 0.5));
    });
  });

  group('PlayerSplitLayout 拖动时零动画', () {
    testWidgets('拖动时零动画：拖完立即到位', (tester) async {
      final state = await _pumpHarness(tester, _harness(visible: true));
      final before = _panelExtent(tester, 1200, horizontal: true);

      await _dragDivider(tester, const Offset(-40, 0));

      final after = _panelExtent(tester, 1200, horizontal: true);
      expect(after, greaterThan(before));
      expect(state.changes, isNotEmpty);
    });
  });

  group('PlayerSplitLayout 真机回归（运行时异常）', () {
    testWidgets('横竖屏切换不抛异常：线加粗时切轴向不再补间约束', (tester) async {
      final state = await _pumpHarness(tester, _harness(visible: true));

      // 真实路径：鼠标悬停到分界线上 → 线加粗（active）→ 再切横竖屏。
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(PlayerSplitDividerLine)));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(PlayerSplitDividerLine)).width,
        SplitPanelMetrics.dividerThickness,
      );

      // 切竖屏：容器形状变化 → 轴向翻转，线的宽高互换。
      const portrait = Size(675, 1200);
      await tester.binding.setSurfaceSize(portrait);
      state.setSize(portrait);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();

      // 曾在此抛：Cannot interpolate between finite constraints and unbounded
      // constraints（AnimatedContainer 补间 BoxConstraints）。
      expect(tester.takeException(), isNull);
      final line = tester.getRect(find.byType(PlayerSplitDividerLine));
      expect(line.height, SplitPanelMetrics.dividerThickness);
      expect(line.width, closeTo(675, 0.5));
    });

    testWidgets('开合动画期间面板按目标尺寸布局：只裁剪可见部分，不溢出', (tester) async {
      final state = await _pumpHarness(tester, _harness(visible: false));

      state.setVisible(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      // 可见区域还很窄……
      expect(_panelExtent(tester, 1200, horizontal: true), lessThan(399));
      // ……但面板内容已按目标尺寸（400）布局：否则页签条 Row 会溢出 39px。
      expect(
        tester.getSize(find.byKey(_Harness.panelKey)).width,
        closeTo(400, 0.5),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(_panelExtent(tester, 1200, horizontal: true), closeTo(400, 0.5));
    });
  });
}

/// 测试宿主：把布局壳的可变状态与回调记录暴露出来。
class _Harness extends StatefulWidget {
  const _Harness({
    required super.key,
    required this.visible,
    this.size = const Size(1200, 675),
    this.landscapeWidth = 0,
    this.portraitFraction = 0,
    this.disableAnimations = false,
  });

  static const Key videoKey = Key('video');
  static const Key panelKey = Key('panel');

  final bool visible;
  final Size size;
  final double landscapeWidth;
  final double portraitFraction;
  final bool disableAnimations;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late double landscapeWidth = widget.landscapeWidth;
  late double portraitFraction = widget.portraitFraction;
  late bool visible = widget.visible;

  final List<({SplitAxis axis, double stored})> changes = [];
  final List<SplitAxis> resets = [];

  /// 切换面板可见性（用来验证开合动画只在可见性变化时发生）。
  void setVisible(bool value) => setState(() => visible = value);

  /// 切换容器尺寸（模拟窗口缩放 / 横竖屏切换）。
  void setSize(Size value) => setState(() => size = value);

  late Size size = widget.size;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: size.width,
          height: size.height,
          child: PlayerSplitLayout(
            visible: visible,
            storedLandscapeWidth: landscapeWidth,
            storedPortraitFraction: portraitFraction,
            disableAnimations: widget.disableAnimations,
            onExtentChanged: (axis, stored) {
              changes.add((axis: axis, stored: stored));
              setState(() {
                if (axis == SplitAxis.horizontal) {
                  landscapeWidth = stored;
                } else {
                  portraitFraction = stored;
                }
              });
            },
            onExtentReset: (axis) {
              resets.add(axis);
              setState(() {
                if (axis == SplitAxis.horizontal) {
                  landscapeWidth = 0;
                } else {
                  portraitFraction = 0;
                }
              });
            },
            video: Container(key: _Harness.videoKey, color: Colors.black),
            panel: Container(key: _Harness.panelKey, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
