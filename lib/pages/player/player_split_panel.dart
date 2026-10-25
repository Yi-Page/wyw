import 'package:flutter/material.dart';
import 'package:wyw/pages/player/controller/player_panel_controller.dart';
import 'package:wyw/pages/player/split_tabs/player_split_tabs.dart';
import 'package:wyw/pages/player/split_tabs/split_tab_host.dart';
import 'package:wyw/pages/player/widgets/split_panel_scaffold.dart';

/// 分屏面板：把 [SplitPanelTab] / [SplitSubPage] 映射成外壳的标签与内容。
///
/// 外壳（chrome、页签保活、二级页头部）在
/// [SplitPanelScaffold]；6 个 tab 与 5 个二级页的装配在
/// `split_tabs/player_split_tabs.dart`。本类只做映射，不含状态。
class PlayerSplitPanel extends StatelessWidget {
  const PlayerSplitPanel({
    super.key,
    required this.host,
    required this.tab,
    required this.subPage,
    required this.onTabChanged,
    required this.onClose,
    required this.onBack,
  });

  final SplitTabHost host;

  /// 当前页签（由 `PlayerPanelController` 持有）。
  final SplitPanelTab tab;

  /// 当前二级页（`null` = 页签内容）。
  final SplitSubPage? subPage;

  final ValueChanged<SplitPanelTab> onTabChanged;

  /// 收起面板。
  final VoidCallback onClose;

  /// 从二级页返回页签内容。
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final subPage = this.subPage;
    return SplitPanelScaffold(
      tabs: [for (final tab in SplitPanelTab.values) tab.label],
      bodies: buildSplitPanelTabs(host),
      index: tab.index,
      onTabChanged: (index) => onTabChanged(SplitPanelTab.values[index]),
      onClose: onClose,
      subPageTitle: subPage?.title,
      subPageBody: subPage == null ? null : buildSplitSubPage(host, subPage),
      onBack: onBack,
    );
  }
}
