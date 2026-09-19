// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'package:flutter/widgets.dart' show Orientation;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/download/download_controller.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/services/video_source/resolution_service.dart';
import 'package:wyw/services/video_source/services.dart';
import 'package:mobx/mobx.dart';
import 'package:wyw/services/history/history_progress_reporter.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/history_type.dart';
import 'package:wyw/services/storage/video_play_model.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/utils/device.dart';
import 'package:wyw/utils/http_headers.dart';
import 'package:wyw/utils/async_session.dart';
import 'package:wyw/services/platform/display_mode_service.dart';

import '../player/player_controller.dart';
import 'video_route_args.dart';

part 'video_controller.g.dart';

class VideoPageController = _VideoPageController with _$VideoPageController;

/// 视频播放页控制器（v3，结构化进入 + 逐集/逐源播放）。
///
/// 进入方式：
///   - 播放进入：`VideoPageRouteArgs` 携带完整播放源列表（`configure` 注入）
///
/// 播放：
///   - `playEpisode` 按 sources[currentSource].episodes[currentEpisode] 分发
///   - `resolve` 路径执行插件方法取真实路径；已解析直链回填供进度持久化
///
/// 进度：
///   - `reportProgress` 记录当前集 position/duration，播放页/player 调用
///   - `buildProgress` 组装整部剧 `VideoPlaybackProgress`（含每集独立进度与直链）
///   - `onProgressChanged` 回调把 progress 交给调用方写历史
abstract class _VideoPageController with Store {
  // ===== 结构化进入参数（configure 注入） =====

  /// 视频唯一 id（历史 key 用）；未走 configure 的旧入口为空串。
  String videoId = '';
  String videoTitle = '';
  String videoCover = '';
  String sourceKey = '';

  /// 完整播放源列表（含每集已解析直链与独立进度）。
  List<VideoPlaySource> sources = const [];

  /// 当前线路（0-based）。
  int currentSourceIndex = 0;

  /// 当前集（0-based）。
  int currentEpisodeIndex = 0;

  /// 续播位置（毫秒）：从历史回填；插件进入时 args.offsetMs 为 0，用它续播。
  int resumeOffsetMs = 0;

  /// 进度回吐回调（调用方据此写进度历史）。
  void Function(VideoPlaybackProgress progress)? onProgressChanged;

  // ===== 兼容旧字段 =====

  /// 当前集实际播放地址（直链或本地路径）。
  String videoUrl = '';

  /// 当前实际用于播放的媒体直链；网页嗅探成功后写入。
  String resolvedVideoUrl = '';

  /// 本次进入播放页是否允许自动切换到「播放即下载」本地代理。
  bool allowProxyPlayback = true;

  /// 播放方式（决策层产出；播放页只执行不再决策）。
  VideoPlayMode playMode = VideoPlayMode.online;

  @observable
  bool loading = true;

  @observable
  String? errorMessage;

  @observable
  bool isFullscreen = false;

  @observable
  bool isOrientationLocked = false;

  @observable
  bool isCommentsAscending = false;

  final AsyncSessionOwner _playbackSessions = AsyncSessionOwner();

  @observable
  bool isPip = false;

  /// 统一解析服务（解析层）：resolve/page 型的插件解析与 WebView 嗅探。
  ResolutionService? _resolutionService;

  @observable
  bool isOfflineMode = false;

  final StreamController<String> _logStreamController =
      StreamController<String>.broadcast();

  Stream<String> get logStream => _logStreamController.stream;

  StreamSubscription<String>? _logSubscription;

  // ===== 逐集状态（写进度时合并进 sources） =====

  /// key = '$sourceIndex:$episodeIndex' → 该集已解析直链。
  final Map<String, String> _resolvedUrls = {};
  final Map<String, int> _positions = {};
  final Map<String, int> _durations = {};
  final Map<String, DateTime> _lastPlayedAt = {};

