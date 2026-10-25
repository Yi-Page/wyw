// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/dialog/dialog.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/modules/danmaku/danmaku_library_ref.dart';
import 'package:wyw/pages/download/download_controller.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/services/download/playback_proxy_service.dart';
import 'package:wyw/services/video_source/resolution_service.dart';
import 'package:wyw/services/video_source/services.dart';
import 'package:wyw/services/danmaku/danmaku_library_service.dart';
import 'package:wyw/services/danmaku/danmaku_cache_service.dart';
import 'package:mobx/mobx.dart';
import 'package:wyw/repositories/i_history_repository.dart';
import 'package:wyw/services/history/video_progress_merge.dart';
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

  /// 作品级身份 code（进度记录 `sourceId` / 下载归属），由 `configure` 从
  /// [VideoPageRouteArgs.historySourceId] 注入。
  ///
  /// **本页所有身份相关逻辑只读这一个字段**（进度回填、写回、下载查询、
  /// 弹幕匹配），不得再由 `sourceKey`+`videoId` 现场拼接——历史上三处各自拼
  /// 过，正是 key 漂移的来源。
  String videoCode = '';

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

  /// 整页沿用进入时选择的播放方式：true = 切换集数时继续使用（默认）；
  /// false = 仅初始集生效，之后切集按「直接播放」处理（弹窗内开关）。
  bool followPlayMode = true;

  /// 是否已用过进入时选择的播放方式（仅 followPlayMode=false 时参与判定）。
  bool _usedChosenMode = false;

  @observable
  bool loading = true;

  @observable
  String? errorMessage;

  @observable
  bool isFullscreen = false;

  @observable
  bool isCommentsAscending = false;

  final AsyncSessionOwner _playbackSessions = AsyncSessionOwner();

  @observable
  bool isPip = false;

  /// 统一解析服务（解析层）：resolve/page 型的插件解析与 WebView 嗅探。
  ResolutionService? _resolutionService;

  /// 当前正在播放的这一集是否来自**本地文件**（离线播放）。
  ///
  /// 不表示整页离线：切集时在 [playEpisode] 开头复位，随后由 [playLocalFile]
  /// 按需重新置真，因此只反映「当前集」，不会跨集残留——否则这一页只要
  /// 播过一次本地文件（含"该集已下载完成"的回退播放），切回在线集后播放器
  /// 顶栏的下载/合流入口仍会被误藏。
  @observable
  bool isOfflineMode = false;

  /// 当前播放源列表是否**全是本地文件**——即"这个列表里只有已缓存项"。
  ///
  /// 这是选集面板 `isOffline` 需要的语义（照 Kazumi `_buildOfflineRoadList`
  /// 只把已缓存集塞进 roads）。**不能直接用 [isOfflineMode]**：
  ///   - 后者只要当前这一集命中已下载的本地文件就置真（单集回退到本地播放），
  ///     而 sources 仍是全量剧集；
  ///   - 而且整页存活期间不会复位，切到在线集之后仍为真；
  /// 于是面板工具条会对一整季在线剧集错误显示「已缓存 · N 集」，同时因为
  /// 离线态会抑制逐集标签，真正的逐集缓存状态反而看不到。
  bool get isCachedOnlyPlayback =>
      sources.isNotEmpty &&
      sources.every((source) =>
          source.episodes.isNotEmpty &&
          source.episodes.every((e) => e.path.type == PlayPathType.local));

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
    videoCode = args.historySourceId;
    sources = args.sources;
    currentSourceIndex = args.initialSource >= 0
        ? args.initialSource.clamp(0, sources.isEmpty ? 0 : sources.length - 1)
        : 0;
    currentEpisodeIndex = args.initialEpisode >= 0 ? args.initialEpisode : 0;
    onProgressChanged = args.onProgressChanged;
    playMode = args.playMode;
    allowProxyPlayback = args.allowProxyPlayback;
    followPlayMode = args.followPlayMode;
    _usedChosenMode = false;
    _resolvedUrls.clear();
    _positions.clear();
    _durations.clear();
    _lastPlayedAt.clear();
    resumeOffsetMs = 0;
    // 弹幕库条目按作品持久化在进度记录里；换一部作品必须先清掉上一部的，
    // 否则同一控制器实例复用时会显示上一部的库（"当前使用"卡片串台）。
    danmakuLibrary = null;
    // 从历史记录回填各集观看进度（不覆盖插件最新剧集列表）
    _applyHistoryProgress();
  }

  /// 进入时从历史记录查询一次，把历史进度按「线路+集数 index」回填到
  /// 当前（插件最新）的 sources 对应集上；并定位到上次观看的集 + 续播位置。
  ///
  /// 不回填则 sources 里各集 positionMs 都是 0，选集面板看不到历史进度、
  /// 也无法续播（插件进入 args 不带 offsetMs）。
  ///
  /// 结构/状态的合并（含线路名 + 集标识二级校验）统一走
  /// [mergeVideoProgressState]，与入口编排层同源，避免两处口径漂移。
  void _applyHistoryProgress() {
    if (videoCode.isEmpty) return;
    final entry = inject<IHistoryRepository>()
        .find(type: HistoryType.video, sourceId: videoCode);
    if (entry == null) return;
    final history = VideoPlaybackProgress.fromMap(entry.progress);

    // 1) 把历史每集进度合并进插件最新列表（只回填状态字段，不动 name/path）
    sources = mergeVideoProgressState(skeleton: sources, history: history);

    // 2) 续播位置 = 当前集（args 指定的初始集）在历史中的 positionMs
    resumeOffsetMs = currentEpisode?.positionMs ?? 0;

    // 3) 弹幕库条目：入场即"当前使用"的来源。分集映射刻意不存，所以这里只拿库，
    //    要出弹幕仍需用户点一次分集（见 docs/danmaku-selection-plan.md §1）。
    danmakuLibrary = history.danmaku;
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

    // 整页沿用：进入时选择的方式对后续切集持续生效；不沿用则只对初始集生效，
    // 之后切集按「直接播放」处理。
    final useChosenMode = followPlayMode || !_usedChosenMode;
    _usedChosenMode = true;
    final effectiveMode = useChosenMode ? playMode : VideoPlayMode.online;

    WywLogger().i('${LogTag.player} 播放剧集 s=$currentSourceIndex '
        'e=$currentEpisodeIndex path=${currentEp.path.type.value} '
        'mode=${effectiveMode.name} name=${currentEp.name}');

    // 开启新一轮播放尝试：先清掉上一次的失败状态，保证解析失败后
    // 再点「重新解析」时界面能回到加载态（而不是停在旧错误页）。
    errorMessage = null;
    loading = true;
    // 重算离线态：isOfflineMode 只反映「当前这一集是否本地文件播放」，
    // 每次切集先复位，本地分支在 playLocalFile 里重新置真。
    isOfflineMode = false;

    // 本地文件：直接本地播放
    if (ep.path.type == PlayPathType.local) {
      await playLocalFile(ep.path.url,
          playerController: playerController, offset: offset ?? 0);
      return;
    }

    // 下载预检：该集已下载完成且本地文件存在 → 直接本地播放
    final downloadController = inject<DownloadController>();
    final localPath = downloadController.findLocalVideoPathByIdentity(
      code: videoCode,
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
    // 合流的解析路径会先预创建任务（让"解析中"在下载页可见）；判型不支持时要
    // 把它撤掉——用户并没有下这一集。
    var preparedDownloadTask = false;
    if (currentEp.resolvedUrl.isNotEmpty) {
      // 已解析直链缓存：直接使用；失效时由用户经「重新解析」强制重走解析
      playUrl = currentEp.resolvedUrl;
    } else if (effectiveMode == VideoPlayMode.merge) {
      // 合流：优先直用进行中任务的新鲜直链（免解析快路径）
      final taskEpisode = inject<DownloadController>().findEpisodeByIdentity(
        code: videoCode,
        sourceIndex: currentSourceIndex,
        episodeIndex: currentEpisodeIndex,
      );
      final taskUrl = taskEpisode?.networkM3u8Url ?? '';
      if (taskUrl.isNotEmpty) {
        playUrl = taskUrl;
      } else {
        // 预创建解析中任务：解析也是下载生命周期的一部分，下载页立即可见
        await inject<DownloadController>().prepareStructuredEpisode(
          code: videoCode,
          sourceKey: sourceKey,
          videoId: videoId,
          title: videoTitle,
          cover: videoCover,
          sourceIndex: currentSourceIndex,
          episodeIndex: currentEpisodeIndex,
          episodeName: currentEp.name,
          sourceName: src.name,
        );
        preparedDownloadTask = true;
        final source = await _resolveMedia(currentEp.path, offset: playOffset);
        if (source == null) {
          // 失败/取消：_resolveMedia 内已置 errorMessage 并停止 loading
          //（取消保持静默，与页面关闭时的取消行为一致）
          await inject<DownloadController>().failPreparedEpisode(
            code: videoCode,
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

    // 合流只支持 HLS：整段媒体（mp4 直链等）没有分片，就没有「播放进度即下载
    // 进度」这条两端共享的量，代理没法边下边播。判型不支持时**底部提示 + 降级
    // 为直链直接播放**（不建下载任务、不挂代理），而不是挂上代理让播放器拿到一个
    // 必然打不开的地址。判型只看内容不看 URL 后缀，理由见 classifyProxyMediaBytes。
    //
    // 非合流模式下恒为 true：它同时也是"允许挂代理"的开关，在线模式的静默代理
    // 挂靠要靠它（与整页策略 allowProxyPlayback 是「与」的关系）。
    var mergeAllowed = true;
    if (effectiveMode == VideoPlayMode.merge) {
      final kind = await PlaybackProxyService.instance.probeMediaKind(playUrl);
      mergeAllowed = kind == ProxyMediaKind.hlsPlaylist;
      if (!mergeAllowed) {
        WywLogger().i('${LogTag.player} 合流源不支持（kind=${kind.name}），'
            '降级为直链播放 url=$playUrl');
        WywDialog.showToast(
          message: kind == ProxyMediaKind.singleFile
              ? '该资源是整段视频，不支持合流播放，已改为直接播放'
              : '无法确认资源格式，合流播放不可用，已改为直接播放',
        );
        if (preparedDownloadTask) {
          await inject<DownloadController>().discardPreparedEpisode(
            code: videoCode,
            sourceIndex: currentSourceIndex,
            episodeIndex: currentEpisodeIndex,
          );
        }
      }
    }

    // 合流：确保下载任务存在（幂等，已完成跳过），随后经静默挂靠走本地代理
    if (effectiveMode == VideoPlayMode.merge && mergeAllowed) {
      await inject<DownloadController>().downloadStructuredEpisode(
        code: videoCode,
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
        playerController: playerController, engageProxy: mergeAllowed);
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
        code: videoCode,
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
          code: videoCode,
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
      code: videoCode,
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

  // ===== 弹幕（选择与关联） =====

  /// 这部作品选用的弹弹play 弹幕库条目信息（**作品级**；null = 还没选过）。
  ///
  /// 唯一事实源是**进度记录**（`VideoPlaybackProgress.danmaku`）：入场由
  /// `_applyHistoryProgress` 读回，用户点选/刷新后由 [setDanmakuLibrary] 立即回写。
  /// 刻意不在页面里再存一份：两份状态必然要靠"同步通道"对齐，那是 v1 踩过的坑。
  ///
  /// 注意它**只代表"用哪个库"**，不代表当前已经加载了弹幕——分集映射刻意不持久化，
  /// 所以入场后还需要用户点一次分集（`playerController.danmaku.danmakuEpisodeId`
  /// 才是"这一集已经出弹幕"的状态）。
  DanmakuLibraryRef? danmakuLibrary;

  /// 记下用户选用的弹幕库（点选与刷新都走这里），并**立即**写一次进度记录。
  ///
  /// 立即写而不是等下一个进度 tick：用户选完可能马上退出播放页，等 tick 可能等不到。
  /// 没有进度记录可写时（下载入口反查不到记录 → `onProgressChanged` 为 null）
  /// 只在本次会话里生效并记日志，不产生残缺记录（与入口编排层的约定一致）。
  void setDanmakuLibrary(DanmakuLibraryRef? ref) {
    danmakuLibrary = ref;
    if (ref == null) return;
    if (onProgressChanged == null) {
      WywLogger().w(
          '${LogTag.player} 本页无进度记录可写，弹幕库选择仅在本次会话生效 '
          'code=$videoCode library=${ref.libraryTitle}');
      return;
    }
    notifyProgressChanged();
  }

  /// 当前线路的分集总数，用于给候选作品算「集数吻合度」；未知返回 null。
  int? get currentSourceEpisodeCount {
    if (sources.isEmpty) return null;
    final index = currentSourceIndex.clamp(0, sources.length - 1);
    final count = sources[index].episodes.length;
    return count > 0 ? count : null;
  }

  /// 离线播放时的弹幕加载：**只读下载目录里的本地缓存**。
  ///
  /// 那份 `danmaku.json` 是**下载产物**（内含写下去的 `episodeId`），不是匹配记忆：
  /// 匹配记忆层已整体退场——作品级选择存在进度记录里
  /// （`VideoPlaybackProgress.danmaku`），分集映射按
  /// 产品口径刻意不持久化。因此在线播放不再"自动出弹幕"，离线播放也只认这份缓存；
  /// 缺缓存就什么都不做，等用户联网后在「弹幕」tab 里点一次分集。
  Future<void> _loadDanmakuForOfflinePlayback(
    PlayerController playerController,
    DownloadEpisode? episode,
  ) async {
    final danmaku = playerController.danmaku;
    if (!DanmakuLibraryService.instance.isConfigured) {
      // 未配置凭证是本地构建的预期状态：整块弹幕功能静默关闭。
      danmaku.resetEpisodeSelection();
      return;
    }

    final directory = episode?.downloadDirectory.trim() ?? '';
    if (directory.isEmpty) {
      danmaku.resetEpisodeSelection();
      return;
    }

    try {
      final cached = await DanmakuCacheService.instance.read(directory);
      if (cached != null && cached.danmakus.isNotEmpty) {
        danmaku.applyDanmakuLoad(
          cached.danmakus,
          episodeId: cached.episodeId,
          libraryTitle: cached.libraryTitle,
          // 读缓存命中就显示，不看那个没有 UI 的 `danmakuEnabledByDefault`
          // （默认 false，会让离线播放永远黑屏弹幕）。
          enableDanmaku: true,
        );
        WywLogger().i(
            '${LogTag.player} 离线播放使用本地缓存的弹幕 episodeId=${cached.episodeId} '
            '条数=${cached.danmakus.length}');
        return;
      }
    } catch (error) {
      WywLogger().w('${LogTag.player} 读离线弹幕缓存失败', error: error);
    }

    danmaku.resetEpisodeSelection();
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
    // 这个反查结果同时给离线弹幕缓存用，所以只查一次。
    DownloadEpisode? localEpisode;
    try {
      localEpisode = inject<DownloadController>().findEpisodeByLocalPath(
        localPath,
      );
    } catch (e) {
      WywLogger().d('${LogTag.player} 反查下载记录获取历史 key 失败（已忽略）', error: e);
    }
    final historyKey = (localEpisode != null &&
            localEpisode.networkM3u8Url.isNotEmpty)
        ? localEpisode.networkM3u8Url
        : localPath;

    final resumeOffset = offset > 0
        ? offset
        : _resolveResumeOffset(historyKey, 0, playerController);

    // 广告过滤统一走同一个开关：离线播放也让引擎启用 hls_ad_filter。
    // 本地 playlist.m3u8 保留了 #EXT-X-DISCONTINUITY（引擎侧过滤的启用条件），
    // 因此这里与在线播放取同一个设置，不再写死关闭。
    final bool forceAdBlocker =
        GStorage.getSetting(SettingsKeys.forceAdBlocker);

    final params = PlaybackInitParams(
      videoUrl: localPath,
      offset: resumeOffset,
      httpHeaders: const {},
      adBlockerEnabled: forceAdBlocker,
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
      } else {
        unawaited(
            _loadDanmakuForOfflinePlayback(playerController, localEpisode));
      }
    } catch (e) {
      loading = false;
      errorMessage = '本地播放失败：${e.toString()}';
      WywLogger().e('${LogTag.player} 本地播放失败 localPath=$localPath', error: e);
    }
  }

  /// 直链直接播放（不经 WebView 嗅探）。
  ///
  /// [engageProxy] 是**本次播放**的开关：合流源判型不支持时传 false，一次性降级为
  /// 直链播放，不影响后续切集是否再尝试合流。它与 [allowProxyPlayback]（整页策略，
  /// 由入口决策层给出）是「与」的关系。
  Future<void> _playDirectUrl(
    String url,
    int offset, {
    required PlayerController playerController,
    bool engageProxy = true,
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
    if (engageProxy && allowProxyPlayback) {
      final proxyUrl = await inject<DownloadController>()
          .maybeStartProxyForPlaybackByIdentity(
        code: videoCode,
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
      } else {
        // 不再"自动出弹幕"：分集映射刻意不持久化，作品级选择（用哪个库）由
        // 「弹幕」tab 里的"当前使用"卡片显示，用户点一次分集才加载。
        // 但**必须复位**，否则上一集的弹幕会留在画布上继续跑。
        playerController.danmaku.resetEpisodeSelection();
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

  /// 历史 key：结构化身份（code）优先，缺省回退直链。
  String _stableHistoryKey(String url) => videoCode.isNotEmpty ? videoCode : url;

  // 曾经还有 switchToProxyPlayback / startProxyForCurrentPlayback 两个"播放中
  // 改挂代理"的入口（顶栏那个下载/合流按钮退场后就再没有调用者了）。它们已删除：
  // 挂代理前必须先判型（合流只支持 HLS），留一个能绕过判型的入口等于把这个坑
  // 重新埋回去。

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
      // 弹幕库条目跟着进度一起写：它是"这部作品我上次怎么播的"的一部分。
      danmaku: danmakuLibrary,
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
  //
  // 方向不在这里：播放页进入/退出时由 `ScreenOrientationService` 占用/释放
  // （owner = player），页面内的方向按钮直接改服务里的当前策略。

  void enterFullScreen() {
    isFullscreen = true;
    DisplayModeService.enterFullScreen();
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

  /// 按直链/历史 key 查历史续播 offset；末段（>= 75%，片尾段）视为已看完，从头开始。
  ///
  /// 显式 [sourceOffset] > 0 时（结构化进入带该集续播位置）直接采用，不再查历史。
  int _resolveResumeOffset(String key, int sourceOffset, PlayerController pc) {
    if (sourceOffset > 0) return sourceOffset;
    WywLogger().i('${LogTag.player} 查询续播偏移 key=$key '
        'sourceOffset=$sourceOffset');
    final entry =
        inject<IHistoryRepository>().find(type: HistoryType.video, sourceId: key);
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
