import 'package:flutter/material.dart';
import 'package:wyw/pages/player/controller/player_panel_controller.dart';
import 'package:wyw/pages/player/split_tabs/split_tab_host.dart';
import 'package:wyw/pages/player/split_tabs/sub_danmaku.dart';
import 'package:wyw/pages/player/split_tabs/sub_display.dart';
import 'package:wyw/pages/player/split_tabs/tab_danmaku.dart';
import 'package:wyw/pages/player/split_tabs/tab_danmaku_settings.dart';
import 'package:wyw/pages/player/split_tabs/tab_display.dart';
import 'package:wyw/pages/player/split_tabs/tab_episodes.dart';
import 'package:wyw/pages/player/split_tabs/tab_more.dart';
import 'package:wyw/pages/player/split_tabs/tab_playback.dart';

/// 面板页签内容的唯一装配点。
///
/// 顺序必须与 [SplitPanelTab.values] 一致（TabBarView 按下标取页）。
List<Widget> buildSplitPanelTabs(SplitTabHost host) => <Widget>[
      EpisodesTab(host: host),
      DanmakuTab(host: host),
      DanmakuSettingsTab(host: host),
      DisplayTab(host: host),
      PlaybackTab(host: host),
      MoreTab(host: host),
    ];

/// 二级页内容的唯一装配点。
///
/// 用类型分派（[SplitSubPage]），不用字符串——改名不会静默变成空 body。
Widget buildSplitSubPage(SplitTabHost host, SplitSubPage page) {
  return switch (page) {
    SplitSubPage.filter => FilterSubPage(host: host),
    SplitSubPage.videoInfo => VideoInfoSubPage(host: host),
    SplitSubPage.shield => ShieldSubPage(host: host),
    SplitSubPage.timeOffset => TimeOffsetSubPage(host: host),
  };
}
