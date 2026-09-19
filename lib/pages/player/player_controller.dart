import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/services/player/external_playback_launcher.dart';
import 'package:wyw/pages/player/controller/player_debug_controller.dart';
import 'package:wyw/pages/player/controller/player_models.dart';
import 'package:wyw/pages/player/controller/player_seek_controller.dart';
import 'package:wyw/pages/player/controller/player_aspect_ratio.dart';
import 'package:wyw/pages/player/controller/player_panel_controller.dart';
import 'package:wyw/pages/player/controller/player_playback_controller.dart';
import 'package:wyw/pages/player/controller/player_super_resolution.dart';
import 'package:wyw/services/history/history_progress_reporter.dart';
import 'package:wyw/services/storage/history_type.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/shaders/shader_asset_service.dart';
import 'package:wyw/services/player/audio_controller.dart';
import 'package:wyw/utils/async_session.dart';
import 'package:wyw/utils/device.dart';

export 'package:wyw/pages/player/controller/player_models.dart';

class PlayerController implements Disposable {
  PlayerController(
    this.shaderAssetService,
    this.audioController,
  );

  final ShaderAssetService shaderAssetService;
  final AudioController audioController;
  final AsyncSessionOwner _initializations = AsyncSessionOwner();
  Future<void>? _shutdownFuture;
  final PlayerPanelController panel = PlayerPanelController();
  final PlayerDebugController debug = PlayerDebugController();

  late final PlayerPlaybackController playback = PlayerPlaybackController(
    shaderAssetService: shaderAssetService,
    debug: debug,
    videoUrl: () => videoUrl,
  );
  late final PlayerSeekController seeking = PlayerSeekController(
    playback: playback,
    pause: pause,
    play: play,
  );
  late final ExternalPlaybackLauncher externalPlayback =
      ExternalPlaybackLauncher(
    videoUrl: () => videoUrl,
    referer: () => referer,
  );

  late String referer;
  String? coverUrl;
  String videoUrl = '';
  bool isLocalPlayback = false;
  Timer? hideVolumeUITimer;
  Timer? _volumeGestureSyncTimer;
  double? _pendingGestureVolume;

  bool muted = false;
  double _preMuteVolume = 100;

  Future<void> toggleMute() async {
    if (!muted && playback.volume > 0) {
      _preMuteVolume = playback.volume;
      muted = true;
      _persistMuteState();
      await setVolume(0);
    } else {
      muted = false;
      _persistMuteState();
      await setVolume(_preMuteVolume > 0 ? _preMuteVolume : 100);
    }
  }

  void _persistMuteState() {
    if (!isDesktop()) {
      return;
    }
    unawaited(GStorage.putSetting<bool>(SettingsKeys.playerMuted, muted));
  }

  /// 在音量被主动调高（手势 / 按键 / 滚轮）时退出静音状态。
  void _clearMuteIfNeeded(double value) {
    if (muted && value > 0) {
      muted = false;
      _persistMuteState();
    }
  }

  void setVolumeDuringGesture(double value) {
    _pendingGestureVolume = value.clamp(0.0, 100.0);
    playback.updateVolume(_pendingGestureVolume!);
    _volumeGestureSyncTimer?.cancel();
    _volumeGestureSyncTimer = Timer(const Duration(milliseconds: 80), () {
      final vol = _pendingGestureVolume;
      if (vol == null) {
        return;
      }
      unawaited(playback.syncVolumeToDevice(vol));
    });
  }

  Future<void> finishVolumeGesture() async {
    _volumeGestureSyncTimer?.cancel();
    _volumeGestureSyncTimer = null;
    final vol = _pendingGestureVolume;
    _pendingGestureVolume = null;
    if (vol != null) {
      playback.volume = vol;
    }
    playback.invalidatePreciseVolume();
    await playback.syncVolumeToDevice(vol);
    final resolved = vol ?? playback.volume;
    _clearMuteIfNeeded(resolved);
    _persistDesktopVolume(resolved);
  }

