import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';

/// 时间标签相对进度条的位置。
///
/// 之所以要三档而不是固定一档：竖屏手机又窄又高，进度条两侧放不下时间；
/// 横屏/平板够宽但可能很扁，两侧仍可能有空间；桌面则习惯把时间摆在控制按钮
/// 之后。这条规则来自 Kazumi 的面板设计，用于让同一份底栏适配三种视口。
enum PlayerTimeLabelPlacement {
  aboveProgress,
  besideProgress,
  afterPlaybackButtons;

  static PlayerTimeLabelPlacement forViewport(
    Size viewport, {
    required bool desktop,
  }) {
    if (desktop) return afterPlaybackButtons;
    final hasRoomForSideLabels = viewport.shortestSide >= 600 &&
        viewport.shortestSide / viewport.longestSide >= 9 / 16;
    return hasRoomForSideLabels ? besideProgress : aboveProgress;
  }
}

/// 播放器底栏（传输控制）。
///
/// 两套布局由 [compact] 决定，而不是由两份 widget 决定 —— 这正是面板"窄屏不挤"
/// 的关键：窄屏只留「播放 + 进度 + 时间 + 全屏」一行，切集等次要操作交给选集面板。
///
/// 颜色不在这里决定：调用方传入已着色的 widget（wyw 的媒体铬层色见
/// `MediaChromeColors`）。
class PlayerTransportBar extends StatelessWidget {
  const PlayerTransportBar({
    super.key,
    required this.compact,
    required this.playPause,
    required this.nextEpisode,
    required this.progressBuilder,
    required this.timeLabel,
    required this.timePlacement,
    required this.controls,
    required this.fullscreen,
  });

  final bool compact;
  final Widget playPause;
  final Widget nextEpisode;
  final Widget Function(TimeLabelLocation location) progressBuilder;
  final Widget timeLabel;
  final PlayerTimeLabelPlacement timePlacement;

  /// 宽屏时跟在切集按钮之后的额外控件（wyw 这里放「选集面板」入口等）。
  final Widget controls;
  final Widget fullscreen;

  @override
  Widget build(BuildContext context) => compact
      ? Row(
          children: [
            playPause,
            Expanded(child: progressBuilder(TimeLabelLocation.none)),
            timeLabel,
            fullscreen,
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (timePlacement == PlayerTimeLabelPlacement.aboveProgress)
              Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 10),
                child: timeLabel,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: progressBuilder(
                timePlacement == PlayerTimeLabelPlacement.besideProgress
                    ? TimeLabelLocation.sides
                    : TimeLabelLocation.none,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  playPause,
                  nextEpisode,
                  if (timePlacement ==
                      PlayerTimeLabelPlacement.afterPlaybackButtons)
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: timeLabel,
                    ),
                  Expanded(child: controls),
                  fullscreen,
                ],
              ),
            ),
            if (timePlacement != PlayerTimeLabelPlacement.aboveProgress)
              const SizedBox(height: 6),
          ],
        );
}
