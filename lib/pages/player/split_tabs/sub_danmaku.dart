import 'package:flutter/material.dart';

import 'package:wyw/pages/player/split_tabs/split_tab_host.dart';
import 'package:wyw/pages/settings/danmaku/danmaku_shield_editor.dart';
import 'package:wyw/pages/settings/danmaku/danmaku_time_offset_content.dart';

/// 弹幕相关的二级页：时间偏移 / 屏蔽设置。
///
/// 两个类都在本文件内（面板一次只挂一个二级页）。一律**无外壳**：不含标题栏、
/// 关闭按钮、`SafeArea`——页面标题与返回箭头由面板外壳
/// （`SplitPanelScaffold`）提供；边距按面板宽度（最窄约 280px）由这里传入。
/// 两个页面都自带滚动容器，面板再矮也不溢出。
///
/// 两个页面挂的都是**共用内容件**：屏蔽挂 `DanmakuShieldEditor`，时间偏移挂
/// `DanmakuTimeOffsetContent`——与设置页的对应卡片是同一份实现（不是复制），
/// 因此不存在两份行为需要对齐。
///
/// 「弹幕检索/换库」原本也是这里的一个二级页，现已内联进同级的「弹幕」tab
/// （`tab_danmaku.dart`）：它需要整页高度做搜索 + 列表 + 详情卡，
/// 塞进"二级页"这一层反而把可用高度切成三段。

/// 二级页共用边距：比设置页的 24 收窄（面板窄，留出更多内容宽度）。
///
/// **顶部必须是正数**：二级页头部下方紧跟一条 `Divider(height: 1)`，若顶部为 0，
/// 主体第一行会直接贴在那条分割线上（真机反馈过）。共用内容件的默认顶部边距
/// （屏蔽编辑器 `24,0,24,24`、时间偏移 `EdgeInsets.zero`）都是"由外壳补顶部间距"
/// 的设计，所以这个间距只能由这里给。
const EdgeInsets _subPagePadding = EdgeInsets.fromLTRB(12, 12, 12, 16);

/// 屏蔽规则二级页：内嵌共用编辑器 [DanmakuShieldEditor]。
///
/// 该编辑器本身就是无头内容件（`ListView` + 边距参数，设置页与弹层两处已在
/// 共用），因此这里只挂它、不再包任何外壳。
class ShieldSubPage extends StatelessWidget {
  const ShieldSubPage({super.key, required this.host});

  /// 本页不需要控制器（屏蔽词仓库是全局单例，编辑器自己订阅变更）。保留该字段
  /// 是为了两个二级页的构造方式一致。
  final SplitTabHost host;

  @override
  Widget build(BuildContext context) =>
      const DanmakuShieldEditor(padding: _subPagePadding);
}

/// 弹幕时间偏移二级页：内嵌共用内容件 [DanmakuTimeOffsetContent]。
///
/// 与播放器内「弹幕时间校准」弹层是**同一份实现**：同一份范围常量
/// （[danmakuTimeOffsetMinSeconds] / [danmakuTimeOffsetMaxSeconds] /
/// [danmakuTimeOffsetDivisions]）、同一套 ±1 秒微调 / 滑杆 / 恢复同步交互、同一个
/// 存储键与同一个归一/文案函数，只是外壳不同（这里不 pop 路由、边距更窄）。
/// 改动同样立刻让已排队弹幕失效——与弹层侧传的是同一个动作。
class TimeOffsetSubPage extends StatelessWidget {
  const TimeOffsetSubPage({super.key, required this.host});

  final SplitTabHost host;

  @override
  Widget build(BuildContext context) {
    return DanmakuTimeOffsetContent(
      padding: _subPagePadding,
      onTimelineOffsetChanged:
          host.playerController.danmaku.clearAndInvalidateScheduled,
    );
  }
}