  // ===== configure / 查询 =====

  /// 用路由参数注入播放上下文。
  void configure(VideoPageRouteArgs args) {
    videoId = args.videoId;
    videoTitle = args.title;
    videoCover = args.cover;
    sourceKey = args.sourceKey ?? '';
    sources = args.sources;
    currentSourceIndex = args.initialSource >= 0
        ? args.initialSource.clamp(0, sources.isEmpty ? 0 : sources.length - 1)
        : 0;
    currentEpisodeIndex = args.initialEpisode >= 0 ? args.initialEpisode : 0;
    onProgressChanged = args.onProgressChanged;
    playMode = args.playMode;
    allowProxyPlayback = args.allowProxyPlayback;
    _resolvedUrls.clear();
    _positions.clear();
    _durations.clear();
    _lastPlayedAt.clear();
    resumeOffsetMs = 0;
    // 从历史记录回填各集观看进度（不覆盖插件最新剧集列表）
    _applyHistoryProgress();
  }

  /// 进入时从历史记录查询一次，把历史进度按「线路+集数 index」回填到
  /// 当前（插件最新）的 sources 对应集上；并定位到上次观看的集 + 续播位置。
  ///
  /// 不回填则 sources 里各集 positionMs 都是 0，选集面板看不到历史进度、
  /// 也无法续播（插件进入 args 不带 offsetMs）。
  void _applyHistoryProgress() {
    final historySourceId = sourceKey.isEmpty ? videoId : '$sourceKey:$videoId';
    final entry = HistoryProgressReporter()
        .findEntry(type: HistoryType.video, sourceId: historySourceId);
    if (entry == null) return;
    final history = VideoPlaybackProgress.fromMap(entry.progress);

    // 1) 把历史每集进度合并进插件最新列表（只回填状态字段，不动 name/path）
    final merged = <VideoPlaySource>[];
    for (var s = 0; s < sources.length; s++) {
      final src = sources[s];
      final histSrc = s < history.sources.length ? history.sources[s] : null;
      final eps = <VideoPlayEpisode>[];
      for (var e = 0; e < src.episodes.length; e++) {
        final ep = src.episodes[e];
        final histEp = (histSrc != null && e < histSrc.episodes.length)
            ? histSrc.episodes[e]
            : null;
        eps.add(ep.copyWith(
          positionMs: histEp?.positionMs ?? ep.positionMs,
          durationMs: histEp?.durationMs ?? ep.durationMs,
          resolvedUrl: histEp?.resolvedUrl ?? ep.resolvedUrl,
          lastPlayedAt: histEp?.lastPlayedAt ?? ep.lastPlayedAt,
        ));
      }
      merged.add(VideoPlaySource(name: src.name, episodes: eps));
    }
    sources = merged;

    // 2) 续播位置 = 当前集（args 指定的初始集）在历史中的 positionMs
    resumeOffsetMs = currentEpisode?.positionMs ?? 0;
  }

  /// 当前集（夹取到合法范围；无集返回 null）。
  VideoPlayEpisode? get currentEpisode {
    if (sources.isEmpty) return null;
    final s = currentSourceIndex.clamp(0, sources.length - 1);
    final src = sources[s];
    if (src.episodes.isEmpty) return null;
    final e = currentEpisodeIndex.clamp(0, src.episodes.length - 1);
    return src.episodes[e];
  }

  /// 当前集的持久化 key。
  String get _currentKey => '$currentSourceIndex:$currentEpisodeIndex';

  /// 当前线路是否存在上一集（播放器面板「上一集」按钮可用态）。
  bool get hasPreviousEpisode {
    if (sources.isEmpty) return false;
    final s = currentSourceIndex.clamp(0, sources.length - 1);
    if (sources[s].episodes.isEmpty) return false;
    return currentEpisodeIndex > 0;
  }

