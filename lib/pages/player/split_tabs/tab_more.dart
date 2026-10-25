import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wyw/bean/settings/settings_list.dart';
import 'package:wyw/pages/player/controller/player_panel_controller.dart';
import 'package:wyw/pages/player/split_tabs/split_tab_host.dart';
import 'package:wyw/services/storage/storage.dart';

/// 更多 tab：播放器调试模式 / 调试信息 / 刷新播放源。
///
/// **不设任何「跳转设置页」入口**（§1.4-1、§1.3）：长尾项（硬解开关、后台播放、
/// 默认倍速等）仍留在设置页，这里只放"播放本次会话"相关的调试与重载动作。
///
/// 「刷新播放源」= 既有「更多」菜单的「重新解析」（先 `stop()` 清资源，再
/// `forceReresolve: true` 重排同一线路/集）。既有实现里**没有**独立的「重新加载」
/// （全仓无 `reload` 语义的播放器重载入口），因此按"一个动作一个实现"合并为
/// 本行，不新造第二份。
class MoreTab extends StatelessWidget {
  const MoreTab({super.key, required this.host});

  final SplitTabHost host;

  @override
  Widget build(BuildContext context) {
    final playback = host.playerController.playback;

    return SettingsList(
      sections: [
        SettingsSection(
          title: const Text('调试'),
          tiles: [
            SettingsTile.switchTile(
              leading: Icons.bug_report_rounded,
              title: const Text('播放器调试模式'),
              description: const Text('把 MPV 内部日志写进应用日志；下次创建播放器时生效'),
              // `playerDebugMode` 是 observable，开关变化会自动重建本行。
              initialValue: playback.playerDebugMode,
              onToggle: (value) {
                final bool next = value ?? !playback.playerDebugMode;
                playback.playerDebugMode = next;
                unawaited(
                  GStorage.putSetting<bool>(SettingsKeys.playerDebugMode, next),
                );
              },
            ),
            SettingsTile(
              leading: Icons.receipt_long_rounded,
              title: const Text('调试信息'),
              description: const Text('播放信息与 MPV 日志'),
              onPressed: (context) => host.openSubPage(SplitSubPage.videoInfo),
            ),
          ],
        ),
        SettingsSection(
          title: const Text('播放源'),
          tiles: [
            SettingsTile(
              leading: Icons.refresh_rounded,
              title: const Text('刷新播放源'),
              description: const Text('清掉本集直链缓存，强制重新解析 / 嗅探后再播放'),
              onPressed: (context) => unawaited(_refreshSource()),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _refreshSource() async {
    final playerController = host.playerController;
    final videoPageController = host.videoPageController;
    try {
      await playerController.stop();
    } catch (_) {
      // 与既有「重新解析」一致：停了就继续重排，失败不阻断。
    }
    await videoPageController.playEpisode(
      sourceIndex: videoPageController.currentSourceIndex,
      episodeIndex: videoPageController.currentEpisodeIndex,
      playerController: playerController,
      forceReresolve: true,
    );
  }
}