  void _persistDesktopVolume(double value) {
    if (!isDesktop()) {
      return;
    }
    if (muted) {
      return;
    }
    final clamped = value.clamp(0.0, 100.0);
    final stored = GStorage.getSetting(SettingsKeys.defaultVolume);
    if (stored.round() == clamped.round()) {
      return;
    }
    unawaited(GStorage.putSetting<double>(SettingsKeys.defaultVolume, clamped));
  }

  Future<bool> init(PlaybackInitParams params) async {
    if (_initializations.isClosed) {
      return false;
    }
    final initialization = _initializations.begin();

    videoUrl = params.videoUrl;
    referer = params.referer;

    WywLogger().i('${LogTag.player} 初始化播放 url=${params.videoUrl}');

    playback.resetForInit();
    debug.playerLogLevel = GStorage.getSetting(SettingsKeys.playerLogLevel);
    playback.playerSpeed = GStorage.getSetting(SettingsKeys.defaultPlaySpeed);
    panel.aspectRatioMode = PlayerAspectRatio.fromStorageValue(
      GStorage.getSetting(SettingsKeys.defaultAspectRatioType),
    );

    playback.buttonSkipTime = GStorage.getSetting(SettingsKeys.buttonSkipTime);
    playback.arrowKeySkipTime =
        GStorage.getSetting(SettingsKeys.arrowKeySkipTime);
    try {
      await _releasePlaybackResources();
    } catch (e) {
      WywLogger().d('${LogTag.player} 初始化前释放旧播放资源失败（已忽略）', error: e);
    }
    if (initialization.isStale) {
      return false;
    }

    final Player? player;
    try {
      player = await playback.createVideoController(
        params.httpHeaders,
        params.adBlockerEnabled,
        canInstall: () => initialization.isActive,
        offset: params.offset,
      );
    } catch (e) {
      if (initialization.isStale) {
        return false;
      }
      playback.loading = false;
      WywLogger().e('${LogTag.player} 初始化播放器失败 url=$videoUrl', error: e);
      return false;
    }
    if (player == null || !_ownsInitialization(initialization, player)) {
      return false;
    }

    if (isDesktop()) {
      final freshStart = playback.volume == -1;
      if (freshStart) {
        muted = GStorage.getSetting(SettingsKeys.playerMuted);
        final remembered = GStorage.getSetting(SettingsKeys.defaultVolume);
        _preMuteVolume = remembered > 0 ? remembered : 100;
        playback.volume = muted ? 0 : remembered;
      }
      await setVolume(playback.volume);
      if (!_ownsInitialization(initialization, player)) {
        return false;
      }
    } else {
      await FlutterVolumeController.getVolume().then((value) {
        playback.volume = (value ?? 0.0) * 100;
      });
      if (!_ownsInitialization(initialization, player)) {
        return false;
      }

      await FlutterVolumeController.updateShowSystemUI(false);
      if (!_ownsInitialization(initialization, player)) {
        await FlutterVolumeController.updateShowSystemUI(true);
        return false;
      }

      FlutterVolumeController.addListener((volume) {
        if (player == null || !_ownsInitialization(initialization, player)) {
          return;
        }
        if (panel.volumeSeeking) {
          return;
        }
        playback.applyExternalVolume(volume * 100);
        if (!Platform.isAndroid && !panel.volumeSeeking) {
          panel.showVolume = true;
          hideVolumeUITimer?.cancel();
          hideVolumeUITimer = Timer(const Duration(seconds: 1), () {
            panel.showVolume = false;
            hideVolumeUITimer = null;
          });
        }
      }, category: AudioSessionCategory.playback, emitOnStart: false);
      if (!_ownsInitialization(initialization, player)) {
        return false;
      }
    }
    await setPlaybackSpeed(playback.playerSpeed);
    if (!_ownsInitialization(initialization, player)) {
      return false;
    }
    WywLogger().i('${LogTag.player} 播放器初始化完成 url=$videoUrl');
    playback.loading = false;
    // v2 History：注册当前播放 source，让 reporter 知道写到哪个 key。
    // 合流代理/local 播放时 videoUrl 是失效地址，用稳定的 historySourceId。
    HistoryProgressReporter().registerSource(
      sourceId: params.historySourceId ?? videoUrl,
      type: HistoryType.video,
      title: params.videoTitle,
      cover: params.videoCover,
    );

    return true;
  }