  /// 当前线路是否存在下一集（播放器面板「下一集」按钮可用态）。
  bool get hasNextEpisode {
    if (sources.isEmpty) return false;
    final s = currentSourceIndex.clamp(0, sources.length - 1);
    final eps = sources[s].episodes;
    if (eps.isEmpty) return false;
    final e = currentEpisodeIndex.clamp(0, eps.length - 1);
    return e < eps.length - 1;
  }

  /// 播放当前线路的相邻集（delta = -1 上一集 / 1 下一集）。
  ///
  /// 越界（已是第一集/最后一集）时不动当前播放并返回 false；
  /// 跨线路切换请走选集面板。
  Future<bool> playAdjacentEpisode(
    int delta, {
    required PlayerController playerController,
  }) async {
    if (sources.isEmpty) return false;
    final s = currentSourceIndex.clamp(0, sources.length - 1);
    final eps = sources[s].episodes;
    if (eps.isEmpty) return false;
    final target = currentEpisodeIndex.clamp(0, eps.length - 1) + delta;
    if (target < 0 || target >= eps.length) return false;
    await playEpisode(
      sourceIndex: s,
      episodeIndex: target,
      playerController: playerController,
    );
    return true;
  }

  // ===== 播放 =====

  /// 播放指定（或当前）集。
  ///
  /// [offset] 为显式续播位置（毫秒）；未指定时按该集历史进度续播。
  /// [forceReresolve] 为 true 时清除该集直链缓存并强制重走解析
  ///（「重新解析」按钮语义）。
  Future<void> playEpisode({
    int? sourceIndex,
    int? episodeIndex,
    int? offset,
    required PlayerController playerController,
    bool forceReresolve = false,
  }) async {
    if (sources.isEmpty) {
      errorMessage = '无可播放资源';
      loading = false;
      return;
    }
    currentSourceIndex =
        (sourceIndex ?? currentSourceIndex).clamp(0, sources.length - 1);
    final src = sources[currentSourceIndex];
    if (src.episodes.isEmpty) {
      errorMessage = '该线路无剧集';
      loading = false;
      return;
    }
    currentEpisodeIndex =
        (episodeIndex ?? currentEpisodeIndex).clamp(0, src.episodes.length - 1);

    final ep = src.episodes[currentEpisodeIndex];
    if (forceReresolve) {
      // 「重新解析」：清除该集直链缓存，强制重走解析/嗅探
      _resolvedUrls.remove(_currentKey);
      final cleared = [...src.episodes];
      cleared[currentEpisodeIndex] = ep.copyWith(resolvedUrl: '');
      sources[currentSourceIndex] =
          VideoPlaySource(name: src.name, episodes: cleared);
    }
    final currentEp = sources[currentSourceIndex].episodes[currentEpisodeIndex];
    WywLogger().i('${LogTag.player} 播放剧集 s=$currentSourceIndex '
        'e=$currentEpisodeIndex path=${currentEp.path.type.value} '
        'mode=${playMode.name} name=${currentEp.name}');

    // 开启新一轮播放尝试：先清掉上一次的失败状态，保证解析失败后
    // 再点「重新解析」时界面能回到加载态（而不是停在旧错误页）。
    errorMessage = null;
    loading = true;

    // 本地文件：直接本地播放
    if (ep.path.type == PlayPathType.local) {
      await playLocalFile(ep.path.url,
          playerController: playerController, offset: offset ?? 0);
      return;
    }

    // 下载预检：该集已下载完成且本地文件存在 → 直接本地播放
    final downloadController = inject<DownloadController>();
    final localPath = downloadController.findLocalVideoPathByIdentity(
      sourceKey: sourceKey,
      videoId: videoId,
      sourceIndex: currentSourceIndex,
      episodeIndex: currentEpisodeIndex,
    );
    if (localPath != null && localPath.isNotEmpty) {
      WywLogger().i('${LogTag.player} 该集已下载，播放本地文件 localPath=$localPath');
      await playLocalFile(localPath,
          playerController: playerController, offset: offset ?? 0);
      return;
    }

    // 统一播放地址：缓存直链 >（合流）任务直链 > direct 型 url > 解析
    String playUrl;
    var playOffset = offset ?? 0;
    if (currentEp.resolvedUrl.isNotEmpty) {
      // 已解析直链缓存：直接使用；失效时由用户经「重新解析」强制重走解析
      playUrl = currentEp.resolvedUrl;
    } else if (playMode == VideoPlayMode.merge) {
      // 合流：优先直用进行中任务的新鲜直链（免解析快路径）
      final taskEpisode = inject<DownloadController>().findEpisodeByIdentity(
        sourceKey: sourceKey,
        videoId: videoId,
        sourceIndex: currentSourceIndex,
        episodeIndex: currentEpisodeIndex,
      );
      final taskUrl = taskEpisode?.networkM3u8Url ?? '';
      if (taskUrl.isNotEmpty) {
        playUrl = taskUrl;
      } else {
        // 预创建解析中任务：解析也是下载生命周期的一部分，下载页立即可见
        await inject<DownloadController>().prepareStructuredEpisode(
          sourceKey: sourceKey,
          videoId: videoId,
          title: videoTitle,
          cover: videoCover,
          sourceIndex: currentSourceIndex,
          episodeIndex: currentEpisodeIndex,
          episodeName: currentEp.name,
          sourceName: src.name,
        );
        final source = await _resolveMedia(currentEp.path, offset: playOffset);
        if (source == null) {
          // 失败/取消：_resolveMedia 内已置 errorMessage 并停止 loading
          //（取消保持静默，与页面关闭时的取消行为一致）
          await inject<DownloadController>().failPreparedEpisode(
            sourceKey: sourceKey,
            videoId: videoId,
            sourceIndex: currentSourceIndex,
            episodeIndex: currentEpisodeIndex,
            message: errorMessage ?? '解析播放地址失败',
          );
          return;
        }
        playUrl = source.url;
        playOffset = source.offset;
      }
    } else if (currentEp.path.type == PlayPathType.direct) {
      playUrl = currentEp.path.url;
    } else {
      // resolve / page 型：统一解析（插件逻辑 → 必要时 WebView 嗅探）
      final source = await _resolveMedia(currentEp.path, offset: playOffset);
      if (source == null) {
        // 失败/取消：_resolveMedia 内已置 errorMessage 并停止 loading
        //（取消保持静默，与页面关闭时的取消行为一致）
        return;
      }
      playUrl = source.url;
      playOffset = source.offset;
    }

    if (playUrl.isNotEmpty) {
      // 回填该集直链（供进度持久化）
      _resolvedUrls[_currentKey] = playUrl;
    }

    // 合流：确保下载任务存在（幂等，已完成跳过），随后经静默挂靠走本地代理
    if (playMode == VideoPlayMode.merge) {
      await inject<DownloadController>().downloadStructuredEpisode(
        sourceKey: sourceKey,
        videoId: videoId,
        title: videoTitle,
        cover: videoCover,
        sourceIndex: currentSourceIndex,
        episodeIndex: currentEpisodeIndex,
        episodeName: currentEp.name,
        sourceName: src.name,
        resolvedUrl: playUrl,
      );
    }

    await _playDirectUrl(playUrl, playOffset,
        playerController: playerController);
  }

