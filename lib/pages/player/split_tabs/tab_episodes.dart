import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/download/download_controller.dart';
import 'package:wyw/pages/player/split_tabs/split_tab_host.dart';
import 'package:wyw/pages/video/episode_selection_panel.dart';

/// 选集 tab：线路/播放源 + 集列表（每集带下载按钮与状态）。
///
/// 与视频页的选集面板**同一份 widget**（[EpisodeSelectionPanel]），参数语义也
/// 照抄视频页（`video_page.dart` 的两处调用），只有两点差异：
/// - `isOffline` 用 `isCachedOnlyPlayback`（"整季都可离线"），**不是**
///   `isOfflineMode`（那只是"当前这一集是本地文件"，会让整季在线剧集错误显示
///   "已缓存"并抑制逐集标签——`video_controller.dart` 里有明确注释）；
/// - `isPlaying` 用视频页那套判据（playing && 两个 loading 都为假）。
///
/// 进入本页自动定位当前集（与视频页 `_revealCurrentEpisode` 一致）。
class EpisodesTab extends StatefulWidget {
  const EpisodesTab({super.key, required this.host});

  final SplitTabHost host;

  @override
  State<EpisodesTab> createState() => _EpisodesTabState();
}

class _EpisodesTabState extends State<EpisodesTab> {
  final GlobalKey<EpisodeSelectionPanelState> _panelKey =
      GlobalKey<EpisodeSelectionPanelState>();

  // 「进入本页自动定位当前集」由 [EpisodeSelectionPanel] 自己首次布局时完成
  // （历史页的选集弹窗同样受益），这里不再重复调用。

  @override
  Widget build(BuildContext context) {
    final vc = widget.host.videoPageController;
    final playback = widget.host.playerController.playback;
    return Observer(
      builder: (context) {
        // 实时观看位置/时长：必须在 Observer 内读取才会注册依赖，
        // 这样选集面板的进度条会随播放推进（其余集用集对象里持久化的值）。
        final livePositionMs = playback.currentPosition.inMilliseconds;
        final liveDurationMs = playback.duration.inMilliseconds;
        return EpisodeSelectionPanel(
          key: _panelKey,
          title: vc.videoTitle,
          roads: vc.sources,
          selectedRoad: vc.currentSourceIndex,
          // 面板收 1 基集号。
          selectedEpisode: vc.currentEpisodeIndex + 1,
          currentPositionMs: livePositionMs,
          currentDurationMs: liveDurationMs,
          onEpisodeSelected: (episode, road) =>
              widget.host.onEpisodeSelected?.call(road, episode - 1),
          downloads: inject<DownloadController>().episodeDownloadsFor(
            code: vc.videoCode,
          ),
          onDownload: widget.host.onDownloadEpisode,
          isOffline: vc.isCachedOnlyPlayback,
          isPlaying: playback.playing && !playback.loading && !vc.loading,
          disableAnimations: widget.host.disableAnimations,
        );
      },
    );
  }
}