  bool _ownsInitialization(AsyncSession initialization, Player player) {
    return initialization.isActive && playback.isCurrentPlayer(player);
  }

  Future<void> setShader(SuperResolutionMode mode, {Player? player}) async {
    await playback.setShader(
      mode,
      player: player,
    );
  }

  Future<void> setPlaybackSpeed(double playerSpeed) async {
    await playback.setPlaybackSpeed(playerSpeed);
  }

  Future<void> setVolume(double value) async {
    await playback.setVolume(value);
    _clearMuteIfNeeded(value);
    _persistDesktopVolume(value);
  }

  void syncPlaybackState() {
    playback.syncPlaybackState();
    WywLogger().i(
        '${LogTag.player} 同步播放状态 positionMs=${playback.currentPosition.inMilliseconds} '
        'durationMs=${playback.duration.inMilliseconds}');
    // v2 History：position/duration 变化时上报（reporter 内部 5 秒节流）
    HistoryProgressReporter().reportProgress(
      positionMs: playback.currentPosition.inMilliseconds,
      durationMs: playback.duration.inMilliseconds,
    );
  }

  Future<void> playOrPause() async {
    await playback.playOrPause(pause: pause, play: play);
  }

  Future<void> seek(Duration duration) => seeking.seekTo(duration);

  Future<void> seekBy(Duration offset) => seeking.seekBy(offset);

  Future<void> pause({bool enableSync = true}) async {
    final player = playback.mediaPlayer;
    if (player == null) return;
    try {
      await player.pause();
    } catch (e) {
      WywLogger().d('${LogTag.player} 暂停播放失败（已忽略）', error: e);
      return;
    }
    playback.playing = false;
  }

  Future<void> play({bool enableSync = true}) async {
    final player = playback.mediaPlayer;
    if (player == null) return;
    try {
      await player.play();
    } catch (e) {
      WywLogger().d('${LogTag.player} 恢复播放失败（已忽略）', error: e);
      return;
    }
    playback.playing = true;
  }

  @override
  void dispose() {
    beginShutdown();
  }

  /// Starts the idempotent player shutdown without blocking route navigation.
  ///
  /// Native media and audio-session cleanup may finish after the route is
  /// removed. Immediate ownership detachment happens synchronously before this
  /// method returns.
  void beginShutdown() {
    _initializations.close();
    if (_shutdownFuture != null) {
      return;
    }
    final shutdown = _shutdownResources();
    _shutdownFuture = shutdown;
    unawaited(
      shutdown.catchError((Object error, StackTrace stackTrace) {
        WywLogger().e(
          '${LogTag.player} 异步释放播放器资源失败',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }

  Future<void> _shutdownResources() async {
    await Future.wait([
      _releasePlaybackResources(),
    ]);
  }

  Future<void> _releasePlaybackResources() async {
    hideVolumeUITimer?.cancel();
    _volumeGestureSyncTimer?.cancel();
    FlutterVolumeController.removeListener();
    await Future.wait([
      audioController.deactivate(),
      playback.stop(),
      _restoreSystemVolumeUi(),
    ]);
  }

  Future<void> _restoreSystemVolumeUi() async {
    try {
      await FlutterVolumeController.updateShowSystemUI(true);
    } catch (error, stackTrace) {
      WywLogger().w(
        '${LogTag.player} 恢复系统音量 UI 失败',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> stop() async {
    // v2 History：退出播放前强制 flush 一次 + 清理 source 上下文
    await HistoryProgressReporter().flush();
    HistoryProgressReporter().clearSource();
    _initializations.cancel();
    await _releasePlaybackResources();
  }

  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) async {
    return await playback.screenshot(format: format);
  }

  Future<Uint8List?> screenshotPng() async {
    return await playback.screenshotPng();
  }

  void setButtonForwardTime(int time) {
    playback.buttonSkipTime = time;
    GStorage.putSetting(SettingsKeys.buttonSkipTime, time);
  }

  void setArrowKeyForwardTime(int time) {
    playback.arrowKeySkipTime = time;
    GStorage.putSetting(SettingsKeys.arrowKeySkipTime, time);
  }

  Future<void> launchExternalPlayer() async {
    await externalPlayback.launch();
  }
}
