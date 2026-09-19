import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wyw/bean/styles/media_chrome_colors.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/download/download_controller.dart';
import 'package:wyw/pages/player/player_controller.dart';
import 'package:wyw/pages/video/video_controller.dart';
import 'package:wyw/pages/player/player_item.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/services/history/history_progress_reporter.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/player/pip_utils.dart';
import 'package:wyw/bean/appbar/drag_to_move_bar.dart' as dtb;
import 'package:wyw/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wyw/bean/widget/embedded_native_control_area.dart';
import 'package:wyw/bean/widget/loading_indicator.dart';
import 'package:wyw/bean/widget/media_error_widget.dart';
import 'package:wyw/services/player/timed_shutdown_service.dart';
import 'package:wyw/utils/device.dart';
import 'package:wyw/services/platform/display_mode_service.dart';
import 'package:wyw/pages/video/video_route_args.dart';
import 'package:wyw/bean/widget/video_episode_panel.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({
    super.key,
    required this.playerController,
    required this.videoPageController,
    this.args,
  });

  final PlayerController playerController;
  final VideoPageController videoPageController;

  /// 结构化进入参数（播放源列表 + 初始源/集）；null 表示旧入口（仅 url 字段）。
  final VideoPageRouteArgs? args;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage>
    with TickerProviderStateMixin, WindowListener {
  PlayerController get playerController => widget.playerController;

  VideoPageController get videoPageController => widget.videoPageController;
  bool _didInitializePlayback = false;
  bool _isClosing = false;

  late bool playResume;
  bool showDebugLog = false;
  List<String> webviewLogLines = [];
  StreamSubscription<String>? _logSubscription;
  final FocusNode keyboardFocus = FocusNode();

  late AnimationController animation;

  /// 选集面板是否展开（右侧抽屉）。
  bool _tabBodyTargetVisible = false;

  late final bool disableAnimations;

  static const Duration _sideTabAnimationDuration = Duration(milliseconds: 120);

  late AnimationController _maskOpacityAnimation;
  late Animation<Offset> _rightOffsetAnimation;

  /// 横屏判断：宽 > 高。
  bool get _windowIsLandscape =>
      MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // 结构化进入参数注入（无参旧入口保持 controller 已有字段）。
    final args = widget.args;
    if (args != null) {
      videoPageController.configure(args);
      // 结构化模式：reporter 静默，进度经 onProgressChanged 写 v3
      final reporter = HistoryProgressReporter();
      reporter.setMuted(true);
      reporter.onMutedProgress = (positionMs, durationMs) {
        videoPageController.reportProgress(
            positionMs: positionMs, durationMs: durationMs);
        videoPageController.notifyProgressChanged();
      };
    }
    // Window fullscreen can be changed outside this page through system chrome.
    videoPageController.syncWindowFullscreenState();
    if (!isDesktop()) {
      // 非桌面端恒为全屏（沉浸式）播放，进入页面即全屏。
      videoPageController.enterFullScreen();
    }

    animation = AnimationController(
      duration: _sideTabAnimationDuration,
      vsync: this,
    );
    _maskOpacityAnimation = AnimationController(
      duration: _sideTabAnimationDuration,
      vsync: this,
    );
    _rightOffsetAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _maskOpacityAnimation, curve: Curves.easeIn));

    playResume = GStorage.getSetting(SettingsKeys.playResume);
    disableAnimations =
        GStorage.getSetting(SettingsKeys.playerDisableAnimations);
    // 桌面/竖屏默认收起右侧抽屉；横屏进入时点选集按钮展开
    _tabBodyTargetVisible = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitializePlayback) {
      return;
    }
    _didInitializePlayback = true;
    _initializePlayback();
  }

  void _initializePlayback() {
    // 结构化进入：统一走 playEpisode，内部按 path.type 分发
    // （local → 本地播放；direct/page/resolve → 在线播放）
    _initPlayback(playerController);
  }

  void _initPlayback(PlayerController playerController) {
    _logSubscription = videoPageController.logStream.listen((log) {
      if (mounted) {
        setState(() {
          webviewLogLines.add(log);
          if (webviewLogLines.length > 100) {
            webviewLogLines.removeAt(0);
          }
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // 结构化进入：按 initialSource/initialEpisode 播放，带续播 offset
      // （args.offsetMs 优先；插件进入时为 0，改用历史回填的 resumeOffsetMs）
      final offsetMs = (widget.args?.offsetMs ?? 0) > 0
          ? widget.args!.offsetMs
          : videoPageController.resumeOffsetMs;
      videoPageController.playEpisode(
        sourceIndex: videoPageController.currentSourceIndex,
        episodeIndex: videoPageController.currentEpisodeIndex,
        offset: offsetMs,
        playerController: playerController,
      );
    });
  }

  @override
  void dispose() {
    // 结构化模式退出：先补一次最终进度（200ms 防抖会落盘），再恢复 reporter
    if (widget.args != null) {
      videoPageController.notifyProgressChanged();
      final reporter = HistoryProgressReporter();
      reporter.setMuted(false);
      reporter.onMutedProgress = null;
    }
    try {
      windowManager.removeListener(this);
    } catch (e) {
      WywLogger().d('${LogTag.player} 移除窗口事件监听失败（已忽略）', error: e);
    }
    try {
      animation.dispose();
    } catch (e) {
      WywLogger().d('${LogTag.player} 释放页面动画控制器失败（已忽略）', error: e);
    }
    try {
      _maskOpacityAnimation.dispose();
    } catch (e) {
      WywLogger().d('${LogTag.player} 释放选集面板遮罩动画控制器失败（已忽略）', error: e);
    }

    try {
      _logSubscription?.cancel();
    } catch (e) {
      WywLogger().d('${LogTag.player} 取消 WebView 日志订阅失败（已忽略）', error: e);
    }
    videoPageController.cancelVideoSourceResolution();
    // 停止代理播放（若有），剩余分片由 DownloadManager 后台补全
    try {
      inject<DownloadController>()
          .stopProxyPlayback(videoPageController.proxyRecordKey);
    } catch (e) {
      WywLogger().d('${LogTag.player} 停止代理播放失败（已忽略）', error: e);
    }
    if (!isDesktop()) {
      try {
        ScreenBrightnessPlatform.instance.resetApplicationScreenBrightness();
      } catch (e) {
        WywLogger().d('${LogTag.player} 恢复屏幕亮度失败（已忽略）', error: e);
      }
      // 非桌面端进入播放页时隐藏了系统状态栏，退出时恢复。
      DisplayModeService.exitFullScreen();
    }
    DisplayModeService.unlockScreenRotation();
    keyboardFocus.dispose();
    TimedShutdownService().cancel();
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    videoPageController.handleOnEnterFullScreen();
  }

  @override
  void onWindowLeaveFullScreen() {
    videoPageController.handleOnExitFullScreen();
  }

  void showDebugConsole() {
    setState(() {
      showDebugLog = true;
    });
  }

  void hideDebugConsole() {
    setState(() {
      showDebugLog = false;
    });
  }

  void switchDebugConsole() {
    setState(() {
      showDebugLog = !showDebugLog;
    });
  }

  void clearWebviewLog() {
    setState(() {
      webviewLogLines.clear();
    });
  }

  // ===== 选集面板动画 =====

  void _toggleTabBodyAnimated() {
    if (_windowIsLandscape) {
      // 横屏：右侧抽屉展开/收起
      if (_tabBodyTargetVisible) {
        _closeTabBodyAnimated();
      } else {
        _openTabBodyAnimated();
      }
      return;
    }
    // 竖屏：从底部弹出选集面板（可下滑收起）
    unawaited(_showPortraitEpisodeSheet());
  }

  /// 竖屏从底部弹出选集/线路面板（bottom sheet，可下滑关闭）。
  Future<void> _showPortraitEpisodeSheet() async {
    if (!mounted) return;
    final selected = await showAdaptiveBottomSheet<(int, int)>(
      context: context,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.6,
        child: VideoEpisodePanel(
          title: videoPageController.videoTitle,
          sources: videoPageController.sources,
          currentSourceIndex: videoPageController.currentSourceIndex,
          currentEpisodeIndex: videoPageController.currentEpisodeIndex,
          onEpisodeTap: (s, e) => Navigator.of(sheetContext).pop((s, e)),
          onDownloadEpisode: (s, e) =>
              videoPageController.downloadEpisode(s, e),
          sourceKey: videoPageController.sourceKey,
          videoId: videoPageController.videoId,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final (source, episode) = selected;
    _onEpisodeTap(source, episode);
  }

  void _openTabBodyAnimated() {
    if (_tabBodyTargetVisible) return;
    setState(() {
      _tabBodyTargetVisible = true;
    });
    if (mounted && !disableAnimations) {
      _maskOpacityAnimation.forward();
    }
  }

  void _closeTabBodyAnimated() {
    if (!_tabBodyTargetVisible) return;
    setState(() {
      _tabBodyTargetVisible = false;
    });
    if (mounted && !disableAnimations) {
      _maskOpacityAnimation.reverse();
    }
  }

  /// 重播当前集（刷新按钮/解析失败重试用）。
  ///
  /// 「重新解析」语义：清除该集直链缓存并强制重走解析/嗅探。
  Future<void> _replayCurrentEpisode() async {
    clearWebviewLog();
    hideDebugConsole();
    try {
      await playerController.stop();
    } catch (e) {
      // 停止旧播放失败不应阻断重新解析；playerController.init 内部
      // 会再次释放播放资源，这里仅记录日志后继续。
      WywLogger().e('${LogTag.player} 重播前停止旧播放失败', error: e);
    }
    await videoPageController.playEpisode(
      sourceIndex: videoPageController.currentSourceIndex,
      episodeIndex: videoPageController.currentEpisodeIndex,
      playerController: playerController,
      forceReresolve: true,
    );
  }

  void onBackPressed(BuildContext context) async {
    if (WywDialog.observer.hasWywDialog) {
      WywDialog.dismiss();
      return;
    }
    if (videoPageController.isPip && isDesktop()) {
      PipUtils.exitDesktopPIPWindow();
      videoPageController.isPip = false;
      return;
    }
    // 桌面端在全屏时按返回应先退出全屏；非桌面端恒为全屏，直接返回页面。
    if (isDesktop() && videoPageController.isFullscreen) {
      videoPageController.exitFullScreen();
      return;
    }
    if (_isClosing) {
      return;
    }
    _isClosing = true;
    playerController.beginShutdown();
    if (!context.mounted) {
      return;
    }
    context.pop();
  }

  void pauseForTimedShutdown() {
    if (playerController.playback.playing) {
      playerController.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          return;
        }
        onBackPressed(context);
      },
      child: Observer(
        builder: (context) {
          final bool isPip = videoPageController.isPip;
          final bool isLandscape = _windowIsLandscape;
          return Scaffold(
            appBar: null,
            body: SafeArea(
              top: !videoPageController.isFullscreen && !isPip,
              // set iOS and Android navigation bar to immersive
              bottom: false,
              left: !videoPageController.isFullscreen && !isPip,
              right: !videoPageController.isFullscreen && !isPip,
              child: Stack(
                alignment: Alignment.centerRight,
                children: [
                  Container(
                    color: MediaChromeColors.surface,
                    height: MediaQuery.sizeOf(context).height,
                    width: MediaQuery.sizeOf(context).width,
                    child: playerBody,
                  ),
                  if (isLandscape && _tabBodyTargetVisible && !isPip) ...[
                    if (disableAnimations) ...[
                      sideTabMask,
                      sideTabBody,
                    ] else ...[
                      FadeTransition(
                        opacity: _maskOpacityAnimation,
                        child: sideTabMask,
                      ),
                      SlideTransition(
                        position: _rightOffsetAnimation,
                        child: sideTabBody,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget get playerBody {
    final bool playerLoading = playerController.playback.loading;
    return Stack(
      children: [
        Positioned.fill(
          child: Stack(
            children: [
              if (videoPageController.loading ||
                  playerLoading ||
                  videoPageController.errorMessage != null)
                Container(
                  color: MediaChromeColors.surface,
                  child: Observer(builder: (context) {
                    return Center(
                      child: videoPageController.errorMessage != null
                          ? MediaErrorWidget(
                              title: '视频加载失败',
                              errMsg: videoPageController.errorMessage!,
                              icon: Icons.error_outline_rounded,
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                LoadingIndicator(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .tertiaryContainer),
                                const SizedBox(height: 10),
                                Text(
                                  videoPageController.loading
                                      ? '视频资源解析中'
                                      : '视频资源解析成功, 播放器加载中',
                                  style: const TextStyle(color: MediaChromeColors.foreground),
                                ),
                              ],
                            ),
                    );
                  }),
                ),
              Visibility(
                visible: (videoPageController.loading || playerLoading) &&
                    showDebugLog,
                child: Container(
                  color: MediaChromeColors.surface,
                  child: Align(
                    alignment: Alignment.center,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: webviewLogLines.length,
                      itemBuilder: (context, index) {
                        return Text(
                          webviewLogLines.isEmpty ? '' : webviewLogLines[index],
                          style: const TextStyle(
                            color: MediaChromeColors.foreground,
                          ),
                          textAlign: TextAlign.center,
                        );
                      },
                    ),
                  ),
                ),
              ),
              Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: EmbeddedNativeControlArea(
                      requireOffset: !videoPageController.isFullscreen,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back,
                                color: MediaChromeColors.foreground),
                            onPressed: () => onBackPressed(context),
                          ),
                          const Expanded(
                              child: dtb.DragToMoveArea(
                                  child: SizedBox(height: 40))),
                          IconButton(
                            icon: const Icon(Icons.refresh_outlined,
                                color: MediaChromeColors.foreground),
                            tooltip: '重新解析',
                            onPressed: () => _replayCurrentEpisode(),
                          ),
                          IconButton(
                            icon: Icon(
                                showDebugLog
                                    ? Icons.bug_report
                                    : Icons.bug_report_outlined,
                                color: MediaChromeColors.foreground),
                            onPressed: () {
                              switchDebugConsole();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: playerController.playback.loading
              ? Container()
              : PlayerItem(
                  playerController: playerController,
                  onBackPressed: onBackPressed,
                  keyboardFocus: keyboardFocus,
                  pauseForTimedShutdown: pauseForTimedShutdown,
                  toggleEpisodePanel: _toggleTabBodyAnimated,
                ),
        ),
      ],
    );
  }
  // ===== 选集 / 线路面板 =====

  /// 右侧抽屉本体。
  Widget get sideTabBody {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height,
      width: (!isDesktop() && !isTablet())
          ? MediaQuery.sizeOf(context).height
          : (MediaQuery.sizeOf(context).width / 3 > 420
              ? 420
              : MediaQuery.sizeOf(context).width / 3),
      child: Container(
        color: Theme.of(context).canvasColor,
        child: VideoEpisodePanel(
          title: videoPageController.videoTitle,
          sources: videoPageController.sources,
          currentSourceIndex: videoPageController.currentSourceIndex,
          currentEpisodeIndex: videoPageController.currentEpisodeIndex,
          onEpisodeTap: _onEpisodeTap,
          onDownloadEpisode: (s, e) =>
              videoPageController.downloadEpisode(s, e),
          sourceKey: videoPageController.sourceKey,
          videoId: videoPageController.videoId,
        ),
      ),
    );
  }

  /// 右侧抽屉遮罩（左深右浅，点击关闭）。
  Widget get sideTabMask {
    return GestureDetector(
      onTap: _closeTabBodyAnimated,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              MediaChromeColors.scrim.withValues(alpha: 0.5),
              Colors.transparent,
            ],
          ),
        ),
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }

  /// 选集面板点击某集：切到该线路/集并播放，然后关闭面板。
  void _onEpisodeTap(int sourceIndex, int episodeIndex) {
    if (sourceIndex == videoPageController.currentSourceIndex &&
        episodeIndex == videoPageController.currentEpisodeIndex) {
      _closeTabBodyAnimated();
      return;
    }
    videoPageController.playEpisode(
      sourceIndex: sourceIndex,
      episodeIndex: episodeIndex,
      playerController: playerController,
    );
    _closeTabBodyAnimated();
  }
}
