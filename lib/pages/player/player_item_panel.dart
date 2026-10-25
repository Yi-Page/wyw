import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wyw/bean/styles/media_chrome_colors.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/widget/kazumi_menu.dart';
import 'package:wyw/bean/widget/play_pause_icon.dart';
import 'package:wyw/pages/player/player_adjustment_hud.dart';
import 'package:wyw/pages/player/danmaku_panel_button.dart';
import 'package:wyw/pages/player/player_transport_bar.dart';
import 'package:wyw/pages/player/player_screenshot_controls.dart';
import 'package:wyw/bean/widget/embedded_native_control_area.dart';
import 'package:wyw/pages/player/player_panel_hold.dart';
import 'package:wyw/pages/video/video_controller.dart';
import 'package:wyw/pages/player/player_controller.dart';
import 'package:wyw/pages/player/skip_seconds_dialog.dart';
import 'package:wyw/services/platform/screen_orientation.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
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
    required this.panelVisibilityController,
    required this.acquirePlayerPanelHold,
    required this.skipOP,
    required this.pauseForTimedShutdown,
    this.disableAnimations = false,
    this.splitPanelVisible = false,
    this.toggleSplitPanel,
    required this.showScreenshotCandidates,
  });

  final PlayerController playerController;
  final void Function(BuildContext) onBackPressed;
  final Future<void> Function(double) setPlaybackSpeed;
  final void Function() handleFullscreen;
  final void Function() handleScreenShot;
  final VoidCallback showScreenshotCandidates;
  final VoidCallback handleProgressBarDragStart;
  final Future<void> Function(Duration duration) handleProgressBarSeek;
  final AnimationController panelVisibilityController;
  final PlayerPanelHold Function() acquirePlayerPanelHold;
  final void Function() skipOP;
  final VoidCallback pauseForTimedShutdown;
  final bool disableAnimations;

  /// 分屏面板当前是否展开（决定 ⚙ 的选中态）。
  final bool splitPanelVisible;

  /// 开合分屏面板。
  final VoidCallback? toggleSplitPanel;

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

  /// 弹幕开关按钮（顶栏常驻，宽窄屏都渲染）。
  ///
  /// 未匹配时点击 / 已匹配时长按都打开分屏面板的「弹幕」tab（选择动线在那里）；
  /// 其余情况单击开关弹幕。它与面板「弹幕设置」tab 的总开关读同一个
  /// `danmaku.danmakuOn`，天然双向同步。
  Widget _buildDanmakuButton() {
    return DanmakuPanelButton(playerController: playerController);
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
    // 面板布局只由「可用宽度」决定，不看横竖屏：分屏、桌面小窗、PiP 也是窄的，
    // 按宽度一次覆盖；用 textScaler 换算保证无障碍大字号下阈值同步放大。
    return LayoutBuilder(
      builder: (context, constraints) => _buildPanel(
        constraints.maxWidth < MediaQuery.textScalerOf(context).scale(600),
      ),
    );
  }

  /// [compact] 为真即「窄屏」（手机竖屏、分屏、小窗、PiP），此时顶/底栏都走精简布局。
  Widget _buildPanel(bool compact) {
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
        // 三个 HUD 只在交互瞬间出现且内容持续在变，整块从语义树摘掉
        // （seek 拖拽、倍速、音量亮度调整对读屏没有逐帧朗读的意义）。
        Positioned(
          top: 25,
          child: ExcludeSemantics(
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
        ),
        Positioned(
          top: 25,
          child: ExcludeSemantics(
            child: Observer(builder: (context) {
              return PlayerSpeedHud(
                visible: playerController.panel.showPlaySpeed,
                speed: playerController.playback.playerSpeed,
                disableAnimations: widget.disableAnimations,
              );
            }),
          ),
        ),
        Positioned(
          top: 25,
          child: ExcludeSemantics(
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
        ),
        // 右侧竖排（截图 / 面板锁定）只在「非桌面 + 全屏 + 非窄屏」出现：
        // 窄屏上这两个图标会挤在画面右缘，Kazumi 也是这么砍的。
        (compact || isDesktop() || !videoPageController.isFullscreen)
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
                        ? _leftControlWidget()
                        : SlideTransition(
                            position: leftOffsetAnimation,
                            child: _leftControlWidget()),
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
                  ? _topControlWidget(compact)
                  : SlideTransition(
                      position: topOffsetAnimation,
                      child: _topControlWidget(compact)),
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
                  ? _bottomControlWidget(compact)
                  : SlideTransition(
                      position: bottomOffsetAnimation,
                      child: _bottomControlWidget(compact)),
            );
          }),
        ),
      ],
    );
  }

  /// 底栏。
  ///
  /// 布局交给 [PlayerTransportBar]：窄屏单行（播放 + 进度 + 时间 + 方向锁定/全屏），
  /// 宽屏多行并把上一集/下一集放在进度条下面一行。窄屏不放上一集/下一集
  /// ——一行里塞 6 个控件会把进度条压得没法拖，切集走顶栏的选集面板。
  ///
  /// 底栏只留播放相关：原先宽屏那一簇「超分/倍速/比例」MenuAnchor 已在 P6 退场，
  /// 分别由面板「画面」tab（超分/比例）与「播放」tab（倍速）承载。
  Widget _bottomControlWidget(bool compact) {
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
        child: PlayerTransportBar(
          compact: compact,
          timePlacement: PlayerTimeLabelPlacement.forViewport(
            MediaQuery.sizeOf(context),
            desktop: isDesktop(),
          ),
          playPause: IconButton(
            tooltip: playerController.playback.playing ? '暂停' : '播放',
            onPressed: () => playerController.playOrPause(),
            icon: PlayPauseIcon(
              iconColor: MediaChromeColors.foreground,
              playing: playerController.playback.playing,
            ),
          ),
          nextEpisode: _adjacentEpisodeButtons(),
          progressBuilder: (location) => Observer(
            builder: (context) => ProgressBar(
              thumbRadius: 8,
              thumbGlowRadius: 18,
              timeLabelLocation: location,
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
          timeLabel: ExcludeSemantics(
            // 时间每秒都在变，从语义树摘掉：Windows 无障碍桥对持续变化的语义
            // 节点会刷 AXTree 更新失败日志（引擎 bug，无害但刷屏），而读屏用户
            // 也不需要逐秒朗读时间。
            child: Observer(
              builder: (context) => Text(
                '${durationToString(playerController.playback.currentPosition)} / ${durationToString(playerController.playback.duration)}',
                style: TextStyle(
                  color: MediaChromeColors.foreground,
                  fontSize: !compact && isDesktop() ? 16.0 : 12.0,
                  fontFeatures: const [
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
          ),
          // 宽屏时这一槽位放「切集之后的额外控件」；超分/倍速/比例退场后
          // 没有内容，留空（`Expanded` 仍会把全屏按钮顶到最右）。
          controls: const SizedBox.shrink(),
          fullscreen: _orientationOrFullscreenButton(),
        ),
      ),
    );
  }

  /// 上一集 / 下一集（当前线路内切换，结构化进入时才有）。
  ///
  /// transport bar 只给一个 `nextEpisode` 槽位，这里把两个按钮打包成一个 widget；
  /// 窄屏分支不会渲染它，所以窄屏不需要为它腾空间。
  Widget _adjacentEpisodeButtons() {
    if (videoPageController.sources.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
    );
  }

  /// 桌面端提供全屏切换；非桌面端提供屏幕方向（三档策略 + 横屏切对侧）。
  Widget _orientationOrFullscreenButton() {
    if (!isDesktop()) {
      return _OrientationPolicyButton(
        acquirePlayerPanelHold: widget.acquirePlayerPanelHold,
      );
    }
    return IconButton(
      color: MediaChromeColors.foreground,
      icon: Icon(videoPageController.isFullscreen
          ? Icons.fullscreen_exit_rounded
          : Icons.fullscreen_rounded),
      tooltip: videoPageController.isFullscreen ? '退出全屏' : '全屏',
      onPressed: () {
        widget.handleFullscreen();
      },
    );
  }

  /// 顶栏。
  ///
  /// 控件分配规则（P5/P6 收编后）：
  ///   - **窄屏**：返回 / 拖动区 / 跳过 / 弹幕开关 / 选集 / ⚙ 面板；
  ///   - **宽屏**：返回 / 标题 / 跳过 / 截图 / 弹幕开关 / 选集 / ⚙ 面板；
  ///   - 其余低频项（超分/倍速/比例/定时关闭/投屏/外部播放/下载/重新解析/
  ///     弹幕设置/画面调节/视频详情）一律由分屏面板的 tab 承载——顶栏不再加东西，
  ///     「更多」菜单与顶栏下载按钮已在 P6 退场（全仓不再有第二份入口）。
  ///
  /// 窄屏中间用空白拖动区而不是标题：一行放不下标题，留个拖动窗口更有用。
  Widget _topControlWidget(bool compact) {
    return EmbeddedNativeControlArea(
      requireOffset: compact || !videoPageController.isFullscreen,
      child: SafeArea(
        top: false,
        bottom: false,
        left: !compact && videoPageController.isFullscreen,
        right: !compact && videoPageController.isFullscreen,
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
                  child: compact
                      ? const SizedBox(height: 40)
                      : Text(
                          videoPageController.videoTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: MediaChromeColors.foreground,
                            fontSize: Theme.of(context)
                                .textTheme
                                .titleMedium!
                                .fontSize,
                          ),
                        ),
                ),
              ),
              // 跳过
              forwardIcon(),
              // 截图（仅桌面端）：截取当前画面 + 带数量徽标的候选挑选入口
              if (isDesktop())
                PlayerScreenshotControls(
                  controller: playerController.screenshots,
                  onCapture: widget.handleScreenShot,
                  onReview: widget.showScreenshotCandidates,
                ),
              // 弹幕开关：两种宽度都常驻（窄屏原来靠「更多」菜单下沉，该菜单
              // 已随面板退场；总开关与面板「弹幕」tab 读同一个 observable）。
              _buildDanmakuButton(),
              // 选集/线路入口已收归面板「选集」tab（顶栏不再放选集按钮，
              // 视频页的侧栏/竖屏弹窗也一并退场）。
              // 下载/合流入口已随顶栏下载按钮退场：面板「选集」tab 的集列表
              // 提供逐集下载按钮与状态（P2 落地）。
              // 分屏面板开关：收编散落功能的唯一入口（播放器顶栏只留播放相关）。
              if (widget.toggleSplitPanel != null)
                IconButton(
                  color: widget.splitPanelVisible
                      ? Theme.of(context).colorScheme.primary
                      : MediaChromeColors.foreground,
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: widget.splitPanelVisible ? '收起面板' : '打开面板',
                  onPressed: widget.toggleSplitPanel,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 画面右侧竖排：截图 + 面板锁定（只在「非桌面 + 全屏 + 非窄屏」出现）。
  Widget _leftControlWidget() {
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

/// 播放页底栏的屏幕方向按钮。
///
/// 状态完全取自 [ScreenOrientationService] 的**真实生效策略**（不再有页面局部
/// bool）：图标/提示就是当前方向，菜单里三档 + 横屏左右随时可切对侧。
/// 菜单展开期间向父级借一个面板 hold，避免控制栏在菜单还开着时自动隐藏。
class _OrientationPolicyButton extends StatefulWidget {
  const _OrientationPolicyButton({required this.acquirePlayerPanelHold});

  final PlayerPanelHold Function() acquirePlayerPanelHold;

  @override
  State<_OrientationPolicyButton> createState() =>
      _OrientationPolicyButtonState();
}

class _OrientationPolicyButtonState extends State<_OrientationPolicyButton> {
  final ScreenOrientationService _orientation =
      ScreenOrientationService.instance;
  PlayerPanelHold? _hold;

  @override
  void dispose() {
    _releaseHold();
    super.dispose();
  }

  void _acquireHold() {
    if (_hold?.isReleased == false) {
      return;
    }
    _hold = widget.acquirePlayerPanelHold();
  }

  void _releaseHold() {
    _hold?.release();
    _hold = null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _orientation,
      builder: (context, _) {
        final policy = _orientation.policy;
        final side = _orientation.landscapeSide;
        return KazumiMenuButton(
          onOpen: _acquireHold,
          onClose: _releaseHold,
          builder: (context, toggle) => IconButton(
            color: MediaChromeColors.foreground,
            tooltip: orientationPolicyTooltip(policy, side),
            onPressed: toggle,
            icon: Icon(orientationPolicyIcon(policy)),
          ),
          menuChildren: [
            for (final item in orientationPolicyMenuItems(policy, side))
              KazumiMenuItem(
                label: item.label,
                leadingIcon: Icon(item.icon),
                selected: item.selected,
                requestFocusOnHover: false,
                onPressed: () => unawaited(
                  _orientation.updateActivePolicy(item.policy, side: item.side),
                ),
              ),
          ],
        );
      },
    );
  }
}
