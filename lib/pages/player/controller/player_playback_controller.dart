// ignore_for_file: library_private_types_in_public_api
import 'package:wyw/services/storage/storage.dart';

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/pages/player/controller/player_aspect_ratio.dart';
import 'package:wyw/pages/player/controller/player_debug_controller.dart';
import 'package:wyw/pages/player/controller/player_super_resolution.dart';
import 'package:wyw/pages/player/controller/video_filter_controller.dart';
import 'package:wyw/services/shaders/shader_asset_service.dart';
import 'package:wyw/utils/constants.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mobx/mobx.dart';
import 'package:path_provider/path_provider.dart';
part 'player_playback_controller.g.dart';

class PlayerPlaybackController = _PlayerPlaybackController
    with _$PlayerPlaybackController;

final class _OwnedPlayer {
  _OwnedPlayer(this.player);

  final Player player;
  Future<void>? _disposeFuture;

  Future<void> dispose() {
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    try {
      await player.dispose();
    } catch (error, stackTrace) {
      WywLogger().e(
        '${LogTag.player} 释放播放器资源失败',
        error: error,
        stackTrace: stackTrace,
      );
      try {
        await player.stop();
      } catch (_) {
        // 静默可接受：dispose 失败后的兜底 stop，资源可能已释放，失败属常态
      }
    }
  }
}

abstract class _PlayerPlaybackController with Store {
  _PlayerPlaybackController({
    required this.shaderAssetService,
    required this.debug,
    required this.videoUrl,
  });

  final ShaderAssetService shaderAssetService;
  final PlayerDebugController debug;
  final String Function() videoUrl;

  _OwnedPlayer? _ownedPlayer;
  Player? get mediaPlayer => _ownedPlayer?.player;
  VideoController? videoController;

  bool hAenable = true;
  late String hardwareDecoder;
  bool androidEnableOpenSLES = true;
  bool lowMemoryMode = false;
  bool autoPlay = true;

  /// 调试模式：影响**下次创建播放器**时是否订阅 MPV 日志（见 `debug.setup`）。
  /// 面板「更多」tab 与设置页共用同一个存储键，因此必须是 observable，
  /// 否则面板改完不会自动重建（曾经靠一个私有 ValueNotifier 兜）。
  @observable
  bool playerDebugMode = false;

  /// 顶栏「跳过」按钮的快进秒数（长按可改）。面板「播放」tab 会直接改它，
  /// 同样必须是 observable。
  @observable
  int buttonSkipTime = 80;

  int arrowKeySkipTime = 10;

  /// 当前超分辨率模式
  @observable
  SuperResolutionMode superResolutionMode = SuperResolutionMode.off;

  /// 画面调节滤镜着色器的文件名前缀（参数用 `#define` 静态烘焙进文件）。
  ///
  /// 关键：**mpv 只按 "glsl-shaders 链的最终内容" 判断是否需要重载**——
  /// 同路径 `set`、或 `remove` + `append` 同一路径后链内容不变，mpv 都会
  /// 跳过重载（这正是"改完必须重进播放器才生效"的原因；`glsl-shader-opts`
  /// 运行时修改同样不触发重载，只在 shader 编译时读取）。因此每次调参都写
  /// 一个**全新文件名**（`video_filters_<n>.glsl`），remove 旧 + append 新，
  /// 链内容必然变化 → mpv 强制重新编译 → 滑杆实时生效。
  static const String _filterShaderPrefix = 'video_filters';

  /// 滑杆拖动节流：避免高频重载 shader。
  static const Duration _filterDebounceInterval = Duration(milliseconds: 120);

  /// 当前链中的滤镜 shader 文件名（null = 不在链中）。
  String? _filterShaderPath;

  /// 唯一文件名序号（每次调参 +1，保证链内容变化以触发重载）。
  int _filterShaderSeq = 0;

  Timer? _filterDebounce;
  Map<String, double>? _pendingFilterParams;

  @observable
  double volume = -1;