  /// 统一解析入口：确保解析服务实例与日志订阅就绪，把解析异常映射为页面状态。
  ///
  /// 返回 null 表示解析失败或被取消：
  /// - timeout/异常 → `errorMessage` 已置且 `loading=false`；
  /// - 取消 → 保持原状静默返回（与页面关闭时的取消行为一致）。
  Future<VideoSource?> _resolveMedia(
    PlayResourcePath path, {
    required int offset,
  }) async {
    _resolutionService ??=
        ResolutionService(pluginController: inject<PluginController>());
    await _logSubscription?.cancel();
    _logSubscription = _resolutionService!.onLog.listen((log) {
      if (!_logStreamController.isClosed) {
        _logStreamController.add(log);
      }
    });
    try {
      return await _resolutionService!.resolve(path, offset: offset);
    } on VideoSourceNotFoundException {
      loading = false;
      errorMessage = '解析播放地址失败';
    } on VideoSourceTimeoutException {
      loading = false;
      errorMessage = '视频解析超时，请重试';
    } on VideoSourceCancelledException {
      WywLogger().i('${LogTag.player} 视频解析已取消 path=${path.url}');
    } catch (e) {
      loading = false;
      errorMessage = '视频解析失败：${e.toString()}';
      WywLogger().e('${LogTag.player} 视频解析失败 path=${path.url}', error: e);
    }
    return null;
  }

