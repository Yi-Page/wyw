import 'dart:async';
import 'dart:io';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:wyw/bean/styles/media_chrome_colors.dart';
import 'package:wyw/modules/danmaku/danmaku_module.dart';
import 'package:wyw/modules/danmaku/danmaku_shield_rule.dart';
import 'package:wyw/pages/player/player_item_panel.dart';
import 'package:wyw/pages/player/player_split_panel.dart';
import 'package:wyw/pages/player/split_tabs/split_tab_host.dart';
import 'package:wyw/pages/player/widgets/player_split_layout.dart';
import 'package:wyw/pages/player/controller/player_super_resolution.dart';
import 'package:wyw/pages/player/controller/video_filter_controller.dart';
import 'package:wyw/pages/player/player_panel_hold.dart';
import 'package:wyw/pages/player/player_pointer_interaction.dart';
import 'package:wyw/pages/player/player_screenshot_feedback_overlay.dart';
import 'package:wyw/pages/player/player_screenshot_sheet.dart';
import 'package:wyw/pages/player/controller/player_screenshot_controller.dart';
import 'package:wyw/services/player/timed_shutdown_service.dart';
import 'package:wyw/utils/constants.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/player/pip_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:wyw/pages/player/player_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/video/video_controller.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/pages/player/player_item_surface.dart';
import 'package:mobx/mobx.dart' as mobx;
import 'package:saver_gallery/saver_gallery.dart';
import 'package:wyw/services/player/audio_controller.dart';
import 'package:wyw/utils/device.dart';
import 'package:wyw/services/platform/player_menu_service.dart';

class PlayerItem extends StatefulWidget {
  const PlayerItem({
    super.key,
    required this.playerController,
    required this.onBackPressed,
    required this.keyboardFocus,
    required this.pauseForTimedShutdown,
    this.disableAnimations = false,
    this.onEpisodeSelected,
    this.onDownloadEpisode,
  });

  final PlayerController playerController;
  final void Function(BuildContext) onBackPressed;
  final FocusNode keyboardFocus;
  final bool disableAnimations;
  final VoidCallback pauseForTimedShutdown;

  /// 面板「选集」tab 的切集回调：`(sourceIndex, episodeIndex)`，0 基。
  final void Function(int sourceIndex, int episodeIndex)? onEpisodeSelected;

  /// 面板「选集」tab 的「缓存剧集」入口（按线路）。
  final void Function(int sourceIndex)? onDownloadEpisode;

  @override
  State<PlayerItem> createState() => _PlayerItemState();
}

