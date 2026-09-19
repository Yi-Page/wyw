import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wyw/bean/styles/media_chrome_colors.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/widget/play_pause_icon.dart';
import 'package:wyw/pages/player/player_adjustment_hud.dart';
import 'package:wyw/pages/player/controller/player_aspect_ratio.dart';
import 'package:wyw/pages/player/controller/player_super_resolution.dart';
import 'package:wyw/bean/widget/embedded_native_control_area.dart';
import 'package:wyw/pages/player/player_panel_hold.dart';
import 'package:wyw/services/player/pip_utils.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/pages/download/download_controller.dart';
import 'package:wyw/pages/video/video_controller.dart';
import 'package:wyw/services/history/history_progress_reporter.dart';
import 'package:wyw/services/storage/history_type.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/pages/player/player_controller.dart';
import 'package:wyw/pages/player/skip_seconds_dialog.dart';
import 'package:wyw/services/player/remote.dart';
import 'package:wyw/utils/constants.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:wyw/services/player/timed_shutdown_service.dart';
import 'package:wyw/utils/device.dart';
import 'package:wyw/utils/format.dart';

import '../../bean/appbar/drag_to_move_bar.dart' as dtb;

class PlayerItemPanel extends StatefulWidget {
  const PlayerItemPanel({
    super.key,
    required this.playerController,
    required this.onBackPressed,
    required this.setPlaybackSpeed,
    required this.handleFullscreen,
    required this.handleScreenShot,
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
  final void Function() handleFullscreen;
  final void Function() handleScreenShot;
  final VoidCallback handleProgressBarDragStart;
  final Future<void> Function(Duration duration) handleProgressBarSeek;
  final Future<void> Function(SuperResolutionMode mode)
      handleSuperResolutionChange;
  final AnimationController panelVisibilityController;
  final PlayerPanelHold Function() acquirePlayerPanelHold;
  final void Function() skipOP;
  final void Function() showVideoInfo;
  final VoidCallback pauseForTimedShutdown;
  final bool disableAnimations;

  /// 选集/线路面板切换回调（由视频页传入）。
  final VoidCallback? toggleEpisodePanel;

  @override
  State<PlayerItemPanel> createState() => _PlayerItemPanelState();
}

class _PlayerItemPanelState extends State<PlayerItemPanel> {
  late bool haEnable;
  late Animation<Offset> topOffsetAnimation;
  late Animation<Offset> bottomOffsetAnimation;
  late Animation<Offset> leftOffsetAnimation;
  final VideoPageController videoPageController = inject<VideoPageController>();
  late final PlayerController playerController;
  final TextEditingController textController = TextEditingController();
  final FocusNode textFieldFocus = FocusNode();
  PlayerPanelHold? _danmakuTextFieldHold;

  // SVG Caches
  String? cachedSvgString;
  Widget? cachedDanmakuOnIcon;
  Widget? cachedDanmakuOffIcon;
  Widget? cachedDanmakuSettingIcon;

  @override
  void dispose() {
    _releaseDanmakuTextFieldPanel();
    textController.dispose();
    textFieldFocus.dispose();
    super.dispose();
  }

  void _releaseDanmakuTextFieldPanel() {
    _danmakuTextFieldHold?.release();
    _danmakuTextFieldHold = null;
  }

  /// 在下载记录中查找当前视频 URL 对应的下载任务
  _DownloadContext? _findCurrentDownload() {
    final downloadController = inject<DownloadController>();
    final episode = downloadController.findEpisodeByIdentity(
      sourceKey: videoPageController.sourceKey,
      videoId: videoPageController.videoId,
      sourceIndex: videoPageController.currentSourceIndex,
      episodeIndex: videoPageController.currentEpisodeIndex,
    );
    if (episode == null) return null;
    final plugin = videoPageController.sourceKey.isEmpty
        ? 'wyw'
        : videoPageController.sourceKey;
    final record = downloadController.getRecord(
        videoPageController.videoId.hashCode, plugin);
    if (record == null) return null;
    return _DownloadContext(
      record: record,
      episode: episode,
      downloadController: downloadController,
    );
  }

  /// 下载按钮：根据当前下载状态显示不同 UI
  Widget _buildDownloadButton() {
    return Observer(builder: (context) {
      final ctx = _findCurrentDownload();
      if (ctx == null) {
        return _buildIdleDownloadButton();
      }
      switch (ctx.episode.status) {
        case DownloadStatus.resolving:
          return _buildDownloadStatusIcon(
            tooltip: '正在解析视频源…',
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: MediaChromeColors.foregroundDim),
            ),
          );
        case DownloadStatus.downloading:
          return _buildDownloadingProgress(ctx);
        case DownloadStatus.completed:
          return _buildDownloadStatusIcon(
            tooltip: '已下载完成',
            child: Icon(Icons.check_circle,
                color: Theme.of(context).colorScheme.primary, size: 20),
          );
        case DownloadStatus.failed:
          return _buildDownloadStatusIcon(
            tooltip: '下载失败：${ctx.episode.errorMessage}',
            onTap: () {
              final dc = ctx.downloadController;
              dc.retryDownload(
                mediaId: ctx.record.mediaId,
                pluginName: ctx.record.pluginName,
                episodeNumber: ctx.episode.episodeNumber,
              );
              WywDialog.showToast(message: '正在重试下载');
            },
            child: Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error, size: 20),
          );
        case DownloadStatus.paused:
          return _buildDownloadStatusIcon(
            tooltip:
                '已暂停 · ${(ctx.episode.progressPercent * 100).toStringAsFixed(0)}%',
            onTap: () {
              final dc = ctx.downloadController;
              dc.retryDownload(
                mediaId: ctx.record.mediaId,
                pluginName: ctx.record.pluginName,
                episodeNumber: ctx.episode.episodeNumber,
              );
              WywDialog.showToast(message: '正在恢复下载');
            },
            child: const Icon(Icons.pause_circle_outline,
                color: MediaChromeColors.foregroundDim, size: 20),
          );
        case DownloadStatus.pending:
          return _buildDownloadStatusIcon(
            tooltip: '排队中…',
            child: const Icon(Icons.schedule, color: MediaChromeColors.foregroundFaint, size: 20),
          );
        default:
          return _buildIdleDownloadButton();
      }
    });
  }

  Widget _buildIdleDownloadButton() {
    return IconButton(
      tooltip: '下载视频',
      onPressed: () async {
        if (videoPageController.isPip) {
          WywDialog.showToast(message: '画中画状态下暂不支持下载');
          return;
        }
        var cover = videoPageController.videoCover;
        if (cover.isEmpty) {
          try {
            // v3：优先用结构化 id（$sourceKey:$videoId）查；旧 v2 以媒体直链为
            // key，需同时尝试入口 URL 与已解析直链，否则网页入口封面查不到。
            final structuredId = (videoPageController.videoId.isNotEmpty)
                ? ((videoPageController.sourceKey.isEmpty)
                    ? videoPageController.videoId
                    : '${videoPageController.sourceKey}:${videoPageController.videoId}')
                : '';
            final entry = (structuredId.isNotEmpty
                    ? HistoryProgressReporter().findEntry(
                        type: HistoryType.video,
                        sourceId: structuredId,
                      )
                    : null) ??
                HistoryProgressReporter().findEntry(
                  type: HistoryType.video,
                  sourceId: videoPageController.videoUrl,
                ) ??
                (videoPageController.resolvedVideoUrl.isNotEmpty
                    ? HistoryProgressReporter().findEntry(
                        type: HistoryType.video,
                        sourceId: videoPageController.resolvedVideoUrl,
                      )
                    : null);
            cover = entry?.cover ?? '';
          } catch (e) {
            WywLogger().d('${LogTag.player} 查询播放历史封面失败（已忽略）', error: e);
          }
        }
        // 先创建下载任务（resolve 形态的集会先经插件解析取地址）。
        // 显式点「下载」即允许合流：解析完成后切换到本地代理播放（播放即下载）。
        await videoPageController.downloadEpisode(
          videoPageController.currentSourceIndex,
          videoPageController.currentEpisodeIndex,
        );
        final switched = await videoPageController.startProxyForCurrentPlayback(
          playerController: playerController,
        );
        if (switched) {
          WywDialog.showToast(message: '已开始播放即下载，进度可在播放器上方查看');
        } else {
          WywDialog.showToast(message: '已添加到下载队列，可在 我的 -> 离线下载 中查看');
        }
      },
      icon: const Icon(Icons.download_outlined, color: MediaChromeColors.foreground),
    );
  }

  /// 进度指示器
  Widget _buildDownloadingProgress(_DownloadContext ctx) {
    final pct = (ctx.episode.progressPercent * 100).toStringAsFixed(0);
    return Tooltip(
      message: '下载中 · $pct%',
      child: SizedBox(
        width: 28,
        height: 28,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                value: ctx.episode.progressPercent,
                strokeWidth: 2.5,
                color: MediaChromeColors.foreground,
              ),
            ),
            Text(
              pct,
              style: const TextStyle(
                color: MediaChromeColors.foreground,
                fontSize: 7,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 通用状态图标包装
  Widget _buildDownloadStatusIcon({
    required String tooltip,
    required Widget child,
    VoidCallback? onTap,
  }) {
    final button = Padding(
      padding: const EdgeInsets.all(12),
      child: child,
    );
    if (onTap != null) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: button,
        ),
      );
    }
    return Tooltip(message: tooltip, child: button);
  }

  // 选择倍速
  void showSetSpeedSheet() {
    final double currentSpeed = playerController.playback.playerSpeed;
    WywDialog.show(builder: (context) {
      return AlertDialog(
        title: const Text('播放速度'),
        content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
          return Wrap(
            spacing: 8,
            runSpacing: isDesktop() ? 8 : 0,
            children: [
              for (final double i in defaultPlaySpeedList) ...<Widget>[
                if (i == currentSpeed)
                  FilledButton(
                    onPressed: () async {
                      await widget.setPlaybackSpeed(i);
                      WywDialog.dismiss();
                    },
                    child: Text(i.toString()),
                  )
                else
                  FilledButton.tonal(
                    onPressed: () async {
                      await widget.setPlaybackSpeed(i);
                      WywDialog.dismiss();
                    },
                    child: Text(i.toString()),
                  ),
              ]
            ],
          );
        }),
        actions: <Widget>[
          TextButton(
            onPressed: () => WywDialog.dismiss(),
            child: Text(
              '取消',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () async {
              await widget.setPlaybackSpeed(1.0);
              WywDialog.dismiss();
            },
            child: const Text('默认速度'),
          ),
        ],
      );
    });
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
        (isDesktop() || !videoPageController.isFullscreen)
            ? Container()
            : Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Observer(builder: (context) {
                  return Visibility(
                    visible: widget.disableAnimations
                        ? playerController.panel.showVideoController
                        : true,
                    child: widget.disableAnimations
                        ? leftControlWidget
                        : SlideTransition(
                            position: leftOffsetAnimation,
                            child: leftControlWidget),
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
    return SafeArea(
      top: false,
      bottom: videoPageController.isFullscreen,
      left: videoPageController.isFullscreen,
      right: videoPageController.isFullscreen,
      child: PlayerPanelHoldMouseRegion(
        acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
        cursor: (videoPageController.isFullscreen &&
                !playerController.panel.showVideoController)
            ? SystemMouseCursors.none
            : SystemMouseCursors.basic,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isDesktop() && !isTablet())
              Container(
                padding: const EdgeInsets.only(left: 10.0, bottom: 10),
                child: Text(
                  '${durationToString(playerController.playback.currentPosition)} / ${durationToString(playerController.playback.duration)}',
                  style: const TextStyle(
                    color: MediaChromeColors.foreground,
                    fontSize: 12.0,
                    fontFeatures: [
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ProgressBar(
                thumbRadius: 8,
                thumbGlowRadius: 18,
                timeLabelLocation: isTablet()
                    ? TimeLabelLocation.sides
                    : TimeLabelLocation.none,
                timeLabelTextStyle: const TextStyle(
                  color: MediaChromeColors.foreground,
                  fontSize: 12.0,
                  fontFeatures: [
                    FontFeature.tabularFigures(),
                  ],
                ),
                progress: playerController.playback.currentPosition,
                buffered: playerController.playback.buffer,
                total: playerController.playback.duration,
                onSeek: widget.handleProgressBarSeek,
                onDragStart: (_) => widget.handleProgressBarDragStart(),
                onDragUpdate: (details) => playerController.seeking
                    .updateInteractiveSeek(details.timeStamp),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  IconButton(
                    tooltip: playerController.playback.playing ? '暂停' : '播放',
                    onPressed: () => playerController.playOrPause(),
                    icon: PlayPauseIcon(
                      iconColor: MediaChromeColors.foreground,
                      playing: playerController.playback.playing,
                    ),
                  ),

                  // 上一集 / 下一集（当前线路内切换，结构化进入时显示）
                  if (videoPageController.sources.isNotEmpty) ...[
                    IconButton(
                      color: MediaChromeColors.foreground,
                      tooltip: '上一集',
                      onPressed: videoPageController.hasPreviousEpisode
                          ? () {
                              videoPageController.playAdjacentEpisode(
                                -1,
                                playerController: playerController,
                              );
                            }
                          : null,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    IconButton(
                      color: MediaChromeColors.foreground,
                      tooltip: '下一集',
                      onPressed: videoPageController.hasNextEpisode
                          ? () {
                              videoPageController.playAdjacentEpisode(
                                1,
                                playerController: playerController,
                              );
                            }
                          : null,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],

                  if (isDesktop())
                    Container(
                      padding: const EdgeInsets.only(left: 10.0),
                      child: Text(
                        '${durationToString(playerController.playback.currentPosition)} / ${durationToString(playerController.playback.duration)}',
                        style: const TextStyle(
                          color: MediaChromeColors.foreground,
                          fontSize: 16.0,
                          fontFeatures: [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                  Expanded(child: SizedBox.shrink()),
                  // 超分辨率
                  PlayerPanelHoldMenuAnchor(
                    acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
                    consumeOutsideTap: true,
                    builder: (BuildContext context, MenuController controller,
                        Widget? child) {
                      return TextButton(
                        onPressed: () {
                          if (controller.isOpen) {
                            controller.close();
                          } else {
                            controller.open();
                          }
                        },
                        child: const Text(
                          '超分辨率',
                          style: TextStyle(color: MediaChromeColors.foreground),
                        ),
                      );
                    },
                    menuChildren: [
                      for (final mode in SuperResolutionMode.values)
                        MenuItemButton(
                          onPressed: () =>
                              widget.handleSuperResolutionChange(mode),
                          child: Container(
                            height: 48,
                            constraints: BoxConstraints(minWidth: 112),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                mode.label,
                                style: TextStyle(
                                  color: playerController
                                              .playback.superResolutionMode ==
                                          mode
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  // 倍速播放
                  PlayerPanelHoldMenuAnchor(
                    acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
                    consumeOutsideTap: true,
                    builder: (BuildContext context, MenuController controller,
                        Widget? child) {
                      return TextButton(
                        onPressed: () {
                          if (controller.isOpen) {
                            controller.close();
                          } else {
                            controller.open();
                          }
                        },
                        child: Text(
                          playerController.playback.playerSpeed == 1.0
                              ? '倍速'
                              : '${playerController.playback.playerSpeed}x',
                          style: const TextStyle(color: MediaChromeColors.foreground),
                        ),
                      );
                    },
                    menuChildren: [
                      for (final double i
                          in defaultPlaySpeedList) ...<MenuItemButton>[
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
                                  color: i ==
                                          playerController.playback.playerSpeed
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  PlayerPanelHoldMenuAnchor(
                    acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
                    consumeOutsideTap: true,
                    builder: (BuildContext context, MenuController controller,
                        Widget? child) {
                      return IconButton(
                        onPressed: () {
                          if (controller.isOpen) {
                            controller.close();
                          } else {
                            controller.open();
                          }
                        },
                        icon: const Icon(
                          Icons.aspect_ratio_rounded,
                          color: MediaChromeColors.foreground,
                        ),
                        tooltip: '视频比例',
                      );
                    },
                    menuChildren: [
                      for (final aspectRatioMode in PlayerAspectRatio.values)
                        MenuItemButton(
                          onPressed: () => playerController
                              .panel.aspectRatioMode = aspectRatioMode,
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
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  // 非桌面端恒为全屏，不提供全屏切换按钮。
                  isDesktop()
                      ? IconButton(
                          color: MediaChromeColors.foreground,
                          icon: Icon(videoPageController.isFullscreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded),
                          tooltip:
                              videoPageController.isFullscreen ? '退出全屏' : '全屏',
                          onPressed: () {
                            widget.handleFullscreen();
                          },
                        )
                      // 非桌面端：锁定/解锁屏幕方向
                      : IconButton(
                          color: MediaChromeColors.foreground,
                          icon: Icon(
                            videoPageController.isOrientationLocked
                                ? Icons.screen_lock_rotation
                                : Icons.screen_rotation,
                          ),
                          tooltip: videoPageController.isOrientationLocked
                              ? '解锁屏幕方向'
                              : '锁定屏幕方向',
                          onPressed: () {
                            videoPageController.toggleOrientationLock(
                              MediaQuery.orientationOf(context),
                            );
                          },
                        ),
                ],
              ),
            ),
            if (isTablet() || isDesktop()) const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget get topControlWidget {
    return EmbeddedNativeControlArea(
      requireOffset: !videoPageController.isFullscreen,
      child: SafeArea(
        top: false,
        bottom: false,
        left: videoPageController.isFullscreen,
        right: videoPageController.isFullscreen,
        child: PlayerPanelHoldMouseRegion(
          acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
          cursor: (videoPageController.isFullscreen &&
                  !playerController.panel.showVideoController)
              ? SystemMouseCursors.none
              : SystemMouseCursors.basic,
          child: Row(
            children: [
              IconButton(
                color: MediaChromeColors.foreground,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: '返回',
                onPressed: () {
                  widget.onBackPressed(context);
                },
              ),
              Expanded(
                child: dtb.DragToMoveArea(
                  child: Text(
                    videoPageController.videoTitle,
                    style: TextStyle(
                      color: MediaChromeColors.foreground,
                      fontSize:
                          Theme.of(context).textTheme.titleMedium!.fontSize,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
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
              // 下载当前视频（离线播放时不提供下载入口）
              if (!videoPageController.isOfflineMode) _buildDownloadButton(),
              if ((isDesktop() && !videoPageController.isFullscreen) ||
                  Platform.isAndroid)
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
                  icon: const Icon(
                    Icons.picture_in_picture,
                    color: MediaChromeColors.foreground,
                  ),
                ),
              PlayerPanelHoldMenuAnchor(
                acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
                consumeOutsideTap: true,
                builder: (BuildContext context, MenuController controller,
                    Widget? child) {
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
                      RemotePlay()
                          .castVideo(playerController.videoUrl)
                          .whenComplete(() {
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
                            TimedShutdownService().start(minutes,
                                onExpired: widget.pauseForTimedShutdown);
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
                                  color: TimedShutdownService().setMinutes ==
                                          minutes
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget get leftControlWidget {
    return SafeArea(
      top: false,
      bottom: false,
      left: videoPageController.isFullscreen,
      right: videoPageController.isFullscreen,
      child: Column(
        children: [
          const Spacer(),
          (playerController.panel.lockPanel)
              ? Container()
              : IconButton(
                  icon: const Icon(
                    Icons.photo_camera_outlined,
                    color: MediaChromeColors.foreground,
                  ),
                  tooltip: '截图',
                  onPressed: () {
                    widget.handleScreenShot();
                  },
                ),
          IconButton(
            icon: Icon(
              playerController.panel.lockPanel
                  ? Icons.lock_outline
                  : Icons.lock_open,
              color: MediaChromeColors.foreground,
            ),
            tooltip: playerController.panel.lockPanel ? '解锁面板' : '锁定面板',
            onPressed: () {
              playerController.panel.lockPanel =
                  !playerController.panel.lockPanel;
            },
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

/// 播放器面板内下载按钮所需的上下文：记录 + 当前剧集 + 控制器
class _DownloadContext {
  final DownloadRecord record;
  final DownloadEpisode episode;
  final DownloadController downloadController;

  _DownloadContext({
    required this.record,
    required this.episode,
    required this.downloadController,
  });
}
