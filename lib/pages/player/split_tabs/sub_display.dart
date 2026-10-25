import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:wyw/bean/widget/content_section.dart';
import 'package:wyw/pages/player/controller/video_filter_controller.dart';
import 'package:wyw/pages/player/split_tabs/split_tab_host.dart';
import 'package:wyw/pages/player/widgets/video_details_content.dart';
import 'package:wyw/pages/player/widgets/video_filter_widgets.dart';
import 'package:wyw/pages/settings/filter_presets_settings.dart';

/// 画面调节二级页（**无头**：没有标题栏 / 关闭按钮 / `SafeArea`，那些在外壳
/// `SplitPanelScaffold` 里；边距由本页自己按面板宽度给）。
///
/// 三段式，**全部在本页内完成，不跳页**（§1.4-1）：
///   1. [VideoFilterPresetPicker] —— 切换 / 新建 / 关闭预设（chip + 新建）；
///   2. [VideoFilterSliders] —— 当前预设的 5 个参数，逐刻度实时下发播放器；
///   3. [FilterPresetsBody] —— 预设管理列表：切换 / **重命名** / **删除** /
///      逐预设调参（与设置页共用同一份内容件，所以两边不会漂移）。
///
/// 面板宽度可窄到 280px：整页纵向滚动，横向不留固定宽度；[FilterPresetsBody]
/// 的边距经参数传成 0（本页已给外边距），避免嵌套双份内边距。
class FilterSubPage extends StatelessWidget {
  const FilterSubPage({super.key, required this.host});

  final SplitTabHost host;

  /// 面板比设置页窄，横向收到 12；底部留出滚动余量。
  static const EdgeInsets _padding = EdgeInsets.fromLTRB(12, 12, 12, 24);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Observer(builder: (context) {
      final active = VideoFilterController.instance.activePreset;
      return SingleChildScrollView(
        padding: _padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const VideoFilterPresetPicker(),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (active == null)
              Text(
                '未启用画面调节：先新建或选择一个预设，再调节下面 5 个参数。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              VideoFilterSliders(presetId: active.id),
            const SizedBox(height: 20),
            const SectionHeader(title: Text('预设管理')),
            const SizedBox(height: 8),
            // 边距参数化（不用 embedded 开关）：本页已给 12 的外边距。
            const FilterPresetsBody(padding: EdgeInsets.zero),
          ],
        ),
      );
    });
  }
}

/// 视频信息二级页（**无头**）：概览 / 日志两个页签的全部内容来自共用内容件
/// [VideoDetailsContent]（P0 抽出，与播放器内「视频详情」弹层同源）。
///
/// 两个边距都是必填参数、由外壳给出：内容区取零（列表项自带 16 的横向内边距），
/// 页签条只留一点下边距。**不改**内容件的默认值，也不给它加 `embedded` 开关。
///
/// 高度：内容件内部含 `Expanded`，必须由父级给出**有界高度**——面板 body 已在
/// `SplitPanelScaffold` 的 `Expanded` 里，所以这里**不能**再套滚动视图
/// （那会把高度变成无限，`Expanded` 直接抛错）。
class VideoInfoSubPage extends StatelessWidget {
  const VideoInfoSubPage({super.key, required this.host});

  final SplitTabHost host;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: VideoDetailsContent(
        playerController: host.playerController,
        padding: EdgeInsets.zero,
        tabsPadding: const EdgeInsets.only(bottom: 8),
      ),
    );
  }
}
