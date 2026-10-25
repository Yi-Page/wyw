import 'package:flutter/foundation.dart';
import 'package:wyw/pages/player/controller/player_panel_controller.dart';
import 'package:wyw/pages/player/controller/player_super_resolution.dart';
import 'package:wyw/pages/player/player_controller.dart';
import 'package:wyw/pages/video/video_controller.dart';

/// 分屏面板各 tab / 二级页的宿主：把「面板需要的一切」收成一个值对象。
///
/// 为什么要有它：v1 把 13 个必填回调摊在 tab 的构造参数上，每加一项都要同时改
/// 面板与播放器页的签名。收成一个对象后，tab 只依赖它，播放器页只构造一次。
///
/// 控制器本身已经是「单一事实源」：tab 一律读 [playerController] /
/// [videoPageController] 的 observable，不各自 `setState` 缓存设置值。
@immutable
class SplitTabHost {
  const SplitTabHost({
    required this.playerController,
    required this.videoPageController,
    required this.disableAnimations,
    required this.setPlaybackSpeed,
    required this.handleSuperResolutionChange,
    required this.skipOP,
    required this.handleScreenshot,
    required this.showScreenshotCandidates,
    required this.pauseForTimedShutdown,
    this.onEpisodeSelected,
    this.onDownloadEpisode,
  });

  final PlayerController playerController;
  final VideoPageController videoPageController;
  final bool disableAnimations;

  final Future<void> Function(double speed) setPlaybackSpeed;
  final Future<void> Function(SuperResolutionMode mode)
      handleSuperResolutionChange;
  final VoidCallback skipOP;
  final VoidCallback handleScreenshot;
  final VoidCallback showScreenshotCandidates;

  /// 定时关闭到期动作（暂停播放）。
  final VoidCallback pauseForTimedShutdown;

  /// 选集回调：`(sourceIndex, episodeIndex)`，**0 基**，与视频页 `_onEpisodeTap`
  /// 同一语义（`EpisodeSelectionPanel` 给的是 1 基集号，由选集 tab 自己换算）。
  final void Function(int sourceIndex, int episodeIndex)? onEpisodeSelected;

  /// 打开「缓存剧集」批量下载面板（按线路）。
  final void Function(int sourceIndex)? onDownloadEpisode;

  PlayerPanelController get panel => playerController.panel;

  /// 打开二级页（替换 body、不重放动画）。
  void openSubPage(SplitSubPage page) => panel.openSplitPanelSubPage(page);

  /// 从二级页返回页签内容。
  void closeSubPage() => panel.closeSplitPanelSubPage();
}