  /// 下载指定集（sourceIndex/episodeIndex 0-based）。
  ///
  /// 下载不负责解析：先经解析服务拿到成品直链，再交给下载队列。
  /// 生命周期三段式：预创建（resolving，下载页立即可见）→ 解析（本页解析，
  /// 日志进调试台）→ 入队（downloading）/ 标记失败。
  Future<void> downloadEpisode(int sourceIndex, int episodeIndex) async {
    if (sources.isEmpty) return;
    final s = sourceIndex.clamp(0, sources.length - 1);
    final src = sources[s];
    if (src.episodes.isEmpty) return;
    final e = episodeIndex.clamp(0, src.episodes.length - 1);
    final ep = src.episodes[e];
    final downloadController = inject<DownloadController>();

    var mediaUrl = ep.resolvedUrl.isNotEmpty ? ep.resolvedUrl : '';
    final needsResolve =
        mediaUrl.isEmpty && ep.path.type != PlayPathType.direct;
    if (needsResolve) {
      await downloadController.prepareStructuredEpisode(
        sourceKey: sourceKey,
        videoId: videoId,
        title: videoTitle,
        cover: videoCover,
        sourceIndex: s,
        episodeIndex: e,
        episodeName: ep.name,
        sourceName: src.name,
      );
    } else if (mediaUrl.isEmpty) {
      mediaUrl = ep.path.url;
    }
    if (needsResolve) {
      final source = await _resolveMedia(ep.path, offset: 0);
      if (source == null || source.url.isEmpty) {
        WywLogger().w('${LogTag.player} 下载前解析播放地址失败 s=$s e=$e');
        await downloadController.failPreparedEpisode(
          sourceKey: sourceKey,
          videoId: videoId,
          sourceIndex: s,
          episodeIndex: e,
          message: errorMessage ?? '解析播放地址失败',
        );
        loading = false;
        return;
      }
      mediaUrl = source.url;
      // 回填该集直链（供进度持久化）
      _resolvedUrls['$s:$e'] = mediaUrl;
    }
    if (mediaUrl.isEmpty) {
      WywLogger().w('${LogTag.player} 该集缺少可下载地址 s=$s e=$e');
      errorMessage = '该集缺少可下载的播放地址';
      loading = false;
      return;
    }

    await downloadController.downloadStructuredEpisode(
      sourceKey: sourceKey,
      videoId: videoId,
      title: videoTitle,
      cover: videoCover,
      sourceIndex: s,
      episodeIndex: e,
      episodeName: ep.name,
      sourceName: src.name,
      resolvedUrl: mediaUrl,
    );
  }