  /// 手势调节时的精确音量，避免 UI 节流导致累计误差
  double preciseVolume = -1;

  @observable
  bool loading = true;
  @observable
  bool playing = false;
  @observable
  bool isBuffering = true;
  @observable
  bool completed = false;
  @observable
  Duration currentPosition = Duration.zero;
  @observable
  Duration buffer = Duration.zero;
  @observable
  Duration duration = Duration.zero;
  @observable
  double playerSpeed = 1.0;

  bool isCurrentPlayer(Player player) {
    return identical(mediaPlayer, player);
  }

  Future<Player?> _discardIfNotCurrent(_OwnedPlayer candidate) async {
    if (identical(_ownedPlayer, candidate)) {
      return candidate.player;
    }
    await candidate.dispose();
    return null;
  }

  Future<void> _cancelDebugInfo() async {
    try {
      await debug.cancel();
    } catch (_) {
      // 静默可接受：停止时取消调试订阅，订阅可能已取消，失败属常态
    }
  }

  @action
  void resetForInit() {
    playing = false;
    loading = true;
    isBuffering = true;
    currentPosition = Duration.zero;
    buffer = Duration.zero;
    duration = Duration.zero;
    completed = false;
  }

  bool get playerPlaying {
    try {
      return mediaPlayer?.state.playing ?? false;
    } catch (_) {
      return false;
    }
  }

  bool get playerBuffering {
    try {
      return mediaPlayer?.state.buffering ?? false;
    } catch (_) {
      return false;
    }
  }

  bool get playerCompleted {
    try {
      return mediaPlayer?.state.completed ?? false;
    } catch (_) {
      return false;
    }
  }

  double get playerVolume {
    try {
      return mediaPlayer?.state.volume ?? volume;
    } catch (_) {
      return volume;
    }
  }

  Duration get playerPosition {
    try {
      return mediaPlayer?.state.position ?? currentPosition;
    } catch (_) {
      return currentPosition;
    }
  }

  Duration get playerBuffer {
    try {
      return mediaPlayer?.state.buffer ?? buffer;
    } catch (_) {
      return buffer;
    }
  }

  Duration get playerDuration {
    try {
      return mediaPlayer?.state.duration ?? duration;
    } catch (_) {
      return duration;
    }
  }

