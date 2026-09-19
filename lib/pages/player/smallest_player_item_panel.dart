import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wyw/bean/styles/media_chrome_colors.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/widget/play_pause_icon.dart';
import 'package:wyw/pages/player/player_adjustment_hud.dart';
import 'package:wyw/pages/player/controller/player_aspect_ratio.dart';
import 'package:wyw/pages/player/controller/player_super_resolution.dart';
import 'package:wyw/pages/player/player_panel_hold.dart';
import 'package:wyw/services/player/pip_utils.dart';
import 'package:wyw/pages/video/video_controller.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/pages/player/player_controller.dart';
import 'package:wyw/pages/player/skip_seconds_dialog.dart';
import 'package:wyw/services/player/remote.dart';
import 'package:wyw/utils/constants.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:wyw/bean/widget/embedded_native_control_area.dart';
import 'package:wyw/services/player/timed_shutdown_service.dart';
import 'package:wyw/utils/device.dart';
import 'package:wyw/utils/format.dart';

class SmallestPlayerItemPanel extends StatefulWidget {
  const SmallestPlayerItemPanel({
    super.key,
    required this.playerController,
    required this.onBackPressed,
    required this.setPlaybackSpeed,
    required this.handleFullscreen,
    required this.handleProgressBarDragStart,
    required this.handleProgressBarSeek,
    required this.handleSuperResolutionChange,
    required this.panelVisibilityController,
    required this.acquirePlayerPanelHold,
    required this.skipOP,
    required this.showVideoInfo,
    required this.pauseForTimedShutdown,
    this.disableAnimations = false,
    this.toggleEpisodePanel,
  });

  final PlayerController playerController;
  final void Function(BuildContext) onBackPressed;
  final Future<void> Function(double) setPlaybackSpeed;
  final void Function() skipOP;
  final void Function() handleFullscreen;
  final VoidCallback handleProgressBarDragStart;
  final Future<void> Function(Duration duration) handleProgressBarSeek;
  final Future<void> Function(SuperResolutionMode mode)
      handleSuperResolutionChange;
  final AnimationController panelVisibilityController;
  final PlayerPanelHold Function() acquirePlayerPanelHold;
  final void Function() showVideoInfo;
  final VoidCallback pauseForTimedShutdown;
  final bool disableAnimations;

  /// 选集/线路面板切换回调（由视频页传入）。
  final VoidCallback? toggleEpisodePanel;

  @override
  State<SmallestPlayerItemPanel> createState() =>
      _SmallestPlayerItemPanelState();
}

class _SmallestPlayerItemPanelState extends State<SmallestPlayerItemPanel> {
  late bool haEnable;
  late Animation<Offset> topOffsetAnimation;
  late Animation<Offset> bottomOffsetAnimation;
  late Animation<Offset> leftOffsetAnimation;
  final VideoPageController videoPageController = inject<VideoPageController>();
  late final PlayerController playerController;
  final TextEditingController textController = TextEditingController();

  // SVG Caches
  String? cachedSvgString;
  Widget? cachedDanmakuOnIcon;
  Widget? cachedDanmakuOffIcon;

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  void showForwardChange() {
    showSkipSecondsDialog(
      currentSkipTime: playerController.playback.buttonSkipTime,
      onSave: playerController.setButtonForwardTime,
    );
  }