  /// 播放本地已下载的文件（离线模式），跳过 WebView 网络解析。
  Future<void> playLocalFile(
    String localPath, {
    required PlayerController playerController,
    int offset = 0,
  }) async {
    isOfflineMode = true;
    resolvedVideoUrl = '';
    loading = true;
    errorMessage = null;

    await playerController.stop();

    WywLogger().i('${LogTag.player} 播放本地文件 localPath=$localPath');

    // 历史 key 用下载剧集的稳定直链（networkM3u8Url），避免本地路径
    // 变化后历史无法反查到已完成下载；无对应记录时回退本地路径。
    String historyKey = localPath;
    try {
      final episode = inject<DownloadController>().findEpisodeByLocalPath(
        localPath,
      );
      if (episode != null && episode.networkM3u8Url.isNotEmpty) {
        historyKey = episode.networkM3u8Url;
      }
    } catch (e) {
      WywLogger().d('${LogTag.player} 反查下载记录获取历史 key 失败（已忽略）', error: e);
    }

    final resumeOffset = offset > 0
        ? offset
        : _resolveResumeOffset(historyKey, 0, playerController);

    final params = PlaybackInitParams(
      videoUrl: localPath,
      offset: resumeOffset,
      httpHeaders: const {},
      adBlockerEnabled: false,
      referer: '',
      videoTitle: videoTitle,
      videoCover: videoCover,
      historySourceId: historyKey,
    );
    try {
      final initialized = await playerController.init(params);
      loading = false;
      if (!initialized) {
        errorMessage = '本地播放初始化失败';
        WywLogger().e('${LogTag.player} 本地播放初始化返回 false localPath=$localPath');
      }
    } catch (e) {
      loading = false;
      errorMessage = '本地播放失败：${e.toString()}';
      WywLogger().e('${LogTag.player} 本地播放失败 localPath=$localPath', error: e);
    }
  }

  /// 直链直接播放（不经 WebView 嗅探）。
  Future<void> _playDirectUrl(
    String url,
    int offset, {
    required PlayerController playerController,
  }) async {
    loading = true;
    errorMessage = null;

    resolvedVideoUrl = url;
    WywLogger().i('${LogTag.player} 播放直链 url=$url');

    final resumeOffset = _resolveResumeOffset(url, offset, playerController);
    final bool forceAdBlocker =
        GStorage.getSetting(SettingsKeys.forceAdBlocker);

    String playbackUrl = url;
    Map<String, String> playbackHeaders = <String, String>{
      'user-agent': getRandomUA(),
    };
    if (allowProxyPlayback) {
      final proxyUrl = await inject<DownloadController>()
          .maybeStartProxyForPlaybackByIdentity(
        sourceKey: sourceKey,
        videoId: videoId,
        sourceIndex: currentSourceIndex,
        episodeIndex: currentEpisodeIndex,
        resolvedUrl: url,
      );
      if (proxyUrl != null && proxyUrl.isNotEmpty) {
        playbackUrl = proxyUrl;
        playbackHeaders = const {};
        WywLogger().i('${LogTag.player} 直链切换为代理播放 url=$playbackUrl');
      }
    }

    final params = PlaybackInitParams(
      videoUrl: playbackUrl,
      offset: resumeOffset,
      httpHeaders: playbackHeaders,
      adBlockerEnabled: forceAdBlocker,
      referer: '',
      videoTitle: videoTitle,
      videoCover: videoCover,
      historySourceId: _stableHistoryKey(url),
    );

    try {
      final initialized = await playerController.init(params);
      loading = false;
      if (!initialized) {
        errorMessage = '视频初始化失败';
        WywLogger().e('${LogTag.player} 直链播放初始化返回 false url=$playbackUrl');
      }
    } catch (e) {
      loading = false;
      errorMessage = '视频播放失败：$e';
      WywLogger().e('${LogTag.player} 视频播放失败 url=$url', error: e);
    }
  }

  /// 当前结构化身份对应的下载记录键（代理会话按此键启停）。
  String get proxyRecordKey =>
      '${sourceKey.isEmpty ? 'wyw' : sourceKey}_${videoId.hashCode}';

