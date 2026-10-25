import 'dart:async';

import 'package:flutter/material.dart';

import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/modules/danmaku/danmaku_episode_response.dart';
import 'package:wyw/pages/player/danmaku_selection/danmaku_search_panel.dart';
import 'package:wyw/pages/player/split_tabs/split_tab_host.dart';
import 'package:wyw/services/danmaku/danmaku_library_service.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

/// 弹幕 tab：**选择与关联**——搜索作品 → 选中预览 → 选分集 → 立即应用。
///
/// 分工：显示效果 / 来源开关 / 时间校准 / 屏蔽规则都在同级的「弹幕设置」tab
/// （`tab_danmaku_settings.dart`）。选择与设置混在一个 tab 里，会让"当前用的是
/// 哪个库"和"弹幕怎么显示"互相抢位置。
///
/// 顶部**不再有**独立的"当前使用"状态行：那一行与库卡片说的是同一件事，现在
/// 统一由卡片表达（卡片自己会用「使用中」标记区分"这个是当前使用的"）。整页
/// 只有一个滚动体，见 [DanmakuSearchPanel] 的版式说明。
///
/// 分集映射**刻意不持久化**（用户确认的口径）：切集后要再点一次分集。
class DanmakuTab extends StatelessWidget {
  const DanmakuTab({super.key, required this.host});

  final SplitTabHost host;

  @override
  Widget build(BuildContext context) {
    final video = host.videoPageController;
    return DanmakuSearchPanel(
      initialKeyword: video.videoTitle,
      localEpisodeIndex: video.currentEpisodeIndex,
      current: video.danmakuLibrary,
      onLibraryPersist: video.setDanmakuLibrary,
      onEpisodeSelected: (detail, episodeIndex) =>
          _applySelection(context, detail, episodeIndex),
    );
  }

  /// 用户选定「库 + 分集」：取该集弹幕 → 立刻灌进播放器。
  ///
  /// 返回 true 表示真的应用成功——面板据此把库写进进度记录（只有出得来弹幕的库
  /// 才值得被记住），所以"写进度"这件事刻意不在这里做。
  ///
  /// 顺序是有意的：先 `beginDanmakuLoad()` 进入"加载中"；取到弹幕再
  /// `applyDanmakuLoad`，失败则 `resetEpisodeSelection()` 回到"选了库但还没出
  /// 弹幕"的状态（不是把上一集的弹幕留在画布上）。
  Future<bool> _applySelection(
    BuildContext context,
    DanmakuBangumiDetail detail,
    int episodeIndex,
  ) async {
    final danmaku = host.playerController.danmaku;
    final episode = detail.episodes[episodeIndex];
    danmaku.beginDanmakuLoad();
    try {
      final danmakus =
          await DanmakuLibraryService.instance.loadComments(episode.episodeId);
      danmaku.applyDanmakuLoad(
        danmakus,
        episodeId: episode.episodeId,
        libraryTitle: detail.animeTitle,
        // 用户刚刚亲手点了这一集，没有任何理由不显示。
        enableDanmaku: true,
      );
      if (!context.mounted) return true;
      WywDialog.showToast(
        message: danmakus.isEmpty
            ? '「${detail.animeTitle}」这一集暂无弹幕'
            : '已切换到「${detail.animeTitle}」',
      );
      return true;
    } catch (error) {
      danmaku.resetEpisodeSelection();
      WywLogger().w(
        '${LogTag.danmaku} 应用所选弹幕失败 episodeId=${episode.episodeId}',
        error: error,
      );
      if (!context.mounted) return false;
      WywDialog.showToast(message: '弹幕加载失败');
      return false;
    }
  }
}
