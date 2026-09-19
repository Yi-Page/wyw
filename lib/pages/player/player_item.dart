import 'dart:async';
import 'dart:io';
import 'package:wyw/bean/styles/media_chrome_colors.dart';
import 'package:wyw/pages/player/player_item_panel.dart';
import 'package:wyw/pages/player/controller/player_super_resolution.dart';
import 'package:wyw/pages/player/player_panel_hold.dart';
import 'package:wyw/pages/player/player_pointer_interaction.dart';
import 'package:wyw/pages/player/player_screenshot_feedback_overlay.dart';
import 'package:wyw/pages/player/smallest_player_item_panel.dart';
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
import 'package:wyw/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/utils/clipboard.dart';
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
    this.toggleEpisodePanel,
  });

  final PlayerController playerController;
  final void Function(BuildContext) onBackPressed;
  final FocusNode keyboardFocus;
  final bool disableAnimations;
  final VoidCallback pauseForTimedShutdown;

  /// 选集/线路面板切换回调（由视频页传入，打开右侧抽屉/下方 tab）。
  final VoidCallback? toggleEpisodePanel;

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
  final Set<PlayerPanelHold> _playerPanelHolds = <PlayerPanelHold>{};
  PlayerPanelHold? _progressBarDragHold;
  PointerDeviceKind? _lastTapPointerKind;
  PointerDeviceKind? _lastDoubleTapPointerKind;

  late final AnimationController _panelVisibilityController;
  late final AnimationController _screenshotFeedbackController;
  late final Animation<double> _screenshotFeedbackAnimation;

  double lastPlayerSpeed = 1.0;
  late double longPressPlaySpeed;
  int episodeNum = 0;
  bool? _lastPipPlaying;
  late mobx.ReactionDisposer _playerSizeListener;

  late mobx.ReactionDisposer _fullscreenListener;

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
    _playScreenshotFeedback();

    if (isDesktop()) {
      WywDialog.showToast(message: '桌面端暂未支持保存截图');
      return;
    }

    try {
      Uint8List? screenshot = await playerController.screenshotPng();

      if (screenshot == null) {
        WywDialog.showToast(message: '截图失败：未获取到图像');
        return;
      }

      final result = await SaverGallery.saveImage(
        screenshot,
        fileName: DateTime.timestamp().millisecondsSinceEpoch.toString(),
        skipIfExists: false,
      );
      if (!result.isSuccess) {
        WywDialog.showToast(message: '截图保存失败：${result.errorMessage}');
      }
    } catch (e) {
      WywDialog.showToast(message: '截图失败：$e');
    }
  }

  void _playScreenshotFeedback() {
    if (!mounted) {
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

  Timer getPlayerTimer() {
    return Timer.periodic(const Duration(seconds: 1), (timer) {
      playerController.syncPlaybackState();
      unawaited(_updateAndroidPIPActions());
      _syncAudioServiceState();
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

  Widget get videoInfoBody {
    return Observer(builder: (context) {
      return ListView(
        children: [
          ListTile(
            title: const Text('Source'),
            subtitle: Text(playerController.videoUrl),
            onTap: () => copyToClipboard(playerController.videoUrl),
          ),
          ListTile(
            title: const Text('Resolution'),
            subtitle: Text(
                '${playerController.debug.playerWidth}x${playerController.debug.playerHeight}'),
            onTap: () => copyToClipboard(
                'Resolution\n${playerController.debug.playerWidth}x${playerController.debug.playerHeight}'),
          ),
          ListTile(
            title: const Text('VideoParams'),
            subtitle: Text(playerController.debug.playerVideoParams.toString()),
            onTap: () => copyToClipboard(
                'VideoParams\n${playerController.debug.playerVideoParams.toString()}'),
          ),
          ListTile(
            title: const Text('AudioParams'),
            subtitle: Text(playerController.debug.playerAudioParams.toString()),
            onTap: () => copyToClipboard(
                'AudioParams\n${playerController.debug.playerAudioParams.toString()}'),
          ),
          ListTile(
            title: const Text('Media'),
            subtitle: Text(playerController.debug.playerPlaylist.toString()),
            onTap: () => copyToClipboard(
                'Media\n${playerController.debug.playerPlaylist.toString()}'),
          ),
          ListTile(
            title: const Text('AudioTrack'),
            subtitle: Text(playerController.debug.playerAudioTracks.toString()),
            onTap: () => copyToClipboard(
                'AudioTrack\n${playerController.debug.playerAudioTracks.toString()}'),
          ),
          ListTile(
            title: const Text('VideoTrack'),
            subtitle: Text(playerController.debug.playerVideoTracks.toString()),
            onTap: () => copyToClipboard(
                'VideoTrack\n${playerController.debug.playerVideoTracks.toString()}'),
          ),
          ListTile(
            title: const Text('VideoBitrate'),
            subtitle:
                Text(playerController.debug.playerVideoBitrate.toString()),
            onTap: () => copyToClipboard(
                'VideoBitrate\n${playerController.debug.playerVideoBitrate.toString()}'),
          ),
          ListTile(
            title: const Text('AudioBitrate'),
            subtitle:
                Text(playerController.debug.playerAudioBitrate.toString()),
            onTap: () => copyToClipboard(
                'AudioBitrate\n${playerController.debug.playerAudioBitrate.toString()}'),
          ),
        ],
      );
    });
  }

  Widget get videoDebugLogBody {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0),
        child: Observer(builder: (context) {
          return ListView.builder(
            itemCount: playerController.debug.playerLog.length,
            itemBuilder: (context, index) {
              return Text(playerController.debug.playerLog[index]);
            },
          );
        }),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.copy),
        onPressed: () => copyToClipboard(
            playerController.debug.playerLog.join('\n'),
            toastMessage: null),
      ),
    );
  }

  void showVideoInfo() {
    showAdaptiveBottomSheet<void>(
      context: context,
      builder: (context) {
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            body: Column(
              children: [
                const PreferredSize(
                  preferredSize: Size.fromHeight(kToolbarHeight),
                  child: Material(
                    child: TabBar(
                      tabs: [
                        Tab(text: '状态'),
                        Tab(text: '日志'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      videoInfoBody,
                      videoDebugLogBody,
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Used to decide which panel is used.
  /// It's too complicated to write these in conditional sentence.
  /// * true: use [PlayerItemPanel]
  /// * false: use [SmallestPlayerItemPanel]
  bool needFullPanel(BuildContext context) {
    // windows too small, workaround for ohos floating window
    if (MediaQuery.sizeOf(context).width < LayoutBreakpoint.compact['width']!) {
      return false;
    }
    // in desktop pip mode
    if (videoPageController.isPip) {
      return false;
    }
    // does not meet Google's phone landscape height and tablet landscape width requirements.
    if (!isDesktop() &&
        (MediaQuery.sizeOf(context).height >
                LayoutBreakpoint.compact['height']! &&
            MediaQuery.sizeOf(context).width <
                LayoutBreakpoint.medium['width']!)) {
      return false;
    }
    if (isDesktop() &&
        (MediaQuery.sizeOf(context).height >
                LayoutBreakpoint.compact['height']! &&
            MediaQuery.sizeOf(context).width <
                LayoutBreakpoint.compact['width']!)) {
      return false;
    }
    return true;
  }

  @override
  void onWindowRestore() {}

  @override
  void initState() {
    super.initState();
    playerController = widget.playerController;
    _loadShortcuts();
    _initKeyboardActions();
    _initPlayerMenu();
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
    playerController.panel.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        return ClipRect(
          child: Container(
            color: MediaChromeColors.surface,
            child: MouseRegion(
              cursor: (videoPageController.isFullscreen &&
                      !playerController.panel.showVideoController)
                  ? SystemMouseCursors.none
                  : SystemMouseCursors.basic,
              onHover: (PointerEvent pointerEvent) {
                // workaround for android.
                // I don't know why, but android tap event will trigger onHover event.
                if (isDesktop()) {
                  if (pointerEvent.position.dy > 50 &&
                      pointerEvent.position.dy <
                          MediaQuery.of(context).size.height - 70) {
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
                child: SizedBox(
                  height: videoPageController.isFullscreen ||
                          videoPageController.isPip
                      ? (MediaQuery.of(context).size.height)
                      : (MediaQuery.of(context).size.width * 9.0 / (16.0)),
                  width: MediaQuery.of(context).size.width,
                  child: Stack(alignment: Alignment.center, children: [
                    _buildVideoSurface(),
                    (playerController.playback.isBuffering ||
                            videoPageController.loading)
                        ? const Positioned.fill(
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : Container(),
                    _buildTapGestureLayer(),
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
              ),
            ),
          ),
        );
      },
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

  /// 播放器控制面板：桌面端完整面板 / 移动端精简面板。
  Widget _buildControlPanels() {
    if (needFullPanel(context)) {
      return PlayerItemPanel(
        playerController: playerController,
        onBackPressed: widget.onBackPressed,
        setPlaybackSpeed: setPlaybackSpeed,
        handleFullscreen: handleFullscreen,
        handleProgressBarDragStart: handleProgressBarDragStart,
        handleProgressBarSeek: handleProgressBarSeek,
        handleSuperResolutionChange: handleSuperResolutionChange,
        panelVisibilityController: _panelVisibilityController,
        acquirePlayerPanelHold: acquirePlayerPanelHold,
        showVideoInfo: showVideoInfo,
        pauseForTimedShutdown: widget.pauseForTimedShutdown,
        disableAnimations: widget.disableAnimations,
        handleScreenShot: handleScreenshot,
        skipOP: skipOP,
        toggleEpisodePanel: widget.toggleEpisodePanel,
      );
    }
    return SmallestPlayerItemPanel(
      playerController: playerController,
      onBackPressed: widget.onBackPressed,
      setPlaybackSpeed: setPlaybackSpeed,
      handleFullscreen: handleFullscreen,
      handleProgressBarDragStart: handleProgressBarDragStart,
      handleProgressBarSeek: handleProgressBarSeek,
      handleSuperResolutionChange: handleSuperResolutionChange,
      panelVisibilityController: _panelVisibilityController,
      acquirePlayerPanelHold: acquirePlayerPanelHold,
      showVideoInfo: showVideoInfo,
      pauseForTimedShutdown: widget.pauseForTimedShutdown,
      disableAnimations: widget.disableAnimations,
      skipOP: skipOP,
      toggleEpisodePanel: widget.toggleEpisodePanel,
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
                final double scale = 180000 / MediaQuery.sizeOf(context).width;
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