  /// 历史 key：有结构化 videoId/sourceKey 时用结构化 id，否则回退直链。
  String _stableHistoryKey(String url) {
    if (videoId.isNotEmpty) {
      return (sourceKey.isEmpty) ? videoId : '$sourceKey:$videoId';
    }
    return url;
  }

  /// 切换到「播放即下载」代理播放：不改动 loading 状态，
  /// 用当前播放位置续播（代理 URL 由 DownloadController 提供）。
  Future<void> switchToProxyPlayback(
    String proxyUrl, {
    required PlayerController playerController,
  }) async {
    final currentMs = playerController.playback.currentPosition.inMilliseconds;
    WywLogger().i('${LogTag.player} 切换代理播放 offsetMs=$currentMs url=$proxyUrl');

    final bool forceAdBlocker =
        GStorage.getSetting(SettingsKeys.forceAdBlocker);

    final params = PlaybackInitParams(
      videoUrl: proxyUrl,
      offset: currentMs > 0 ? currentMs : 0,
      httpHeaders: const {}, // 代理地址无需源站 UA
      adBlockerEnabled: forceAdBlocker,
      referer: '',
      videoTitle: videoTitle,
      videoCover: videoCover,
      historySourceId:
          resolvedVideoUrl.isNotEmpty ? resolvedVideoUrl : videoUrl,
    );

    try {
      final initialized = await playerController.init(params);
      if (!initialized) {
        errorMessage = '切换到本地代理播放失败';
        WywLogger().e('${LogTag.player} 代理播放初始化返回 false url=$proxyUrl');
      }
    } catch (e) {
      errorMessage = '切换代理播放失败：$e';
      WywLogger().e('${LogTag.player} 切换代理播放失败 url=$proxyUrl', error: e);
    }
  }

  /// 在当前播放已经得到最终直链后，尝试把现有下载任务切换为代理播放。
  Future<bool> startProxyForCurrentPlayback({
    required PlayerController playerController,
  }) async {
    if (isOfflineMode || resolvedVideoUrl.isEmpty) {
      return false;
    }
    allowProxyPlayback = true;
    final proxyUrl =
        await inject<DownloadController>().maybeStartProxyForPlaybackByIdentity(
      sourceKey: sourceKey,
      videoId: videoId,
      sourceIndex: currentSourceIndex,
      episodeIndex: currentEpisodeIndex,
      resolvedUrl: resolvedVideoUrl,
    );
    if (proxyUrl == null || proxyUrl.isEmpty) return false;
    await switchToProxyPlayback(
      proxyUrl,
      playerController: playerController,
    );
    return true;
  }

  void cancelVideoSourceResolution() {
    _playbackSessions.cancel();
    _logSubscription?.cancel();
    _logSubscription = null;
    if (!_logStreamController.isClosed) {
      _logStreamController.close();
    }
    final service = _resolutionService;
    _resolutionService = null;
    if (service != null) {
      unawaited(service.dispose());
    }
  }

  // ===== 进度 =====

  /// 记录当前集播放进度（position 变化时由 player/页面调用）。
  void reportProgress({required int positionMs, required int durationMs}) {
    _positions[_currentKey] = positionMs;
    _durations[_currentKey] = durationMs;
    _lastPlayedAt[_currentKey] = DateTime.now();
  }