  Future<Player?> createVideoController(
    Map<String, String> httpHeaders,
    bool adBlockerEnabled, {
    required bool Function() canInstall,
    int offset = 0,
  }) async {
    superResolutionMode = SuperResolutionMode.fromStorageValue(
      GStorage.getSetting(SettingsKeys.defaultSuperResolutionMode),
    );
    hAenable = GStorage.getSetting(SettingsKeys.hAenable);
    androidEnableOpenSLES =
        GStorage.getSetting(SettingsKeys.androidEnableOpenSLES);
    hardwareDecoder = GStorage.getSetting(SettingsKeys.hardwareDecoder);
    autoPlay = GStorage.getSetting(SettingsKeys.autoPlay);
    lowMemoryMode = GStorage.getSetting(SettingsKeys.lowMemoryMode);
    playerDebugMode = GStorage.getSetting(SettingsKeys.playerDebugMode);

    if (!canInstall()) {
      return null;
    }
    final candidate = _OwnedPlayer(
      Player(
        configuration: PlayerConfiguration(
          bufferSize: lowMemoryMode ? 15 * 1024 * 1024 : 1500 * 1024 * 1024,
          osc: false,
          logLevel: MPVLogLevel.values[debug.playerLogLevel],
          adBlocker: adBlockerEnabled,
        ),
      ),
    );
    final player = candidate.player;
    if (!canInstall()) {
      await candidate.dispose();
      return null;
    }
    _ownedPlayer = candidate;

    try {
      debug.playerLog.clear();
      await debug.setup(
        player,
        isCurrentPlayer: isCurrentPlayer,
        playerDebugMode: playerDebugMode,
      );
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      var pp = player.platform as NativePlayer;
      // media-kit 默认启用硬盘作为双重缓存，这可以维持大缓存的前提下减轻内存压力
      // media-kit 内部硬盘缓存目录按照 Linux 配置，这导致该功能在其他平台上被损坏
      // 该设置可以在所有平台上正确启用双重缓存
      try {
        await pp.setProperty('demuxer-cache-dir', await _playerTempPath());
      } catch (e) {
        WywLogger()
            .d('${LogTag.player} 设置 mpv demuxer-cache-dir 失败（已忽略）', error: e);
      }
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      await pp.setProperty('af', 'scaletempo2=max-speed=8');
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }
      if (Platform.isAndroid) {
        await pp.setProperty('volume-max', '100');
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
        if (androidEnableOpenSLES) {
          await pp.setProperty('ao', 'opensles');
        } else {
          await pp.setProperty('ao', 'audiotrack');
        }
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      await player.setAudioTrack(
        AudioTrack.auto(),
      );
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      String? videoRenderer;
      if (Platform.isAndroid) {
        final String androidVideoRenderer =
            GStorage.getSetting(SettingsKeys.androidVideoRenderer);

        if (androidVideoRenderer == 'auto') {
          // Android 14 及以上使用基于 Vulkan 的 MPV GPU-NEXT 视频输出，着色器性能更好
          // GPU-NEXT 需要 Vulkan 1.2 支持
          // 避免 Android 13 及以下设备上部分机型 Vulkan 支持不佳导致的黑屏问题
          // wyw pinned media_kit 不再携带 PlatformEnvironmentService 桥
          // 假设目标设备 SDK >= 30（与 PlatformEnvironmentService.getAndroidSdkVersion 默认一致）
          const int androidSdkVersion = 30;
          if (!isCurrentPlayer(player)) {
            return await _discardIfNotCurrent(candidate);
          }
          if (androidSdkVersion >= 34) {
            videoRenderer = 'gpu-next';
          } else {
            videoRenderer = 'gpu';
          }
        } else {
          videoRenderer = androidVideoRenderer;
        }
      }

      if (videoRenderer == 'mediacodec_embed') {
        hAenable = true;
        hardwareDecoder = 'mediacodec';
        superResolutionMode = SuperResolutionMode.off;
      }

      videoController ??= VideoController(
        player,
        configuration: VideoControllerConfiguration(
          vo: videoRenderer,
          enableHardwareAcceleration: hAenable,
          // enableAndroidSurfaceProducer is unsupported on the wyw pinned
          // media_kit_video; flag removed from the configuration.
          hwdec: hAenable ? hardwareDecoder : 'no',
          androidAttachSurfaceAfterVideoParameters: false,
        ),
      );
      player.setPlaylistMode(PlaylistMode.none);
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      bool showPlayerError = GStorage.getSetting(SettingsKeys.showPlayerError);
      player.stream.error.listen((event) {
        if (showPlayerError) {
          if (!isCurrentPlayer(player)) {
            return;
          }
          if (event.toString().contains('Failed to open') && playerBuffering) {
            WywDialog.showToast(
                message: '加载失败, 请尝试更换其他视频来源', showActionButton: true);
          } else {
            WywDialog.showToast(
                message: '播放器内部错误 ${event.toString()} ${videoUrl()}',
                duration: const Duration(seconds: 5),
                showActionButton: true);
          }
        }
        WywLogger()
            .e('${LogTag.player} 播放器内部错误 videoUrl=${videoUrl()}', error: event);
      });

      // 新播放器的 glsl-shaders 链为空，滤镜"在链中"状态重置。
      _filterShaderPath = null;

      if (superResolutionMode != SuperResolutionMode.off) {
        await setShader(superResolutionMode, player: player);
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      // 应用当前画面调节滤镜（预设切换/编辑由 VideoFilterController 实时下发，
      // 这里只负责播放器新建/重开时把持久化的活动预设补上）。
      final filterVf = VideoFilterController.instance.activeVf;
      if (filterVf != null) {
        await _applyVideoFilterNow(filterVf, player: player);
        if (!isCurrentPlayer(player)) {
          return await _discardIfNotCurrent(candidate);
        }
      }

      await player.open(
        Media(videoUrl(),
            start: Duration(milliseconds: offset), httpHeaders: httpHeaders),
        play: autoPlay,
      );
      if (!isCurrentPlayer(player)) {
        return await _discardIfNotCurrent(candidate);
      }

      return player;
    } catch (error, stackTrace) {
      if (identical(_ownedPlayer, candidate)) {
        _ownedPlayer = null;
        videoController = null;
      }
      await candidate.dispose();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> setShader(SuperResolutionMode mode, {Player? player}) async {
    final currentPlayer = player ?? mediaPlayer;
    if (currentPlayer == null) return;
    try {
      final pp = currentPlayer.platform as NativePlayer;
      await pp.waitForPlayerInitialization;
      await pp.waitForVideoControllerInitializationIfAttached;
      if (!identical(mediaPlayer, currentPlayer)) {
        return;
      }
      superResolutionMode = mode;
      await _applyShaderChain(pp);
    } catch (e) {
      WywLogger().w('${LogTag.player} 设置着色器失败 mode=${mode.name}', error: e);
    }
  }

  /// 应用画面调节滤镜；[params] 为 null 时关闭滤镜。
  ///
  /// 由 [VideoFilterController] 在切换/编辑/删除预设时实时调用（暂停中也
  /// 会重渲当前帧）；播放器新建时由初始化逻辑用 [_applyVideoFilterNow] 补一次
  /// 持久化的活动预设（不走节流，立即生效）。
  ///
  /// 与超分辨率共存：Anime4K 组和 video_filters.glsl 合并成一条 glsl-shaders
  /// 链。播放中参数变化把当前值**烘焙**进 shader 文件（`#define`），再用
  /// `remove` + `append` 强制 mpv 重新加载该项——**路径不变时 `set` 会被 mpv
  /// 判定为"链无变化"而跳过重载**（这正是"改完必须重进播放器才生效"的原因），
  /// 而 `glsl-shader-opts` 运行时修改同样不触发重载（只在 shader 编译时读取）。
  Future<void> setVideoFilterParams(
    Map<String, double>? params, {
    Player? player,
  }) async {
    _pendingFilterParams = params;
    _filterDebounce?.cancel();
    _filterDebounce = Timer(_filterDebounceInterval, () {
      unawaited(_applyVideoFilterNow(
        _pendingFilterParams,
        player: player,
        rebuildChain: false,
      ));
    });
  }

  /// 立即应用滤镜参数（初始化路径走 [rebuildChain]=true，整链 `set` 一次；
  /// 播放中走节流版且 [rebuildChain]=false，烘焙文件后强制重载该项）。
  Future<void> _applyVideoFilterNow(
    Map<String, double>? params, {
    Player? player,
    bool rebuildChain = true,
  }) async {
    final currentPlayer = player ?? mediaPlayer;
    if (currentPlayer == null) return;
    try {
      final pp = currentPlayer.platform as NativePlayer;
      await pp.waitForPlayerInitialization;
      if (!identical(mediaPlayer, currentPlayer)) {
        return;
      }
      if (params == null) {
        // 关闭：把当前 shader 移出链（链内容变化 → mpv 重载）并删除文件。
        final old = _filterShaderPath;
        _filterShaderPath = null;
        if (old != null) {
          await pp.command([
            'change-list',
            'glsl-shaders',
            'remove',
            _filterShaderAbsPath(old),
          ]);
          await _deleteFilterShader(old);
        }
        if (rebuildChain) {
          await _applyShaderChain(pp);
        }
      } else {
        final old = _filterShaderPath;
        final next = await _writeFilterShader(params);
        if (rebuildChain && old == null) {
          // 初始化（或滤镜尚未进链）：整链一次 set。
          _filterShaderPath = next;
          await _applyShaderChain(pp);
        } else {
          // 播放中：remove 旧路径 + append 新路径——链内容必然变化，
          // mpv 强制重新编译（同路径会被判定为"无变化"而跳过）。
          if (old != null) {
            await pp.command([
              'change-list',
              'glsl-shaders',
              'remove',
              _filterShaderAbsPath(old),
            ]);
          }
          await pp.command([
            'change-list',
            'glsl-shaders',
            'append',
            _filterShaderAbsPath(next),
          ]);
          _filterShaderPath = next;
          if (old != null) {
            await _deleteFilterShader(old);
          }
        }
      }
      // 诊断：确认下发确实到达当前播放器（播放中不生效时据此区分
      // "链路断" 与 "mpv 侧未重绘"）。
      WywLogger().w(
        '${LogTag.player} 画面滤镜已下发 params=$params '
        'player=${identityHashCode(currentPlayer)} '
        'playing=${currentPlayer.state.playing} shader=$_filterShaderPath',
      );
      // 暂停中 media_kit 不产生新帧（渲染循环无事可做），强制重绘当前帧。
      if (identical(mediaPlayer, currentPlayer)) {
        await pp.command(['redraw']);
      }
    } catch (e) {
      WywLogger().w('${LogTag.player} 设置画面滤镜失败', error: e);
    }
  }

  String _filterShaderAbsPath(String fileName) =>
      '${shaderAssetService.shadersDirectory.path}'
      '${Platform.pathSeparator}$fileName';

  /// 把当前参数烘焙进一个新的唯一文件名（返回文件名）。
  Future<String> _writeFilterShader(Map<String, double> params) async {
    _filterShaderSeq++;
    final fileName = '${_filterShaderPrefix}_$_filterShaderSeq.glsl';
    await File(_filterShaderAbsPath(fileName))
        .writeAsString(_filterShaderSource(params));
    return fileName;
  }

  /// 删除上一个临时 shader 文件（失败可忽略）。
  Future<void> _deleteFilterShader(String fileName) async {
    try {
      final file = File(_filterShaderAbsPath(fileName));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 静默可接受：临时文件清理失败不影响功能
    }
  }

  /// 生成参数烘焙版滤镜着色器源码（`#define` 静态参数，Anime4K v3 同款写法）。
  ///
  /// 显式提升 sampler/float 精度：libmpv 旧 GPU renderer 默认把 sampler 声明为
  /// `mediump`，复杂运算下会出现全局偏色（media-kit#1438 / Kazumi#1547）。
  String _filterShaderSource(Map<String, double> params) {
    final sharpness = params['wyw_filter_sharpness'] ?? 0.0;
    final contrast = params['wyw_filter_contrast'] ?? 1.0;
    final saturation = params['wyw_filter_saturation'] ?? 1.0;
    final brightness = params['wyw_filter_brightness'] ?? 0.0;
    final gamma = params['wyw_filter_gamma'] ?? 1.0;
    return '''
// wyw 画面调节滤镜（参数烘焙版）
//!DESC wyw 画面调节滤镜
//!HOOK MAIN
//!BIND HOOKED

#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
precision highp sampler2D;
#endif

#define WYW_SHARPNESS ${sharpness.toStringAsFixed(3)}
#define WYW_CONTRAST ${contrast.toStringAsFixed(3)}
#define WYW_SATURATION ${saturation.toStringAsFixed(3)}
#define WYW_BRIGHTNESS ${brightness.toStringAsFixed(3)}
#define WYW_GAMMA ${gamma.toStringAsFixed(3)}

vec4 hook() {
    vec4 c = HOOKED_tex(HOOKED_pos);
    vec3 rgb = c.rgb;

    // 亮度（加法，与 ffmpeg eq 同序、先做）
    rgb += WYW_BRIGHTNESS;

    // 对比度（围绕 0.5 缩放）
    rgb = (rgb - 0.5) * WYW_CONTRAST + 0.5;

    // 饱和度（按 luma 混合）
    float luma = dot(vec3(0.299, 0.587, 0.114), rgb);
    rgb = mix(vec3(luma), rgb, WYW_SATURATION);

    // 伽马（ffmpeg eq 语义：pow(1/gamma)，>1 变亮）
    rgb = pow(max(rgb, vec3(0.0)), vec3(1.0 / WYW_GAMMA));

    // 锐化（unsharp mask：原图 − 3×3 盒式模糊后按系数加回）
    if (WYW_SHARPNESS > 0.0001) {
        vec2 pt = vec2(1.0) / HOOKED_size;
        vec3 blurred =
            HOOKED_tex(HOOKED_pos + vec2(-pt.x, -pt.y)).rgb +
            HOOKED_tex(HOOKED_pos + vec2(0.0, -pt.y)).rgb +
            HOOKED_tex(HOOKED_pos + vec2(pt.x, -pt.y)).rgb +
            HOOKED_tex(HOOKED_pos + vec2(-pt.x, 0.0)).rgb +
            c.rgb +
            HOOKED_tex(HOOKED_pos + vec2(pt.x, 0.0)).rgb +
            HOOKED_tex(HOOKED_pos + vec2(-pt.x, pt.y)).rgb +
            HOOKED_tex(HOOKED_pos + vec2(0.0, pt.y)).rgb +
            HOOKED_tex(HOOKED_pos + vec2(pt.x, pt.y)).rgb;
        blurred /= 9.0;
        rgb += (rgb - blurred) * WYW_SHARPNESS;
    }

    return vec4(rgb, c.a);
}
''';
  }

  /// 按「超分辨率 Anime4K 组 + 画面调节滤镜」构建并下发整条 glsl-shaders 链。
  ///
  /// 超分辨率与滤镜任一侧变化都走这里（`set` 整链替换；两侧都关则 `clr`），
  /// 保证二者可同时生效而不会相互覆盖。
  Future<void> _applyShaderChain(NativePlayer pp) async {
    final shaders = <String>[];
    switch (superResolutionMode) {
      case SuperResolutionMode.efficiency:
        shaders.addAll(mpvAnime4KShadersLite);
        break;
      case SuperResolutionMode.quality:
        shaders.addAll(mpvAnime4KShaders);
        break;
      case SuperResolutionMode.off:
        break;
    }
    if (_filterShaderPath != null) {
      shaders.add(_filterShaderPath!);
    }
    if (shaders.isEmpty) {
      await pp.command(['change-list', 'glsl-shaders', 'clr', '']);
    } else {
      await pp.command([
        'change-list',
        'glsl-shaders',
        'set',
        _buildShadersAbsolutePath(
          shaderAssetService.shadersDirectory.path,
          shaders,
        ),
      ]);
    }
  }

  Future<void> setPlaybackSpeed(double playerSpeed) async {
    this.playerSpeed = playerSpeed;
    try {
      mediaPlayer!.setRate(playerSpeed);
    } catch (e) {
      WywLogger().e('${LogTag.player} 设置播放速度失败 speed=$playerSpeed', error: e);
    }
  }

  Future<void> setVolume(double value) async {
    updateVolume(value);
    await syncVolumeToDevice(preciseVolume >= 0 ? preciseVolume : volume);
  }

  @action
  void updateVolume(double value) {
    value = value.clamp(0.0, 100.0);
    preciseVolume = value;
    if (volume.toInt() == value.toInt()) {
      return;
    }
    volume = value;
  }

  /// 外部来源（硬件键、系统面板等）变更音量时同步，并清除手势缓存
  @action
  void applyExternalVolume(double value) {
    value = value.clamp(0.0, 100.0);
    preciseVolume = -1;
    volume = value;
  }

  void invalidatePreciseVolume() {
    preciseVolume = -1;
  }

  // ─── helpers ───
  bool _isDesktop() =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<String> _playerTempPath() async {
    if (_isDesktop()) {
      // Linux/macOS: media_kit expects the standard cache dir.
      try {
        final dir = await getApplicationCacheDirectory();
        return dir.path;
      } catch (_) {
        return Directory.systemTemp.path;
      }
    }
    return Directory.systemTemp.path;
  }

  String _buildShadersAbsolutePath(
    String shadersDir,
    List<String> shaders,
  ) {
    final sep = Platform.pathSeparator;
    return shaders.map((s) => '$shadersDir$sep$s').join(
          Platform.isWindows ? ';' : ':',
        );
  }

  Future<void> syncVolumeToDevice([double? value]) async {
    final vol = (value ?? volume).clamp(0.0, 100.0);
    try {
      if (_isDesktop()) {
        await mediaPlayer!.setVolume(vol);
      } else {
        await FlutterVolumeController.setVolume(vol / 100);
      }
    } catch (_) {
      // 静默可接受：音量同步为 best-effort，手势期间高频触发，失败属常态
    }
  }

  @action
  void syncPlaybackState() {
    final player = mediaPlayer;
    if (player == null) return;

    final PlayerState state;
    try {
      state = player.state;
    } catch (_) {
      return;
    }
    if (playing != state.playing) {
      playing = state.playing;
    }
    if (isBuffering != state.buffering) {
      isBuffering = state.buffering;
    }
    if (currentPosition != state.position) {
      currentPosition = state.position;
    }
    if (buffer != state.buffer) {
      buffer = state.buffer;
    }
    if (duration != state.duration) {
      duration = state.duration;
    }
    if (completed != state.completed) {
      completed = state.completed;
    }
  }

  Future<void> playOrPause({
    required Future<void> Function() pause,
    required Future<void> Function() play,
  }) async {
    if (playerPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  // ─── facade-facing shortcuts ────────────────────────────────────────────
  Future<void> play() async {
    final player = mediaPlayer;
    if (player == null) return;
    try {
      await player.play();
    } catch (e) {
      WywLogger().d('${LogTag.player} 播放失败（已忽略）', error: e);
    }
  }

  Future<void> pause({bool enableSync = true}) async {
    final player = mediaPlayer;
    if (player == null) return;
    try {
      await player.pause();
    } catch (e) {
      WywLogger().d('${LogTag.player} 暂停失败（已忽略）', error: e);
    }
  }

  Future<void> seek(Duration position) async {
    final player = mediaPlayer;
    if (player == null) return;
    try {
      await player.seek(position);
    } catch (e) {
      WywLogger()
          .d('${LogTag.player} seek 失败（已忽略） position=$position', error: e);
    }
  }

  /// Open (or re-open) the current media player on a URL.
  Future<void> open({required String videoUrl, int offset = 0}) async {
    final player = mediaPlayer;
    if (player == null) return;
    try {
      await player.open(Media(videoUrl), play: autoPlay);
      if (offset > 0) {
        await player.seek(Duration(milliseconds: offset));
      }
    } catch (e) {
      WywLogger().e(
        '${LogTag.player} 打开视频失败 videoUrl=$videoUrl',
        error: e,
      );
    }
  }

  PlayerAspectRatio _aspectRatio = PlayerAspectRatio.automatic;
  PlayerAspectRatio get aspectRatio => _aspectRatio;
  void setAspectRatio(PlayerAspectRatio ratio) {
    _aspectRatio = ratio;
  }

  /// Apply the current [superResolutionMode] to the underlying mpv player.
  void setSuperResolutionMode(SuperResolutionMode mode) {
    superResolutionMode = mode;
    setShader(mode);
  }

  Future<void> stop() async {
    final ownedPlayer = _ownedPlayer;
    _ownedPlayer = null;
    videoController = null;
    playing = false;
    loading = true;
    // media_kit stops playback as part of disposal before releasing native
    // resources. Debug subscriptions can be cancelled concurrently.
    await Future.wait([
      ownedPlayer?.dispose() ?? Future<void>.value(),
      _cancelDebugInfo(),
    ]);
  }

  Future<Uint8List?> screenshotPng() async {
    final player = mediaPlayer;
    if (player == null) {
      return null;
    }
    // Encode the captured frame natively; PlayerState dimensions may be stale.
    return player.safeScreenshot(format: 'image/png');
  }
}