  @override
  void initState() {
    super.initState();
    playerController = widget.playerController;
    topOffsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.0),
      end: const Offset(0.0, 0.0),
    ).animate(CurvedAnimation(
      parent: widget.panelVisibilityController,
      curve: Curves.easeInOut,
    ));
    bottomOffsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, 1.0),
      end: const Offset(0.0, 0.0),
    ).animate(CurvedAnimation(
      parent: widget.panelVisibilityController,
      curve: Curves.easeInOut,
    ));
    leftOffsetAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: const Offset(0.0, 0.0),
    ).animate(CurvedAnimation(
      parent: widget.panelVisibilityController,
      curve: Curves.easeInOut,
    ));
    haEnable = GStorage.getSetting(SettingsKeys.hAenable);
  }

  Widget forwardIcon() {
    return Tooltip(
      message: '快进${playerController.playback.buttonSkipTime}秒，长按修改时间',
      child: GestureDetector(
        onLongPress: () => showForwardChange(),
        child: IconButton(
          icon: Image.asset(
            'assets/images/forward_80.png',
            color: MediaChromeColors.foreground,
            height: 24,
          ),
          onPressed: () {
            widget.skipOP();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedPositioned(
          duration: const Duration(seconds: 1),
          top: 0,
          left: 0,
          right: 0,
          child: Observer(builder: (context) {
            return Visibility(
              visible: !playerController.panel.lockPanel &&
                  (widget.disableAnimations
                      ? playerController.panel.showVideoController
                      : true),
              child: widget.disableAnimations
                  ? Container(
                      height: 50,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            MediaChromeColors.barrier,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    )
                  : SlideTransition(
                      position: topOffsetAnimation,
                      child: Container(
                        height: 50,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              MediaChromeColors.barrier,
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
            );
          }),
        ),
        AnimatedPositioned(
          duration: const Duration(seconds: 1),
          bottom: 0,
          left: 0,
          right: 0,
          child: Observer(builder: (context) {
            return Visibility(
              visible: !playerController.panel.lockPanel &&
                  (widget.disableAnimations
                      ? playerController.panel.showVideoController
                      : true),
              child: widget.disableAnimations
                  ? Container(
                      height: 100,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            MediaChromeColors.barrier,
                          ],
                        ),
                      ),
                    )
                  : SlideTransition(
                      position: bottomOffsetAnimation,
                      child: Container(
                        height: 100,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              MediaChromeColors.barrier,
                            ],
                          ),
                        ),
                      ),
                    ),
            );
          }),
        ),
        Positioned(
          top: 25,
          child: Observer(builder: (context) {
            return PlayerSeekHud(
              visible: playerController.panel.showSeekTime,
              currentPosition: playerController.playback.currentPosition,
              playerPosition: playerController.playback.playerPosition,
              duration: playerController.playback.duration,
              direction: playerController.panel.seekDirection,
              disableAnimations: widget.disableAnimations,
            );
          }),
        ),
        Positioned(
          top: 25,
          child: Observer(builder: (context) {
            return PlayerSpeedHud(
              visible: playerController.panel.showPlaySpeed,
              speed: playerController.playback.playerSpeed,
              disableAnimations: widget.disableAnimations,
            );
          }),
        ),
        Positioned(
          top: 25,
          child: Observer(builder: (context) {
            final showVolume = playerController.panel.showVolume;
            final showBrightness = playerController.panel.showBrightness;
            return PlayerAdjustmentHud(
              visible: showVolume || showBrightness,
              type: showVolume
                  ? PlayerAdjustmentHudType.volume
                  : PlayerAdjustmentHudType.brightness,
              value: showVolume
                  ? playerController.playback.volume
                  : playerController.panel.brightness,
              disableAnimations: widget.disableAnimations,
            );
          }),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Observer(builder: (context) {
            return Visibility(
              visible: !playerController.panel.lockPanel &&
                  (widget.disableAnimations
                      ? playerController.panel.showVideoController
                      : true),
              child: widget.disableAnimations
                  ? topControlWidget
                  : SlideTransition(
                      position: topOffsetAnimation, child: topControlWidget),
            );
          }),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Observer(builder: (context) {
            return Visibility(
              visible: !playerController.panel.lockPanel &&
                  (widget.disableAnimations
                      ? playerController.panel.showVideoController
                      : true),
              child: widget.disableAnimations
                  ? bottomControlWidget
                  : SlideTransition(
                      position: bottomOffsetAnimation,
                      child: bottomControlWidget),
            );
          }),
        ),
      ],
    );
  }

  Widget get bottomControlWidget {
    return Row(
      children: [
        IconButton(
          icon: PlayPauseIcon(
            iconColor: MediaChromeColors.foreground,
            playing: playerController.playback.playing,
          ),
          tooltip: playerController.playback.playing ? '暂停' : '播放',
          onPressed: () {
            playerController.playOrPause();
          },
        ),
        // 上一集 / 下一集（当前线路内切换，结构化进入时显示）
        if (videoPageController.sources.isNotEmpty) ...[
          IconButton(
            color: MediaChromeColors.foreground,
            icon: const Icon(Icons.skip_previous_rounded),
            tooltip: '上一集',
            onPressed: videoPageController.hasPreviousEpisode
                ? () {
                    videoPageController.playAdjacentEpisode(
                      -1,
                      playerController: playerController,
                    );
                  }
                : null,
          ),
          IconButton(
            color: MediaChromeColors.foreground,
            icon: const Icon(Icons.skip_next_rounded),
            tooltip: '下一集',
            onPressed: videoPageController.hasNextEpisode
                ? () {
                    videoPageController.playAdjacentEpisode(
                      1,
                      playerController: playerController,
                    );
                  }
                : null,
          ),
        ],
        Expanded(
          child: ProgressBar(
            thumbRadius: 8,
            thumbGlowRadius: 18,
            timeLabelLocation: TimeLabelLocation.none,
            progress: playerController.playback.currentPosition,
            buffered: playerController.playback.buffer,
            total: playerController.playback.duration,
            onSeek: widget.handleProgressBarSeek,
            onDragStart: (_) => widget.handleProgressBarDragStart(),
            onDragUpdate: (details) => playerController.seeking
                .updateInteractiveSeek(details.timeStamp),
          ),
        ),
        Text(
          '    ${durationToString(playerController.playback.currentPosition)} / ${durationToString(playerController.playback.duration)}',
          style: const TextStyle(
            color: MediaChromeColors.foreground,
            fontSize: 12.0,
            fontFeatures: [
              FontFeature.tabularFigures(),
            ],
          ),
        ),
        // 非桌面端恒为全屏，不提供全屏切换按钮；竖屏/横屏都提供方向锁定按钮。
        if (!isDesktop())
          IconButton(
            color: MediaChromeColors.foreground,
            icon: Icon(
              videoPageController.isOrientationLocked
                  ? Icons.screen_lock_rotation
                  : Icons.screen_rotation,
            ),
            tooltip:
                videoPageController.isOrientationLocked ? '解锁屏幕方向' : '锁定屏幕方向',
            onPressed: () {
              videoPageController.toggleOrientationLock(
                MediaQuery.orientationOf(context),
              );
            },
          )
        else if (isDesktop() && !videoPageController.isPip)
          IconButton(
            color: MediaChromeColors.foreground,
            icon: Icon(videoPageController.isFullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded),
            tooltip: videoPageController.isFullscreen ? '退出全屏' : '全屏',
            onPressed: () {
              widget.handleFullscreen();
            },
          )
      ],
    );
  }

  Widget get topControlWidget {
    return EmbeddedNativeControlArea(
      child: Row(
        children: [
          ..._topBarActions(),
          _moreOptionsMenu(),
        ],
      ),
    );
  }

  /// 顶栏左侧按钮：返回、拖动条、跳过、选集、画中画。
  List<Widget> _topBarActions() {
    return [
      IconButton(
        color: MediaChromeColors.foreground,
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: '返回',
        onPressed: () {
          widget.onBackPressed(context);
        },
      ),
      // 拖动条
      const Expanded(
        child: dtb.DragToMoveArea(child: SizedBox(height: 40)),
      ),
      // 跳过
      forwardIcon(),
      // 选集/线路面板（仅结构化进入时可用）
      if (widget.toggleEpisodePanel != null &&
          videoPageController.sources.isNotEmpty)
        IconButton(
          color: MediaChromeColors.foreground,
          icon: const Icon(Icons.menu_open_outlined),
          tooltip: '选集面板',
          onPressed: widget.toggleEpisodePanel,
        ),
      if (isDesktop() || Platform.isAndroid)
        IconButton(
            onPressed: () async {
              final toggled = await PipUtils.togglePip(
                isPip: videoPageController.isPip,
                isPlaying: playerController.playback.playing,
                width: playerController.debug.playerWidth,
                height: playerController.debug.playerHeight,
              );
              if (isDesktop()) {
                videoPageController.isPip = toggled;
              }
            },
            tooltip: '画中画',
            icon: const Icon(Icons.picture_in_picture, color: MediaChromeColors.foreground)),
    ];
  }

  /// 顶栏右侧「更多选项」菜单：比例、倍速、超分辨率、定时关闭、投屏等。
  Widget _moreOptionsMenu() {
    return PlayerPanelHoldMenuAnchor(
      acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
      consumeOutsideTap: true,
      builder:
          (BuildContext context, MenuController controller, Widget? child) {
        return IconButton(
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          tooltip: '更多选项',
          icon: const Icon(
            Icons.more_vert,
            color: MediaChromeColors.foreground,
          ),
        );
      },
      menuChildren: [
        SubmenuButton(
          menuChildren: [
            for (final aspectRatioMode in PlayerAspectRatio.values)
              MenuItemButton(
                onPressed: () =>
                    playerController.panel.aspectRatioMode = aspectRatioMode,
                child: Container(
                  height: 48,
                  constraints: BoxConstraints(minWidth: 112),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      aspectRatioMode.label,
                      style: TextStyle(
                          color: aspectRatioMode ==
                                  playerController.panel.aspectRatioMode
                              ? Theme.of(context).colorScheme.primary
                              : null),
                    ),
                  ),
                ),
              ),
          ],
          child: Container(
            height: 48,
            constraints: BoxConstraints(minWidth: 112),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('视频比例'),
            ),
          ),
        ),
        SubmenuButton(
          menuChildren: [
            for (final double i in defaultPlaySpeedList) ...<MenuItemButton>[
              MenuItemButton(
                onPressed: () async {
                  await widget.setPlaybackSpeed(i);
                },
                child: Container(
                  height: 48,
                  constraints: BoxConstraints(minWidth: 112),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${i}x',
                      style: TextStyle(
                          color: i == playerController.playback.playerSpeed
                              ? Theme.of(context).colorScheme.primary
                              : null),
                    ),
                  ),
                ),
              ),
            ],
          ],
          child: Container(
            height: 48,
            constraints: BoxConstraints(minWidth: 112),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('倍速'),
            ),
          ),
        ),
        SubmenuButton(
          menuChildren: [
            for (final mode in SuperResolutionMode.values)
              MenuItemButton(
                onPressed: () => widget.handleSuperResolutionChange(mode),
                child: Container(
                  height: 48,
                  constraints: BoxConstraints(minWidth: 112),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      mode.label,
                      style: TextStyle(
                        color: playerController.playback.superResolutionMode ==
                                mode
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
          ],
          child: Container(
            height: 48,
            constraints: BoxConstraints(minWidth: 112),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('超分辨率'),
            ),
          ),
        ),
        MenuItemButton(
          onPressed: () {
            widget.showVideoInfo();
          },
          child: Container(
            height: 48,
            constraints: BoxConstraints(minWidth: 112),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('视频详情'),
            ),
          ),
        ),
        MenuItemButton(
          onPressed: () {
            bool needRestart = playerController.playback.playing;
            playerController.pause();
            RemotePlay().castVideo(playerController.videoUrl).whenComplete(() {
              if (mounted && needRestart) {
                playerController.play();
              }
            });
          },
          child: Container(
            height: 48,
            constraints: BoxConstraints(minWidth: 112),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('远程投屏'),
            ),
          ),
        ),
        MenuItemButton(
          onPressed: () {
            playerController.launchExternalPlayer();
          },
          child: Container(
            height: 48,
            constraints: BoxConstraints(minWidth: 112),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('外部播放'),
            ),
          ),
        ),
        MenuItemButton(
          onPressed: () async {
            // 重新解析：清缓存并强制重走解析/嗅探后播放
            try {
              await playerController.stop();
            } catch (_) {}
            await videoPageController.playEpisode(
              sourceIndex: videoPageController.currentSourceIndex,
              episodeIndex: videoPageController.currentEpisodeIndex,
              playerController: playerController,
              forceReresolve: true,
            );
          },
          child: Container(
            height: 48,
            constraints: BoxConstraints(minWidth: 112),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('重新解析'),
            ),
          ),
        ),
        // 定时关闭
        SubmenuButton(
          menuChildren: [
            MenuItemButton(
              onPressed: () {
                TimedShutdownService().cancel();
              },
              child: Container(
                height: 48,
                constraints: BoxConstraints(minWidth: 112),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '不开启',
                    style: TextStyle(
                      color: !TimedShutdownService().isActive
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            for (final int minutes in [15, 30, 60])
              MenuItemButton(
                onPressed: () {
                  TimedShutdownService()
                      .start(minutes, onExpired: widget.pauseForTimedShutdown);
                  WywDialog.showToast(
                      message:
                          '已设置 ${TimedShutdownService().formatMinutesToDisplay(minutes)} 后定时关闭');
                },
                child: Container(
                  height: 48,
                  constraints: BoxConstraints(minWidth: 112),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$minutes 分钟',
                      style: TextStyle(
                        color: TimedShutdownService().setMinutes == minutes
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            MenuItemButton(
              onPressed: () {
                TimedShutdownService.showCustomTimerDialog(
                  onExpired: widget.pauseForTimedShutdown,
                );
              },
              child: Container(
                height: 48,
                constraints: BoxConstraints(minWidth: 112),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('自定义'),
                ),
              ),
            ),
          ],
          child: Container(
            height: 48,
            constraints: BoxConstraints(minWidth: 112),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ValueListenableBuilder<int>(
                valueListenable:
                    TimedShutdownService().remainingSecondsNotifier,
                builder: (context, remainingSeconds, child) {
                  return Text(
                    remainingSeconds > 0
                        ? '定时关闭 (${TimedShutdownService().formatRemainingTime()})'
                        : '定时关闭',
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