  /// 组装整部剧进度（含每集独立进度与已解析直链）。
  VideoPlaybackProgress buildProgress() {
    final updatedSources = <VideoPlaySource>[];
    for (var s = 0; s < sources.length; s++) {
      final src = sources[s];
      final eps = <VideoPlayEpisode>[];
      for (var e = 0; e < src.episodes.length; e++) {
        final key = '$s:$e';
        eps.add(src.episodes[e].copyWith(
          resolvedUrl: _resolvedUrls[key] ?? src.episodes[e].resolvedUrl,
          positionMs: _positions[key] ?? src.episodes[e].positionMs,
          durationMs: _durations[key] ?? src.episodes[e].durationMs,
          lastPlayedAt: _lastPlayedAt[key] ?? src.episodes[e].lastPlayedAt,
        ));
      }
      updatedSources.add(VideoPlaySource(name: src.name, episodes: eps));
    }
    return VideoPlaybackProgress(
      videoId: videoId,
      sourceKey: sourceKey,
      sources: updatedSources,
      lastSourceIndex: currentSourceIndex,
      lastEpisodeIndex: currentEpisodeIndex,
      videoUrl: resolvedVideoUrl.isNotEmpty
          ? resolvedVideoUrl
          : (currentEpisode?.effectiveUrl ?? ''),
      lastWatchTime: DateTime.now(),
    );
  }

  /// 通过 onProgressChanged 回调把当前进度交给调用方写历史。
  void notifyProgressChanged() {
    final cb = onProgressChanged;
    if (cb == null) return;
    try {
      cb(buildProgress());
    } catch (e) {
      WywLogger().e('${LogTag.player} 进度回调通知失败', error: e);
    }
  }

  // ===== 全屏 / 方向 =====

  void enterFullScreen() {
    isOrientationLocked = false;
    isFullscreen = true;
    DisplayModeService.enterFullScreen(lockOrientation: false);
  }

  void exitFullScreen() {
    if (!isDesktop()) {
      return;
    }
    isFullscreen = false;
    DisplayModeService.exitFullScreen();
  }

  Future<void> syncWindowFullscreenState() async {
    if (isDesktop()) {
      isFullscreen = await windowManager.isFullScreen();
    }
  }

  void handleOnEnterFullScreen() async {
    if (isDesktop()) {
      isFullscreen = true;
    }
  }

  void handleOnExitFullScreen() async {
    if (isDesktop()) {
      isFullscreen = false;
    }
  }

  void toggleOrientationLock(Orientation orientation) {
    if (isOrientationLocked) {
      isOrientationLocked = false;
      unawaited(DisplayModeService.unlockScreenRotation());
    } else {
      isOrientationLocked = true;
      unawaited(DisplayModeService.lockOrientation(orientation));
    }
  }

  /// 按直链/历史 key 查历史续播 offset；末段（>= 75%，片尾段）视为已看完，从头开始。
  ///
  /// 显式 [sourceOffset] > 0 时（结构化进入带该集续播位置）直接采用，不再查历史。
  int _resolveResumeOffset(String key, int sourceOffset, PlayerController pc) {
    if (sourceOffset > 0) return sourceOffset;
    final reporter = HistoryProgressReporter();
    WywLogger().i('${LogTag.player} 查询续播偏移 key=$key '
        'sourceOffset=$sourceOffset');
    final entry = reporter.findEntry(type: HistoryType.video, sourceId: key);
    if (entry == null) {
      WywLogger().i('${LogTag.player} 无历史记录，使用 sourceOffset=$sourceOffset');
      return sourceOffset;
    }
    final progress = VideoPlaybackProgress.fromMap(entry.progress);
    final ep = progress.currentEpisode;
    final pos = ep?.positionMs ?? 0;
    final dur = ep?.durationMs ?? 0;
    WywLogger().i('${LogTag.player} 找到历史记录 '
        'pos=$pos dur=$dur lastWatchTime=${entry.lastWatchTime}');
    if (pos <= 0) {
      WywLogger().i('${LogTag.player} 历史位置无效，使用 sourceOffset=$sourceOffset');
      return sourceOffset;
    }
    if (dur > 0 && pos >= (dur * 0.75).toInt()) {
      WywLogger().i('${LogTag.player} 已看完（pos=$pos >= 75% of dur=$dur），'
          '使用 sourceOffset=$sourceOffset');
      return sourceOffset;
    }
    WywLogger().i('${LogTag.player} 从历史续播 positionMs=$pos dur=$dur');
    return pos;
  }
}
