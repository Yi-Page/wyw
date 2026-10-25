import 'package:flutter/material.dart';

/// 胶囊指示器页签条（可滚动 + 胶囊选中底 + 计数语义标签）。
///
/// 收藏页与播放器分屏面板**共用同一份样式**。
/// v1 曾把收藏页这段手抄进面板，并让数值悄悄漂移（圆角 20 vs 24、页签高
/// 40 vs 48、最小宽 56 vs 64、水平内边距 14 vs 16），还丢掉了 `Semantics`
/// 与 `PageStorageKey`。所以"照某页同款"必须落到**代码共用**，禁止再抄常量。
///
/// 需要"铺满整行、各段等宽"的两三选一切换时**不要**用这个，用
/// `bean/widget/connected_tabs.dart` 的 `ConnectedTabs`（M3 connected-button
/// 组，Kazumi 弹幕设置弹窗用的就是它）。
class CapsuleTabStrip extends StatelessWidget {
  const CapsuleTabStrip({
    super.key,
    required this.controller,
    required this.tabs,
    this.tabBarKey,
  });

  final TabController controller;

  /// 页签列表，通常用 [CapsuleTab] 构造。
  final List<Widget> tabs;

  /// 透传给内部 `TabBar` 的 key（收藏页用它做 `PageStorageKey`
  /// 以保留页签条的滚动位置）。
  final Key? tabBarKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return TabBar(
      key: tabBarKey,
      controller: controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      dividerHeight: 0,
      indicatorSize: TabBarIndicatorSize.tab,
      indicatorPadding: const EdgeInsets.symmetric(horizontal: 2),
      indicator: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(pillRadius),
      ),
      indicatorAnimation: TabIndicatorAnimation.elastic,
      labelColor: colors.onPrimaryContainer,
      unselectedLabelColor: colors.onSurfaceVariant,
      labelStyle:
          theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelStyle:
          theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      splashBorderRadius: BorderRadius.circular(pillRadius),
      tabs: tabs,
    );
  }
}

/// 胶囊页签条里的单个页签：统一高度 / 最小宽度 / 水平内边距。
class CapsuleTab extends StatelessWidget {
  const CapsuleTab({
    super.key,
    required this.label,
    this.semanticsLabel,
    this.minWidth = defaultMinWidth,
  });

  final String label;

  /// 读屏标签；默认用 [label]。需要带上计数等附加信息时显式传入。
  final String? semanticsLabel;

  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: tabHeight,
      child: Semantics(
        label: semanticsLabel ?? label,
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Text(label, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}

/// 胶囊圆角（选中底与 splash 一致）。
const double pillRadius = 24;

/// 页签高度。
const double tabHeight = 48;

/// 页签最小宽度。
const double defaultMinWidth = 64;

/// 页签水平内边距。
const double horizontalPadding = 16;
