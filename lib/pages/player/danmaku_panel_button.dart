import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:wyw/bean/styles/media_chrome_colors.dart';
import 'package:wyw/pages/player/controller/player_panel_controller.dart';
import 'package:wyw/pages/player/player_controller.dart';

/// 播放器顶栏的弹幕按钮。
///
/// 只在**宽屏**顶栏常驻（窄屏顶栏放不下，入口改由分屏面板的「弹幕」tab 提供）。
/// 三种状态两种行为：还没匹配到弹幕库时单击直接打开「弹幕」tab（此时开关没有
/// 意义，用户真正需要的是先选一个库）；已匹配时单击开关弹幕、长按换库。
///
/// 换库**不再弹底部弹层**：搜索 / 类型筛选 / 详情卡 / 选分集整条动线已内联在
/// 分屏面板的「弹幕」tab（`split_tabs/tab_danmaku.dart`），弹层等于同一件事的
/// 第二份实现（仓库约定：禁止双入口）。
class DanmakuPanelButton extends StatelessWidget {
  const DanmakuPanelButton({
    super.key,
    required this.playerController,
  });

  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) {
      final danmaku = playerController.danmaku;
      final on = danmaku.danmakuOn;
      final unmatched = danmaku.danmakuEpisodeId == 0;
      return IconButton(
        color: MediaChromeColors.foreground,
        icon: Icon(
          on ? Icons.subtitles_rounded : Icons.subtitles_off_rounded,
        ),
        tooltip: unmatched
            ? '未匹配弹幕库（点击选择）'
            : (on ? '弹幕：开（长按换库）' : '弹幕：关（长按换库）'),
        onPressed: () {
          if (unmatched) {
            _openDanmakuTab();
            return;
          }
          danmaku.setDanmakuEnabled(!on);
        },
        onLongPress: _openDanmakuTab,
      );
    });
  }

  /// 打开分屏面板的「弹幕」tab：选择与换库的动线都在那里。
  void _openDanmakuTab() =>
      playerController.panel.openSplitPanel(SplitPanelTab.danmaku);
}