class _PlayerItemState extends State<PlayerItem>
    with WindowListener, WidgetsBindingObserver, TickerProviderStateMixin {
  late final PlayerController playerController;
  final VideoPageController videoPageController = inject<VideoPageController>();
  AudioController get _audioController => playerController.audioController;
  late Map<String, List<String>> keyboardShortcuts;
  late List<String> keyboardActionsNeedLongPress;
  late Map<String, void Function()> keyboardActions;

  // 硬件解码
  late bool haEnable;
  late bool autoPlayNext;
  late bool backgroundPlayback;
  late bool brightnessVolumeGesture;

  // 播放器控制面板无交互后自动隐藏所需时间 （单位：毫秒）
  late int playerControllerLayerDisappearTime;

  Timer? hideTimer;
  Timer? playerTimer;
  Timer? mouseScrollerTimer;
  Timer? _adjustmentHudHideTimer;

  /// 视频区（分屏后是容器左侧/上侧那块，比窗口窄）。
  ///
  /// 手势灵敏度、HUD 判据、弹幕 `compactLayout` 都必须按**它**算，而不是整窗
  /// `MediaQuery`（v1 遗留：视频区被面板压窄后 seek 灵敏度仍按窗口宽算）。
  final GlobalKey _videoRegionKey = GlobalKey();
  final Set<PlayerPanelHold> _playerPanelHolds = <PlayerPanelHold>{};
  PlayerPanelHold? _progressBarDragHold;
  PointerDeviceKind? _lastTapPointerKind;
  PointerDeviceKind? _lastDoubleTapPointerKind;

  late final AnimationController _panelVisibilityController;
  late final AnimationController _screenshotFeedbackController;
  late final Animation<double> _screenshotFeedbackAnimation;

  /// 截图候选（照 Kazumi：连续截图 → 挑选面板 → 批量保存）。
  late final PlayerScreenshotController _screenshots =
      playerController.screenshots;
  bool _screenshotSheetOpen = false;

  double lastPlayerSpeed = 1.0;
  late double longPressPlaySpeed;
  int episodeNum = 0;
  bool? _lastPipPlaying;
  late mobx.ReactionDisposer _playerSizeListener;

  late mobx.ReactionDisposer _fullscreenListener;
  late mobx.ReactionDisposer _pipListener;

  /// 处理 Android/iOS 应用后台或熄屏
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused &&
        !backgroundPlayback &&
        playerController.playback.mediaPlayer != null &&
        playerController.playback.playerPlaying) {
      try {
        await playerController.pause(enableSync: false);
      } catch (e) {
        WywLogger().d('${LogTag.player} 应用切后台时暂停播放失败（已忽略）', error: e);
      }
      return;
    }
  }

  Future<void> _syncAndroidAutoEnterPIPSetting() async {
    if (!Platform.isAndroid) {
      return;
    }
    final bool autoEnterPIPEnabled =
        GStorage.getSetting(SettingsKeys.androidAutoEnterPIP);
    try {
      await PipUtils.setAndroidAutoEnterPIPEnabled(autoEnterPIPEnabled);
    } catch (e) {
      WywLogger().w(
        '${LogTag.player} 同步 Android 自动进入画中画设置失败 enabled=$autoEnterPIPEnabled',
        error: e,
      );
    }
  }

  Future<void> _syncAndroidPIPPlayerPageState(bool inPlayerPage) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await PipUtils.setAndroidPIPInPlayerPage(inPlayerPage);
    } catch (e) {
      WywLogger().w(
        '${LogTag.player} 同步 Android 画中画播放页状态失败 inPlayerPage=$inPlayerPage',
        error: e,
      );
    }
  }

  Future<void> _updateAndroidPIPActions({bool force = false}) async {
    if (!Platform.isAndroid) {
      return;
    }
    final bool playing = playerController.playback.playing;
    if (!force && _lastPipPlaying == playing) {
      return;
    }

    _lastPipPlaying = playing;
    await PipUtils.updateAndroidPIPActions(
      playing: playing,
      width: playerController.debug.playerWidth,
      height: playerController.debug.playerHeight,
    );
  }

  Future<void> _syncPIPAspectWhenVideoSizeReady() async {
    if (playerController.debug.playerWidth <= 0 ||
        playerController.debug.playerHeight <= 0) {
      return;
    }
    if (Platform.isAndroid) {
      await _updateAndroidPIPActions(force: true);
      return;
    }
    if (isDesktop() && videoPageController.isPip) {
      await PipUtils.enterDesktopPIPWindow(
        width: playerController.debug.playerWidth,
        height: playerController.debug.playerHeight,
      );
    }
  }

  void _loadShortcuts() {
    keyboardShortcuts = {};
    defaultShortcuts.forEach((key, defaultValue) {
      keyboardShortcuts[key] = GStorage.getStringListSettingByName(
        'shortcut_$key',
        defaultValue: defaultValue,
      );
    });
  }

  void _initKeyboardActions() {
    //需要实现长按的功能列表。
    keyboardActionsNeedLongPress = ['forward'];
    //快捷键功能对应表
    keyboardActions = {
      'playorpause': () => playerController.playOrPause(),
      'forward': () async => handleShortcutForwardDown(),
      'rewind': () async => handleShortcutRewind(),
      'volumeup': () async => handleShortcutVolumeChange('up'),
      'volumedown': () async => handleShortcutVolumeChange('down'),
      'togglemute': () async => handleShortcutVolumeChange('mute'),
      'fullscreen': () => handleShortcutFullscreen(),
      'screenshot': () async => handleScreenshot(),
      'toggledanmaku': () => playerController.danmaku
          .setDanmakuEnabled(!playerController.danmaku.danmakuOn),
      // 分屏面板开合（Esc 在 handleShortcutDown 里先退二级页再收面板）。
      'togglesplitpanel': () => playerController.panel.toggleSplitPanel(),
      'skip': () async => skipOP(),
      'exitfullscreen': () => handleShortcutExitFullscreen(),
      'speed1': () async => setPlaybackSpeed(1.0),
      'speed2': () async => setPlaybackSpeed(2.0),
      'speed3': () async => setPlaybackSpeed(3.0),
      'speedup': () async => handleSpeedChange('up'),
      'speeddown': () async => handleSpeedChange('down'),
      // 开始对应长按功能
      // 如需对应长按功能，例如对功能'func'对应长按，请分别添加'funcRepeat'和'funcUp'。
      'forwardRepeat': () async => handleShortcutForwardRepeat(),
      'forwardUp': () async => handleShortcutForwardUp(),
    };
  }

  //初始化播放器菜单
  void _initPlayerMenu() {
    PlayerMenuService.initialize(keyboardActions);
  }

  //销毁播放器菜单
  void _disposePlayerMenu() {
    PlayerMenuService.dispose();
  }

  //快捷键按下
  bool handleShortcutDown(String keyLabel) {
    // Esc（桌面）：先退二级页，再收面板；面板没开时不拦截按键。
    if (keyLabel == 'Escape') {
      final panel = playerController.panel;
      if (!panel.splitPanelVisible) {
        return false;
      }
      if (panel.splitPanelSubPage != null) {
        panel.closeSplitPanelSubPage();
      } else {
        panel.closeSplitPanel();
      }
      return true;
    }
    for (final entry in keyboardShortcuts.entries) {
      final func = entry.key;
      final keys = entry.value;
      if (keys.contains(keyLabel)) {
        final action = keyboardActions[func];
        if (action != null) {
          action();
          return true;
        }
      }
    }
    return false;
  }

  // 快捷键长按
  bool handleShortcutLongPress(String keyLabel, String mode) {
    for (final func in keyboardActionsNeedLongPress) {
      final keys = keyboardShortcuts[func];
      if (keys?.contains(keyLabel) == true) {
        final action = keyboardActions[func + mode];
        if (action != null) {
          action();
          return true;
        }
      }
    }
    return false;
  }

  Future<void> handleShortcutRewind() async {
    try {
      await _seekWithPlayerTimer(
        () => playerController.seekBy(
          Duration(seconds: -playerController.playback.arrowKeySkipTime),
        ),
      );
    } catch (e) {
      WywLogger().e('${LogTag.player} 快捷键后退 seek 失败', error: e);
    }
  }

  Future<void> handleShortcutForwardDown() async {
    lastPlayerSpeed = playerController.playback.playerSpeed;
  }

  Future<void> handleShortcutForwardRepeat() async {
    final double defaultShortcutForwardPlaySpeed =
        GStorage.getSetting(SettingsKeys.defaultShortcutForwardPlaySpeed);
    if (playerController.playback.playerSpeed <
        defaultShortcutForwardPlaySpeed) {
      playerController.panel.showPlaySpeed = true;
      setPlaybackSpeed(defaultShortcutForwardPlaySpeed);
    }
  }

  Future<void> handleShortcutForwardUp() async {
    if (playerController.panel.showPlaySpeed) {
      playerController.panel.showPlaySpeed = false;
      setPlaybackSpeed(lastPlayerSpeed);
    } else {
      try {
        await _seekWithPlayerTimer(
          () => playerController.seekBy(
            Duration(seconds: playerController.playback.arrowKeySkipTime),
          ),
        );
      } catch (e) {
        WywLogger().e('${LogTag.player} 快捷键快进 seek 失败', error: e);
      }
    }
  }

  //全屏快捷键动作
  void handleShortcutFullscreen() {
    if (!videoPageController.isPip) handleFullscreen();
  }

  //退出全屏快捷键动作
  void handleShortcutExitFullscreen() {
    // 非桌面端恒为全屏，不存在退出全屏。
    if (!isDesktop()) {
      return;
    }
    if (videoPageController.isFullscreen) {
      videoPageController.exitFullScreen();
    } else if (!Platform.isMacOS) {
      playerController.pause();
      windowManager.hide();
    }
  }

  void _toggleVideoController() {
    if (playerController.panel.showVideoController) {
      hideVideoController();
    } else {
      displayVideoController();
    }
  }

  void _handleTap(PointerDeviceKind? pointerKind) {
    if (shouldToggleControllerOnPrimaryTap(
      isDesktop: isDesktop(),
      pointerKind: pointerKind,
    )) {
      _toggleVideoController();
      return;
    }
    playerController.playOrPause();
  }

  void _handleDoubleTap(PointerDeviceKind? pointerKind) {
    if (shouldToggleFullscreenOnDoubleTap(
      isDesktop: isDesktop(),
      isPip: videoPageController.isPip,
      pointerKind: pointerKind,
    )) {
      handleFullscreen();
      return;
    }
    playerController.playOrPause();
  }

  void _handleMouseScroller() {
    playerController.panel.showVolume = true;
    mouseScrollerTimer?.cancel();
    mouseScrollerTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        playerController.panel.showVolume = false;
      }
      mouseScrollerTimer = null;
    });
  }

  void _cancelAdjustmentHudHideTimer() {
    _adjustmentHudHideTimer?.cancel();
    _adjustmentHudHideTimer = null;
  }

  void _showVolumeAdjustmentHud() {
    _cancelAdjustmentHudHideTimer();
    playerController.panel.showBrightness = false;
    playerController.panel.showVolume = true;
  }

  void _showBrightnessAdjustmentHud() {
    _cancelAdjustmentHudHideTimer();
    playerController.panel.showVolume = false;
    playerController.panel.showBrightness = true;
  }

  void _scheduleAdjustmentHudHide({
    Duration delay = const Duration(milliseconds: 650),
  }) {
    _cancelAdjustmentHudHideTimer();
    _adjustmentHudHideTimer = Timer(delay, () {
      if (mounted) {
        playerController.panel.showVolume = false;
        playerController.panel.showBrightness = false;
      }
      _adjustmentHudHideTimer = null;
    });
  }

  void _finishAdjustmentGesture() {
    if (!brightnessVolumeGesture) {
      return;
    }
    if (playerController.panel.volumeSeeking) {
      playerController.panel.volumeSeeking = false;
      unawaited(playerController.finishVolumeGesture());
    }
    if (playerController.panel.brightnessSeeking) {
      playerController.panel.brightnessSeeking = false;
    }
    _scheduleAdjustmentHudHide();
  }

  Future<void> skipOP() async {
    await playerController.seekBy(
      Duration(seconds: playerController.playback.buttonSkipTime),
    );
  }

  Future<void> _bindAudioService() async {
    try {
      await _audioController.bindCallbacks(
        onPlay: () => playerController.play(),
        onPause: () => playerController.pause(),
        onSeek: (position) => playerController.seek(position),
      );
      _syncAudioServiceState();
    } catch (e) {
      WywLogger().w('${LogTag.player} 绑定音频服务回调失败', error: e);
    }
  }

  void _syncAudioServiceState() {
    try {
      if (playerController.playback.duration <= Duration.zero) return;

      unawaited(
        _audioController.updateSession(
          mediaId: videoPageController.videoUrl,
          title: videoPageController.videoUrl,
          duration: playerController.playback.duration,
          playing: playerController.playback.playing,
          loading: playerController.playback.loading,
          buffering: playerController.playback.isBuffering,
          completed: playerController.playback.completed,
          updatePosition: playerController.playback.currentPosition,
          bufferedPosition: playerController.playback.buffer,
          speed: playerController.playback.playerSpeed,
          cover: videoPageController.videoCover,
        ),
      );
    } catch (e) {
      WywLogger().w('${LogTag.player} 同步音频服务播放状态失败', error: e);
    }
  }

  void _handleFullscreenChange(BuildContext context) async {
    playerController.panel.lockPanel = false;
    _releasePlayerPanelHolds();
  }

  void handleProgressBarDragStart() {
    _beginInteractiveSeek();
    _syncAudioServiceState();
    _progressBarDragHold = acquirePlayerPanelHold();
  }

  Future<void> handleProgressBarSeek(Duration duration) async {
    if (!playerController.seeking.updateInteractiveSeek(duration)) {
      await playerController.seek(duration);
      return;
    }
    await _commitInteractiveSeek();
  }

  void _beginInteractiveSeek() {
    _progressBarDragHold?.release();
    _progressBarDragHold = null;
    playerTimer?.cancel();
    playerController.seeking.beginInteractiveSeek();
  }

  Future<void> _commitInteractiveSeek() async {
    var completed = false;
    try {
      completed = await playerController.seeking.commitInteractiveSeek();
    } catch (e) {
      WywLogger().e('${LogTag.player} 提交手势 seek 失败', error: e);
    }
    if (!mounted ||
        (!completed && playerController.seeking.hasActiveInteractiveSeek)) {
      return;
    }
    _progressBarDragHold?.release();
    _progressBarDragHold = null;
    if (completed) {
      _syncAudioServiceState();
    }
    _restartPlayerTimer();
  }

  void _restartPlayerTimer() {
    playerTimer?.cancel();
    playerTimer = getPlayerTimer();
  }

  Future<void> _seekWithPlayerTimer(
    Future<void> Function() seekAction,
  ) async {
    playerTimer?.cancel();
    try {
      await seekAction();
    } finally {
      if (mounted) {
        _restartPlayerTimer();
      }
    }
  }

  //截图
  Future<void> handleScreenshot() async {
    if (!mounted) return;
    if (!isDesktop()) {
      await _saveScreenshotToGallery();
      return;
    }
    if (_screenshots.busy || _screenshotSheetOpen) return;
    final source = videoPageController.currentSourceIndex;
    final episode = videoPageController.currentEpisodeIndex;
    final player = playerController.playback.mediaPlayer;
    if (videoPageController.loading || player == null) {
      WywDialog.showToast(message: '暂未获取到画面，请等视频显示后重试');
      return;
    }
    final added = await _screenshots.capture(
      capturePng: playerController.screenshotPng,
      title: videoPageController.videoTitle,
      episode: _screenshotEpisodeLabel(source, episode),
      position: playerController.playback.playerPosition,
      isCurrent: () =>
          mounted &&
          !videoPageController.loading &&
          videoPageController.currentSourceIndex == source &&
          videoPageController.currentEpisodeIndex == episode &&
          identical(playerController.playback.mediaPlayer, player),
    );
    if (!mounted) return;
    if (added) _playScreenshotFeedback();
    if (!_screenshotSheetOpen) {
      showVideoController();
      if (!added || _screenshots.candidates.length == 1) {
        WywDialog.showToast(
          message: added
              ? '已截取画面，点击右上角图库挑选保存'
              : _screenshots.message ?? '截图失败，请重试',
          showActionButton: _screenshots.candidates.isNotEmpty,
          actionLabel: '挑选截图',
          onActionPressed: showScreenshotCandidates,
        );
      }
    }
  }

  /// 截图候选里显示的集名（取不到名字时退化成集号）。
  String _screenshotEpisodeLabel(int sourceIndex, int episodeIndex) {
    final sources = videoPageController.sources;
    if (sourceIndex >= 0 && sourceIndex < sources.length) {
      final episodes = sources[sourceIndex].episodes;
      if (episodeIndex >= 0 && episodeIndex < episodes.length) {
        final name = episodes[episodeIndex].name.trim();
        if (name.isNotEmpty) return name;
      }
    }
    return '第 ${episodeIndex + 1} 集';
  }

  /// 移动端：直接存相册（桌面端走候选 + 挑选面板）。
  Future<void> _saveScreenshotToGallery() async {
    _playScreenshotFeedback();
    try {
      final screenshot = await playerController.screenshotPng();
      if (!mounted) return;
      if (screenshot == null || screenshot.isEmpty) {
        WywDialog.showToast(message: '截图失败：未获取到图像');
        return;
      }
      final result = await SaverGallery.saveImage(
        screenshot,
        fileName: DateTime.timestamp().millisecondsSinceEpoch.toString(),
        extension: 'png',
        skipIfExists: false,
      );
      if (mounted && !result.isSuccess) {
        WywDialog.showToast(message: '截图保存失败：${result.errorMessage}');
      }
    } catch (e) {
      if (mounted) WywDialog.showToast(message: '截图失败：$e');
    }
  }

  /// 桌面端：打开截图挑选面板（期间暂停播放，关闭后按原样恢复）。
  Future<void> showScreenshotCandidates() async {
    if (!isDesktop() || !mounted || _screenshotSheetOpen || _screenshots.busy) {
      return;
    }
    _screenshotSheetOpen = true;
    final hold = acquirePlayerPanelHold();
    final player = playerController.playback.mediaPlayer;
    final source = videoPageController.currentSourceIndex;
    final episode = videoPageController.currentEpisodeIndex;
    final resume = playerController.playback.playing;
    final sleepRemaining = TimedShutdownService().remainingSecondsNotifier.value;
    final sleepDeadline = sleepRemaining > 0
        ? DateTime.now().add(Duration(seconds: sleepRemaining))
        : null;
    try {
      if (resume) await playerController.pause(enableSync: false);
      if (!mounted) return;
      await showPlayerScreenshotSheet(context, controller: _screenshots);
    } finally {
      _screenshotSheetOpen = false;
      if (mounted) {
        hold.release();
        widget.keyboardFocus.requestFocus();
        // Resume only the same local playback, respecting the sleep timer.
        if (resume &&
            identical(player, playerController.playback.mediaPlayer) &&
            videoPageController.currentSourceIndex == source &&
            videoPageController.currentEpisodeIndex == episode &&
            !videoPageController.loading &&
            (sleepDeadline == null || DateTime.now().isBefore(sleepDeadline)) &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed &&
            (ModalRoute.of(context)?.isCurrent ?? false)) {
          await playerController.play(enableSync: false);
        }
      } else {
        hold.releaseSilently();
      }
    }
  }

  void _playScreenshotFeedback() {
    if (!mounted ||
        widget.disableAnimations ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    _screenshotFeedbackController.forward(from: 0);
  }

  Future<void> handleSuperResolutionChange(SuperResolutionMode mode) async {
    if (!mounted) return;

    // mediacodec_embed 不支持超分辨率
    if (Platform.isAndroid && mode != SuperResolutionMode.off) {
      final String androidVideoRenderer =
          GStorage.getSetting(SettingsKeys.androidVideoRenderer);

      if (androidVideoRenderer == 'mediacodec_embed') {
        await WywDialog.show(builder: (context) {
          return AlertDialog(
            title: const Text('兼容性提示'),
            content: const Text('MediaCodec 渲染器不支持超分辨率功能。\n\n'
                '如需使用超分辨率，请在播放设置中将视频渲染器切换为 gpu 或 gpu-next。'),
            actions: [
              TextButton(
                onPressed: () {
                  WywDialog.dismiss();
                },
                child: const Text('确定'),
              ),
            ],
          );
        });
        return;
      }
    }

    final bool requiresPerformanceWarning = mode == SuperResolutionMode.quality;
    final bool warningDisabled = GStorage.getSetting(
      SettingsKeys.disableSuperResolutionWarning,
    );

    if (requiresPerformanceWarning && !warningDisabled) {
      bool confirmed = false;

      await WywDialog.show(builder: (context) {
        bool dontAskAgain = false;

        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('性能提示'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('启用超分辨率（质量档）可能会造成设备卡顿，是否继续？'),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: dontAskAgain,
                      onChanged: (value) =>
                          setState(() => dontAskAgain = value ?? false),
                    ),
                    const Text('下次不再询问'),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  if (dontAskAgain) {
                    await GStorage.putSetting(
                      SettingsKeys.disableSuperResolutionWarning,
                      true,
                    );
                  }
                  WywDialog.dismiss();
                },
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  confirmed = true;
                  if (dontAskAgain) {
                    await GStorage.putSetting(
                      SettingsKeys.disableSuperResolutionWarning,
                      true,
                    );
                  }
                  WywDialog.dismiss();
                },
                child: const Text('确认'),
              ),
            ],
          );
        });
      });

      if (confirmed) {
        playerController.setShader(mode);
      }
    } else {
      playerController.setShader(mode);
    }
  }

  void handleFullscreen() {
    // 非桌面端恒为全屏，无需切换。
    if (!isDesktop()) {
      return;
    }
    _handleFullscreenChange(context);
    if (videoPageController.isFullscreen) {
      videoPageController.exitFullScreen();
    } else {
      videoPageController.enterFullScreen();
    }
  }

  bool get _canHidePlayerPanel =>
      playerController.panel.canHidePlayerPanel && _playerPanelHolds.isEmpty;

  void showVideoController({bool restartHideTimer = true}) {
    _panelVisibilityController.forward();
    playerController.panel.showVideoController = true;
    if (restartHideTimer && _canHidePlayerPanel) {
      _startHideTimer();
    }
  }

  void displayVideoController() {
    showVideoController();
  }

  void hideVideoController() {
    if (!_canHidePlayerPanel) {
      return;
    }
    _panelVisibilityController.reverse();
    _cancelHideTimer();
    playerController.panel.showVideoController = false;
  }

  // All temporary panel blockers flow through this single lease registry.
  PlayerPanelHold acquirePlayerPanelHold() {
    late final PlayerPanelHold hold;
    hold = PlayerPanelHold(
      onRelease: () {
        _playerPanelHolds.remove(hold);
        if (_playerPanelHolds.isNotEmpty) {
          return;
        }
        playerController.panel.canHidePlayerPanel = true;
        _startHideTimer();
      },
    );
    _playerPanelHolds.add(hold);
    playerController.panel.canHidePlayerPanel = false;
    _cancelHideTimer();
    showVideoController(restartHideTimer: false);
    return hold;
  }

  // Fullscreen/system overlay changes can dispose menus without delivering
  // MenuAnchor.onClose, so the parent owns the emergency release path.
  void _releasePlayerPanelHolds() {
    for (final hold in _playerPanelHolds.toList()) {
      hold.releaseSilently();
    }
    _playerPanelHolds.clear();
    _progressBarDragHold = null;
    playerController.panel.canHidePlayerPanel = true;
    _startHideTimer();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await playerController.setPlaybackSpeed(speed);
  }

  Future<void> handleSpeedChange(String type) async {
    try {
      final currentSpeed = playerController.playback.playerSpeed;
      int index = defaultPlaySpeedList.indexOf(currentSpeed);
      if (type == 'up') {
        if (index < defaultPlaySpeedList.length - 1) {
          index++;
          setPlaybackSpeed(defaultPlaySpeedList[index]);
        } else {
          WywDialog.showToast(message: '已达倍速上限');
        }
      } else if (type == 'down') {
        if (index > 0) {
          index--;
          setPlaybackSpeed(defaultPlaySpeedList[index]);
        } else {
          WywDialog.showToast(message: '已达倍速下限');
        }
      }
    } catch (e, s) {
      WywLogger()
          .e('${LogTag.player} 切换倍速失败 type=$type', error: e, stackTrace: s);
    }
  }

  Future<void> handleShortcutVolumeChange(String type) async {
    try {
      switch (type) {
        case 'up':
          await playerController
              .setVolume(playerController.playback.volume + 10);
          break;
        case 'down':
          await playerController
              .setVolume(playerController.playback.volume - 10);
          break;
        case 'mute':
          await playerController.toggleMute();
          break;
        default:
          return;
      }
      _showVolumeAdjustmentHud();
      _scheduleAdjustmentHudHide(delay: const Duration(seconds: 1));
    } catch (e) {
      WywLogger().e('${LogTag.player} 快捷键调节音量失败 type=$type', error: e);
    }
  }

  Future<void> setBrightness(double value) async {
    try {
      await ScreenBrightnessPlatform.instance
          .setApplicationScreenBrightness(value);
    } catch (_) {
      // 静默可接受：手势拖动高频调用，平台不支持等失败属常态，避免日志刷屏
    }
  }

  void _startHideTimer() {
    _cancelHideTimer();
    if (!_canHidePlayerPanel) {
      return;
    }
    hideTimer =
        Timer(Duration(milliseconds: playerControllerLayerDisappearTime), () {
      if (mounted) {
        hideVideoController();
      }
      hideTimer = null;
    });
  }

  void _cancelHideTimer() {
    hideTimer?.cancel();
    hideTimer = null;
  }

  /// 弹幕画布层。
  ///
  /// `DanmakuScreen` 建好画布后把控制器回调给 [PlayerDanmakuController]，
  /// 之后投喂弹幕都走控制器，widget 树只负责提供画布与尺寸。
  /// 整层从语义树摘掉：弹幕是纯画布文字（读屏读不到），且每条进出画布都会
  /// 带动语义树，Windows 无障碍桥对高频变化的树会刷 AXTree 报错。
  Widget _buildDanmakuLayer() {
    return ExcludeSemantics(
      child: DanmakuScreen<dynamic>(
        createdController: (controller) {
          playerController.danmaku.canvasController = controller;
          // 画布刚建好时同步一次倍速：弹幕滚动时长要跟随当前播放速度。
          playerController.danmaku
              .updateDanmakuSpeed(playerController.playback.playerSpeed);
        },
        option: playerController.danmaku.resolveCanvasOption(
          compactLayout:
              (_videoViewportSize?.shortestSide ??
                  MediaQuery.sizeOf(context).shortestSide) <
              600,
        ),
      ),
    );
  }

  /// 把当前播放秒数上的弹幕投进画布。
  ///
  /// 播放位置每秒轮询一次，同一秒内的多条弹幕按索引错峰 0~999ms 发出，避免
  /// 齐刷刷糊成一片。延迟任务真正执行前要重新校验状态：跳转（generation 自增）、
  /// 暂停、缓冲、关闭弹幕，任一命中就丢弃这一条，防止跳转后旧弹幕串场。
  void _emitDanmakusForCurrentPosition() {
    final danmaku = playerController.danmaku;
    if (playerController.playback.currentPosition.inMicroseconds == 0 ||
        playerController.playback.playerPlaying != true ||
        !danmaku.danmakuOn ||
        !danmaku.hasCanvas) {
      return;
    }

    final entries = danmaku.danmakusForPlaybackPosition(
      playerController.playback.currentPosition,
    );
    final total = entries.length;
    // 每轮只取一次屏蔽词，别在循环里按条读存储。
    final shieldRules = danmaku.shieldRules;
    for (final entry in entries.asMap().entries) {
      final index = entry.key;
      final item = entry.value;
      if (!danmaku.isSourceEnabled(item)) {
        continue;
      }
      if (isDanmakuShielded(item.message, shieldRules)) {
        continue;
      }

      final color = GStorage.getSetting(SettingsKeys.danmakuColor)
          ? item.color
          : MediaChromeColors.foreground;
      final delay = DanmakuTimeline.staggerDelayMilliseconds(
        index: index,
        total: total,
      );
      final generation = danmaku.scheduledGeneration;
      Future.delayed(Duration(milliseconds: delay), () {
        if (!mounted ||
            playerController.playback.playerPlaying != true ||
            playerController.playback.playerBuffering ||
            !danmaku.danmakuOn ||
            danmaku.scheduledGeneration != generation) {
          return;
        }
        danmaku.canvasController?.addDanmaku(
          DanmakuContentItem(
            item.message,
            color: color,
            type: _danmakuItemType(item),
          ),
        );
      });
    }
  }

  /// 弹弹play 的弹幕模式：1 滚动 / 4 底部 / 5 顶部。
  DanmakuItemType _danmakuItemType(DanmakuEntry item) {
    if (item.type == 4) {
      return DanmakuItemType.bottom;
    }
    if (item.type == 5) {
      return DanmakuItemType.top;
    }
    return DanmakuItemType.scroll;
  }

  Timer getPlayerTimer() {
    return Timer.periodic(const Duration(seconds: 1), (timer) {
      playerController.syncPlaybackState();
      // 续播点：播放中每秒落盘一次（照 Kazumi）。
      // 门控与 Kazumi 一致＝播放中 + 非加载；「有没有可记录的身份」与「隐私
      // 模式」由 reporter 和仓库各自把关。
      if (playerController.playback.playerPlaying &&
          !videoPageController.loading) {
        playerController.reportPlaybackProgress();
      }
      unawaited(_updateAndroidPIPActions());
      _syncAudioServiceState();
      _emitDanmakusForCurrentPosition();
      // 设置可能在播放页存活期间被改（后台播放/画中画/从设置页返回），
      // 每秒比对一次并只在真的变化时应用到画布。
      if (mounted) {
        playerController.danmaku.syncCanvasOptionIfChanged(
          compactLayout:
              (_videoViewportSize?.shortestSide ??
                  MediaQuery.sizeOf(context).shortestSide) <
              600,
        );
      }
      // 音量相关
      if (!playerController.panel.volumeSeeking) {
        if (isDesktop()) {
          playerController.playback
              .applyExternalVolume(playerController.playback.playerVolume);
        }
      }
      // 亮度相关
      if (!Platform.isWindows &&
          !Platform.isMacOS &&
          !Platform.isLinux &&
          !playerController.panel.brightnessSeeking) {
        ScreenBrightnessPlatform.instance.application.then((value) {
          if (!mounted) return;
          playerController.panel.brightness = value;
        });
      }
    });
  }

  // 面板由 PlayerItemPanel 一份承担：它按「可用宽度 < 600」自行决定窄屏/宽屏布局，
  // 因此这里不再需要"选哪份面板"的判断（原 needFullPanel 的四个分支已被
  // LayoutBuilder 的单一宽度判据取代）。

  @override
  void onWindowRestore() {}

  @override
  void initState() {
    super.initState();
    playerController = widget.playerController;
    // 画面调节：把预设控制器的实时下发接到本播放器（切换/编辑/删除实时生效）
    VideoFilterController.instance.applyVf =
        (params) => playerController.setVideoFilter(params);
    // 弹幕默认开关：进播放页时按设置初始化；真实数据加载后（匹配到弹幕库）
    // 会以"有没有弹幕"再校正一次。
    playerController.danmaku.setDanmakuEnabled(
      GStorage.getSetting(SettingsKeys.danmakuEnabledByDefault),
    );
    _loadShortcuts();
    _initKeyboardActions();
    _initPlayerMenu();
    // 分屏面板：比例是持久化偏好，进页面时读一次（`0` = 未自定义）。
    playerController.panel.loadSplitPanelExtent();
    _fullscreenListener = mobx.reaction<bool>(
      (_) => videoPageController.isFullscreen,
      (_) {
        _handleFullscreenChange(context);
      },
    );
    _playerSizeListener = mobx.reaction<String>(
      (_) =>
          '${playerController.debug.playerWidth}:${playerController.debug.playerHeight}',
      (_) {
        unawaited(_syncPIPAspectWhenVideoSizeReady());
      },
    );
    // 画中画：进入时自动收起面板；退出不自动恢复（避免干扰）。
    _pipListener = mobx.reaction<bool>(
      (_) => videoPageController.isPip,
      (isPip) {
        if (isPip) {
          playerController.panel.closeSplitPanel();
        }
      },
    );
    if (Platform.isAndroid) {
      PipUtils.initPipHandler(
        onAction: (action) async {
          if (!mounted) return;

          switch (action) {
            case 'play_pause':
              playerController.playOrPause();
              break;

            case 'forward':
              await skipOP();
              break;
          }

          await _updateAndroidPIPActions(force: true);
        },
      );
      unawaited(_syncAndroidAutoEnterPIPSetting());
      unawaited(_syncAndroidPIPPlayerPageState(true));
      unawaited(_updateAndroidPIPActions(force: true));
    }
    WidgetsBinding.instance.addObserver(this);
    _panelVisibilityController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _screenshotFeedbackController = AnimationController(
      duration: const Duration(milliseconds: 420),
      vsync: this,
    );
    _screenshotFeedbackAnimation = CurvedAnimation(
      parent: _screenshotFeedbackController,
      curve: Curves.linear,
    );
    haEnable = GStorage.getSetting(SettingsKeys.hAenable);
    autoPlayNext = GStorage.getSetting(SettingsKeys.autoPlayNext);
    backgroundPlayback = GStorage.getSetting(SettingsKeys.backgroundPlayback);
    brightnessVolumeGesture =
        GStorage.getSetting(SettingsKeys.brightnessVolumeGesture);
    playerControllerLayerDisappearTime =
        GStorage.getSetting(SettingsKeys.playerControllerLayerDisappearTime);
    longPressPlaySpeed =
        GStorage.getSetting(SettingsKeys.defaultShortcutForwardPlaySpeed);
    unawaited(_bindAudioService());
    playerTimer = getPlayerTimer();
    windowManager.addListener(this);
    displayVideoController();
  }

  @override
  void dispose() {
    // Playback lifetime is owned by the route-scoped PlayerController.
    // This widget only detaches UI listeners and timers.
    _fullscreenListener();
    _playerSizeListener();
    _pipListener();
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    playerController.seeking.invalidateInteractiveSeek();
    playerTimer?.cancel();
    hideTimer?.cancel();
    mouseScrollerTimer?.cancel();
    _adjustmentHudHideTimer?.cancel();
    _panelVisibilityController.dispose();
    _screenshotFeedbackController.dispose();
    _disposePlayerMenu();
    if (Platform.isAndroid) {
      unawaited(_syncAndroidPIPPlayerPageState(false));
      PipUtils.disposePipHandler();
    }
    // 分屏面板：先把防抖窗口内的比例落盘，再取消定时器（v1 的定时器在
    // dispose 没取消，页面卸载后还会写存储）。
    unawaited(playerController.panel.flushSplitPanelExtent());
    playerController.panel.disposeSplitPanelPersistence();
    playerController.panel.reset();
    VideoFilterController.instance.applyVf = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        // 视频区与面板各自只构造**一次实例**：下面的几何 Observer 会在拖动
        // 分界线时逐帧重建，但这两个 widget 实例不变，Flutter 会直接跳过它们的
        // 子树重建（否则每拖一帧都要重建整页 + 整个面板内容 → 手感发黏）。
        final videoRegion = _buildVideoRegion(context);
        final panelRegion = Observer(
          builder: (context) {
            final panel = playerController.panel;
            return PlayerSplitPanel(
              host: _splitTabHost,
              tab: panel.splitPanelTab,
              subPage: panel.splitPanelSubPage,
              onTabChanged: panel.setSplitPanelTab,
              onClose: panel.closeSplitPanel,
              onBack: panel.closeSplitPanelSubPage,
            );
          },
        );
        return ClipRect(
          child: Container(
            color: MediaChromeColors.surface,
            child: SizedBox(
              height: videoPageController.isFullscreen ||
                      videoPageController.isPip
                  ? (MediaQuery.of(context).size.height)
                  : (MediaQuery.of(context).size.width * 9.0 / (16.0)),
              width: MediaQuery.of(context).size.width,
              // 几何相关的 observable 只在这里读：拖动时只重建布局壳，
              // 不波及视频区与面板内容。
              child: Observer(
                builder: (context) {
                  final panel = playerController.panel;
                  return PlayerSplitLayout(
                    visible: panel.splitPanelVisible,
                    storedLandscapeWidth: panel.splitPanelWidth,
                    storedPortraitFraction: panel.splitPanelHeightFraction,
                    disableAnimations: widget.disableAnimations,
                    onExtentChanged: panel.setSplitPanelExtent,
                    onExtentReset: panel.resetSplitPanelExtent,
                    video: videoRegion,
                    panel: panelRegion,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// 分屏面板各 tab 的宿主（值对象，每次 build 重新构造，很便宜）。
  SplitTabHost get _splitTabHost => SplitTabHost(
        playerController: playerController,
        videoPageController: videoPageController,
        disableAnimations: widget.disableAnimations,
        setPlaybackSpeed: setPlaybackSpeed,
        handleSuperResolutionChange: handleSuperResolutionChange,
        skipOP: skipOP,
        handleScreenshot: handleScreenshot,
        showScreenshotCandidates: showScreenshotCandidates,
        pauseForTimedShutdown: widget.pauseForTimedShutdown,
        onEpisodeSelected: widget.onEpisodeSelected,
        onDownloadEpisode: widget.onDownloadEpisode,
      );

  /// 视频区实测尺寸；布局首帧可能还拿不到，此时返回 `null`（调用方回落到整窗值）。
  Size? get _videoViewportSize {
    final box = _videoRegionKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return null;
    }
    return box.size;
  }

  /// 视频区：画面 + 覆盖层 + 控制面板。
  ///
  /// 悬停与滚轮**只挂在本区**：v1 把它们挂在整容器上，导致在右侧面板区域
  /// 滚动也会改音量（真 bug）。分屏后视频区与面板区是两个独立子树，问题消失。
  Widget _buildVideoRegion(BuildContext context) {
    return MouseRegion(
      key: _videoRegionKey,
      cursor: (videoPageController.isFullscreen &&
              !playerController.panel.showVideoController)
          ? SystemMouseCursors.none
          : SystemMouseCursors.basic,
      onHover: (PointerEvent pointerEvent) {
        // workaround for android.
        // I don't know why, but android tap event will trigger onHover event.
        if (isDesktop()) {
          // 判据用**视频区**局部坐标：分屏后视频区比窗口窄/矮，整窗判据会在
          // 面板区域误判控制栏显隐。
          final box =
              _videoRegionKey.currentContext?.findRenderObject() as RenderBox?;
          final hasBox = box != null && box.hasSize;
          final localDy = hasBox
              ? box.globalToLocal(pointerEvent.position).dy
              : pointerEvent.position.dy;
          final regionHeight = hasBox
              ? box.size.height
              : MediaQuery.of(context).size.height;
          if (localDy > 50 && localDy < regionHeight - 70) {
            displayVideoController();
          } else {
            if (!playerController.panel.showVideoController) {
              _panelVisibilityController.forward();
              playerController.panel.showVideoController = true;
            }
          }
        }
      },
      child: Listener(
        onPointerSignal: (pointerSignal) {
          if (pointerSignal is PointerScrollEvent) {
            _handleMouseScroller();
            final scrollDelta = pointerSignal.scrollDelta;
            final double volume =
                playerController.playback.volume - scrollDelta.dy / 60;
            playerController.setVolume(volume);
          }
        },
        child: Stack(alignment: Alignment.center, children: [
          _buildVideoSurface(),
          (playerController.playback.isBuffering ||
                  videoPageController.loading)
              ? const Positioned.fill(
                  child: ExcludeSemantics(
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                )
              : Container(),
          _buildTapGestureLayer(),
          // 弹幕层：必须在视频表面之上、控制面板之下，
          // 否则弹幕会盖住控制条。
          Positioned.fill(child: _buildDanmakuLayer()),
          Positioned.fill(
            child: PlayerScreenshotFeedbackOverlay(
              animation: _screenshotFeedbackAnimation,
            ),
          ),
          // 播放器控制面板
          _buildControlPanels(),
          // 播放器手势控制
          _buildGestureControls(),
        ]),
      ),
    );
  }

  /// 视频画面层：键盘焦点处理 + 播放器表面。
  Widget _buildVideoSurface() {
    return Center(
      child: Focus(
        // workaround for #461
        // I don't know why, but the focus node will break popscope.
        focusNode: widget.keyboardFocus,
        autofocus: true,
        onKeyEvent: (focusNode, KeyEvent event) {
          bool handled = false;
          final keyLabel = event.logicalKey.keyLabel.isNotEmpty
              ? event.logicalKey.keyLabel
              : event.logicalKey.debugName ?? '';
          if (event is KeyDownEvent) {
            handled = handleShortcutDown(keyLabel);
          } else if (event is KeyRepeatEvent) {
            handled = handleShortcutLongPress(keyLabel, 'Repeat');
          } else if (event is KeyUpEvent) {
            handled = handleShortcutLongPress(keyLabel, 'Up');
          }
          return handled ? KeyEventResult.handled : KeyEventResult.ignored;
        },
        child: PlayerItemSurface(playerController: playerController),
      ),
    );
  }

  /// 点击/双击/长按手势层（锁定面板时禁用双击与长按）。
  Widget _buildTapGestureLayer() {
    return GestureDetector(
      onTapDown: (details) {
        _lastTapPointerKind = details.kind;
      },
      onTap: () {
        _handleTap(_lastTapPointerKind);
        _lastTapPointerKind = null;
      },
      onTapCancel: () {
        _lastTapPointerKind = null;
      },
      onDoubleTapDown: (playerController.panel.lockPanel)
          ? null
          : (details) {
              _lastDoubleTapPointerKind = details.kind;
            },
      onDoubleTap: (playerController.panel.lockPanel)
          ? null
          : () {
              _handleDoubleTap(
                _lastDoubleTapPointerKind ?? _lastTapPointerKind,
              );
              _lastDoubleTapPointerKind = null;
              _lastTapPointerKind = null;
            },
      onLongPressStart: (_) {
        if (playerController.panel.lockPanel) {
          return;
        }
        setState(() {
          playerController.panel.showPlaySpeed = true;
        });
        lastPlayerSpeed = playerController.playback.playerSpeed;
        setPlaybackSpeed(longPressPlaySpeed);
      },
      onLongPressEnd: (_) {
        if (playerController.panel.lockPanel) {
          return;
        }
        setState(() {
          playerController.panel.showPlaySpeed = false;
        });
        setPlaybackSpeed(lastPlayerSpeed);
      },
      child: Container(
        color: Colors.transparent,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }

  /// 播放器控制面板。
  ///
  /// 只有一份面板：窄屏/宽屏由它内部按可用宽度自行切换（见 `PlayerItemPanel`）。
  Widget _buildControlPanels() {
    return PlayerItemPanel(
      playerController: playerController,
      onBackPressed: widget.onBackPressed,
      setPlaybackSpeed: setPlaybackSpeed,
      handleFullscreen: handleFullscreen,
      handleProgressBarDragStart: handleProgressBarDragStart,
      handleProgressBarSeek: handleProgressBarSeek,
      panelVisibilityController: _panelVisibilityController,
      acquirePlayerPanelHold: acquirePlayerPanelHold,
      pauseForTimedShutdown: widget.pauseForTimedShutdown,
      disableAnimations: widget.disableAnimations,
      handleScreenShot: handleScreenshot,
      showScreenshotCandidates: showScreenshotCandidates,
      skipOP: skipOP,
      splitPanelVisible: playerController.panel.splitPanelVisible,
      toggleSplitPanel: playerController.panel.toggleSplitPanel,
    );
  }

  /// 播放器手势控制：水平拖动 seek，垂直拖动调亮度（左）/音量（右）。
  Widget _buildGestureControls() {
    return Positioned.fill(
      left: 16,
      top: 25,
      right: 15,
      bottom: 15,
      child: (isDesktop() || playerController.panel.lockPanel)
          ? Container()
          : GestureDetector(
              onHorizontalDragStart: (_) {
                playerController.panel.seekDirection = 0;
                _beginInteractiveSeek();
              },
              onHorizontalDragUpdate: (DragUpdateDetails details) {
                playerController.panel.showSeekTime = true;
                if (details.delta.dx != 0) {
                  playerController.panel.seekDirection =
                      details.delta.dx > 0 ? 1 : -1;
                }
                // 按视频区实测宽度换算：面板占掉一部分后，同样的拖动距离
                // 必须对应同样的**视频内**进度比例。
                final double scale = 180000 /
                    (_videoViewportSize?.width ??
                        MediaQuery.sizeOf(context).width);
                playerController.seeking.updateInteractiveSeek(
                  playerController.playback.currentPosition +
                      Duration(
                        milliseconds: (details.delta.dx * scale).round(),
                      ),
                );
              },
              onHorizontalDragEnd: (_) {
                playerController.panel.showSeekTime = false;
                playerController.panel.seekDirection = 0;
                if (playerController.seeking.hasActiveInteractiveSeek) {
                  unawaited(
                    _commitInteractiveSeek(),
                  );
                }
              },
              onVerticalDragUpdate: (DragUpdateDetails details) async {
                if (!brightnessVolumeGesture) {
                  return;
                }
                final double totalWidth = MediaQuery.sizeOf(context).width;
                final double totalHeight = MediaQuery.sizeOf(context).height;
                final double tapPosition = details.localPosition.dx;
                final double sectionWidth = totalWidth / 2;
                final double delta = details.delta.dy;

                if (tapPosition < sectionWidth) {
                  // 左边区域
                  playerController.panel.brightnessSeeking = true;
                  _showBrightnessAdjustmentHud();
                  final double level = (totalHeight) * 2;
                  final double brightness =
                      playerController.panel.brightness - delta / level;
                  final double result = brightness.clamp(0.0, 1.0);
                  setBrightness(result);
                  playerController.panel.brightness = result;
                } else {
                  // 右边区域
                  _showVolumeAdjustmentHud();
                  if (!playerController.panel.volumeSeeking) {
                    playerController.panel.volumeSeeking = true;
                    playerController.playback.invalidatePreciseVolume();
                  }
                  final double baseVolume =
                      playerController.playback.preciseVolume >= 0
                          ? playerController.playback.preciseVolume
                          : playerController.playback.volume;
                  final double level = (totalHeight) * 0.03;
                  final double volume = baseVolume - delta / level;
                  playerController.setVolumeDuringGesture(volume);
                }
              },
              onVerticalDragEnd: (_) {
                _finishAdjustmentGesture();
              },
              onVerticalDragCancel: () {
                _finishAdjustmentGesture();
              },
            ),
    );
  }
}
