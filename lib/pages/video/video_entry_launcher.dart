// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/pages/history/history_progress_summary.dart'
    show formatHistoryPosition;
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/pages/video/play_intent.dart';
import 'package:wyw/pages/video/video_route_args.dart';
import 'package:wyw/repositories/i_history_repository.dart';
import 'package:wyw/services/history/video_progress_merge.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/history_entry.dart';
import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/history_type.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/services/storage/video_code.dart';
import 'package:wyw/services/storage/video_play_model.dart';

/// 进播放页的**唯一编排层**（三入口 → 统一中间体 → 公共流程）。
///
/// 设计约定（`docs/` 讨论结论）：
///   1. `code`（作品级身份，[VideoCode]）**只在这里构造一次**；其余入口一律
///      读取记录里已有的 code（`HistoryEntry.sourceId` / `DownloadRecord.code`）。
///      页面与写回只读 `VideoPageRouteArgs.code`，不得再自行拼接。
///   2. 三个入口先把参数处理成同一形状（[_VideoEntry]），再走 [_open]：
///      查进度回填状态 → 决策（本地短路 / 弹窗 / 只下载）→ 构造 args 进播放页。
///   3. **写回口径**：只有拿到进度记录（骨架）时才挂 `onProgressChanged`。
///      下载入口反查不到记录时**不写进度**——绝不产生"只有一集"的残缺权威
///      记录（那会把整部剧的源/集列表削成单集）。反查不到但任务还在下时，用下载
///      记录本身推结构走合流（[buildSourcesFromDownloadRecord]），同样不写。
///   4. 集级身份仍是下标 `(sourceIndex, episodeIndex)`，配
///      [mergeVideoProgressState] 的二级校验（线路名 + 集标识）防换序串集。
///
/// 这是"约定型"收口：新入口请调用本类，不要直接 `pushNamed('/video/')`。
class VideoEntryLauncher {
  VideoEntryLauncher(this.context);

  final BuildContext context;

  // ===== 入口 ①：插件调用 =====

  /// 插件结构化进入（`Navigator.navigateToVideo`）。
  ///
  /// [pluginName] 为插件 key（必须非空）；[videoId] 为插件内唯一、跨次稳定的
  /// 作品 id；[sources] 为插件给的完整线路/集列表（结构权威）。
  Future<void> openFromPlugin({
    required String pluginName,
    required String videoId,
    required String title,
    String cover = '',
    required List<VideoPlaySource> sources,
    int initialSource = 0,
    int initialEpisode = 0,
  }) async {
    final code = VideoCode.of(pluginName: pluginName, videoId: videoId);
    if (code.isEmpty) {
      WywDialog.showToast(message: '插件未提供视频 id，无法进入播放');
      return;
    }
    if (sources.isEmpty) {
      WywDialog.showToast(message: '插件未返回播放源');
      return;
    }
    if (pluginName.isEmpty) {
      // 空插件名会让 code 退化成裸 id，与手动播放/其他来源混在一起，且来源
      // 无法展示。非空但未注册只告警（js 控制台测试脚本、热重载时序）。
      WywLogger().w('${LogTag.player} 插件播放入口缺少 sourceKey code=$code');
      WywDialog.showToast(message: '插件未标识来源，无法进入播放');
      return;
    }
    if (inject<PluginController>().getPlugin(pluginName) == null) {
      WywLogger().w(
          '${LogTag.player} 插件播放入口的 sourceKey 未注册（继续） plugin=$pluginName code=$code');
    }

    final s = initialSource.clamp(0, sources.length - 1);
    if (sources[s].episodes.isEmpty) {
      WywDialog.showToast(message: '该线路没有可播放的剧集');
      return;
    }
    final e = initialEpisode.clamp(0, sources[s].episodes.length - 1);

    // ① 历史合并：结构以插件为准，状态（位置/时长/直链）从进度记录回填
    final history = _progressOfHistory(code);
    final merged =
        mergeVideoProgressState(skeleton: sources, history: history);
    final current = merged[s].episodes[e];

    await _open(
      code: code,
      pluginName: pluginName,
      videoId: videoId,
      title: title,
      cover: cover,
      sources: merged,
      initialSource: s,
      initialEpisode: e,
      offsetMs: current.positionMs,
      cachedUrl: current.resolvedUrl,
      resumeText: _resumeText(history, s, e),
      writable: true,
    );
  }

  // ===== 入口 ②：进度记录 =====

  /// 从进度记录续播（历史页卡片 / 「继续观看」/ 选集面板）。
  ///
  /// 不传 [sourceIndex]/[episodeIndex] 时续上次看到的集；传了则进入指定集
  /// （历史页的「选集」入口）。记录本身即骨架，因此无需再查进度。
  Future<void> openFromHistory(
    HistoryEntry entry, {
    int? sourceIndex,
    int? episodeIndex,
  }) async {
    final progress = _progressOf(entry);
    if (progress == null || progress.sources.isEmpty) {
      WywDialog.showToast(message: '该记录没有可用的播放结构，请从插件详情页重新进入');
      return;
    }
    final code = entry.sourceId.isNotEmpty
        ? entry.sourceId
        : VideoCode.of(
            pluginName: progress.sourceKey,
            videoId: progress.videoId,
          );
    if (code.isEmpty) {
      WywDialog.showToast(message: '该记录缺少作品标识，请从插件详情页重新进入');
      return;
    }

    final s = (sourceIndex ?? progress.lastSourceIndex)
        .clamp(0, progress.sources.length - 1);
    if (progress.sources[s].episodes.isEmpty) {
      WywDialog.showToast(message: '该线路没有可播放的剧集');
      return;
    }
    final e = (episodeIndex ?? progress.lastEpisodeIndex)
        .clamp(0, progress.sources[s].episodes.length - 1);
    final current = progress.sources[s].episodes[e];

    await _open(
      code: code,
      pluginName: progress.sourceKey,
      videoId: progress.videoId,
      title: entry.title,
      cover: entry.cover,
      // 记录里的 sources 已含状态，无需合并
      sources: progress.sources,
      initialSource: s,
      initialEpisode: e,
      offsetMs: current.positionMs,
      cachedUrl: current.resolvedUrl,
      resumeText: _resumeText(progress, s, e),
      writable: true,
    );
  }

  // ===== 入口 ③：下载记录 =====

  /// 从下载记录进入播放。
  ///
  /// `DownloadRecord.effectiveCode` 是本记录引用的进度记录 code：
  ///   - **能反查到进度记录** → 用它的完整源/集列表当骨架、(s,e) 用下载记录的
  ///     真实下标 → 与入口 ② 完全同形（写回整表替换安全，本地文件由播放页的
  ///     "已下载"短路自动挑中，不需要把本地路径写进 path）；
  ///   - **反查不到**（只下载没播过 / 历史被删 / 私人模式）→ 只播这个本地
  ///     文件且**不写进度**（约定：宁可无记录，也不产生残缺记录）。
  Future<void> openFromDownload(
    DownloadRecord record,
    DownloadEpisode episode, {
    required String localPath,
  }) async {
    final code = record.effectiveCode;
    final history = _progressOfHistory(code);

    final s = episode.sourceIndex;
    final e = episodeIndexOf(episode.episodeNumber);
    final hasSkeleton = history != null &&
        s >= 0 &&
        s < history.sources.length &&
        e >= 0 &&
        e < history.sources[s].episodes.length;

    if (!hasSkeleton) {
      // ① 本地文件已就绪（已完成下载但没播过）→ 只播这个文件，不写进度，
      //    避免产生"只有一集"的残缺记录。
      if (localPath.isNotEmpty) {
        final episodeName = episode.episodeName.isNotEmpty
            ? episode.episodeName
            : '第${episode.episodeNumber}集';
        await _open(
          code: code,
          pluginName: record.sourceKey,
          videoId: record.videoId,
          title: record.mediaName.isNotEmpty ? record.mediaName : episodeName,
          cover: record.mediaCover,
          sources: [
            VideoPlaySource(
              name: '本地文件',
              episodes: [
                VideoPlayEpisode(
                  name: episodeName,
                  path: PlayResourcePath(
                    url: localPath,
                    type: PlayPathType.local,
                  ),
                ),
              ],
            ),
          ],
          initialSource: 0,
          initialEpisode: 0,
          offsetMs: 0,
          cachedUrl: '',
          // 反查不到进度记录 → 不写（见类注释第 3 条）
          writable: false,
        );
        return;
      }

      // ② 还在下（进行中/已暂停/待解析）且任务里已有直链 → 从下载页直接进
      //    「边下边播」。没有进度记录就没有现成骨架，但播放页要靠 (线路, 集) 找
      //    任务，所以这里用**下载记录本身**推出结构（真实下标），
      //    见 buildSourcesFromDownloadRecord。
      final inProgress = episode.status == DownloadStatus.downloading ||
          episode.status == DownloadStatus.paused ||
          episode.status == DownloadStatus.pending ||
          episode.status == DownloadStatus.resolving;
      if (inProgress &&
          episode.networkM3u8Url.isNotEmpty &&
          code.isNotEmpty) {
        final sources = buildSourcesFromDownloadRecord(record);
        final s = episode.sourceIndex;
        final e = episodeIndexOf(episode.episodeNumber);
        final identityCovered = s < sources.length &&
            e >= 0 &&
            e < sources[s].episodes.length;
        if (identityCovered) {
          await _open(
            code: code,
            pluginName: record.sourceKey,
            videoId: record.videoId,
            title: record.mediaName,
            cover: record.mediaCover,
            sources: sources,
            initialSource: s,
            initialEpisode: e,
            // 没有进度记录就没有续播位置可回填
            offsetMs: 0,
            cachedUrl: '',
            writable: false,
          );
          return;
        }
        WywLogger().w(
            '${LogTag.player} 下载记录推不出这一集的下标，无法直接进合流 '
            'code=$code sourceIndex=$s episodeIndex=$e 推得线路数=${sources.length}');
      }

      // 已完成但本地文件不见了 → 沿用原来的提示；还没解析出地址 → 说清是"等解析"。
      WywDialog.showToast(
        message: episode.status == DownloadStatus.completed
            ? '本地文件不存在'
            : '这一集还没有可播放的地址，等解析完成后再试',
      );
      return;
    }

    final current = history.sources[s].episodes[e];
    await _open(
      code: code,
      pluginName: record.sourceKey,
      videoId: record.videoId,
      title: record.mediaName,
      cover: record.mediaCover,
      sources: history.sources,
      initialSource: s,
      initialEpisode: e,
      offsetMs: current.positionMs,
      cachedUrl: current.resolvedUrl,
      resumeText: _resumeText(history, s, e),
      writable: true,
    );
  }

  // ===== 公共流程 =====

  Future<void> _open({
    required String code,
    required String pluginName,
    required String videoId,
    required String title,
    required String cover,
    required List<VideoPlaySource> sources,
    required int initialSource,
    required int initialEpisode,
    required int offsetMs,
    required String cachedUrl,
    String? resumeText,
    required bool writable,
  }) async {
    if (sources.isEmpty ||
        initialSource >= sources.length ||
        initialEpisode >= sources[initialSource].episodes.length) {
      WywDialog.showToast(message: '没有可播放的剧集');
      return;
    }
    final current = sources[initialSource].episodes[initialEpisode];

    // 决策层（异步、有 UI、可能执行解析）：本地短路 / 弹窗 / 只下载。
    final decision = await PlayIntentDecider.decide(
      context: context,
      path: current.path,
      code: code,
      sourceKey: pluginName,
      videoId: videoId,
      sourceIndex: initialSource,
      episodeIndex: initialEpisode,
      episodeName: current.name,
      sourceName: sources[initialSource].name,
      videoTitle: title,
      videoCover: cover,
      cachedUrl: cachedUrl,
      resumeText: resumeText,
      followDefault:
          GStorage.getSetting(SettingsKeys.followPlayModeInPlayer),
    );
    if (decision == null || !context.mounted) return;

    context.pushNamed(
      '/video/',
      arguments: VideoPageRouteArgs(
        code: code,
        videoId: videoId,
        title: title,
        cover: cover,
        sourceKey: pluginName.isEmpty ? null : pluginName,
        sources: sources,
        initialSource: initialSource,
        initialEpisode: initialEpisode,
        offsetMs: offsetMs,
        playMode: decision.mode,
        allowProxyPlayback: decision.allowProxyPlayback,
        followPlayMode: decision.followPlayMode,
        // 写回只认 code（唯一出口）；无骨架时不挂回调 = 不写任何记录。
        onProgressChanged: writable
            ? (progress) {
                inject<IHistoryRepository>().setProgress(
                  type: HistoryType.video,
                  sourceId: code,
                  title: title,
                  cover: cover,
                  progress: progress.toMap(),
                );
              }
            : null,
      ),
    );
  }

  // ===== 辅助 =====

  /// 按 code 查进度记录（不依赖当前正在播放的 source）。
  ///
  /// 走注册表里的 [IHistoryRepository]（coreModule 单例，启动即就绪），
  /// 不用只在 JS 引擎 init 后才配置好的 reporter——这样历史页/下载页在
  /// 冷启动早期进入播放也能查到进度。
  VideoPlaybackProgress? _progressOfHistory(String code) {
    if (code.isEmpty) return null;
    final entry = inject<IHistoryRepository>()
        .find(type: HistoryType.video, sourceId: code);
    return _progressOf(entry);
  }

  VideoPlaybackProgress? _progressOf(HistoryEntry? entry) {
    if (entry == null) return null;
    final progress = entry.parseProgress();
    return progress is VideoPlaybackProgress ? progress : null;
  }

  /// 弹窗里的「可续播 · 源 · 集 · 位置/总时长」文案；该集无历史直链或无
  /// 观看位置时返回 null。
  String? _resumeText(VideoPlaybackProgress? history, int s, int e) {
    if (history == null) return null;
    if (s >= history.sources.length) return null;
    final src = history.sources[s];
    if (e >= src.episodes.length) return null;
    final ep = src.episodes[e];
    if (ep.resolvedUrl.isEmpty || ep.positionMs <= 0) return null;
    final parts = <String>[
      if (src.name.isNotEmpty) src.name,
      ep.name.isNotEmpty ? ep.name : '第 ${e + 1} 集',
      '播放到 ${formatHistoryPosition(ep.positionMs)}',
      if (ep.durationMs > 0) '/ ${formatHistoryPosition(ep.durationMs)}',
    ];
    return parts.join(' · ');
  }
}

/// 用**下载记录本身**推出一份可播放结构（这一集没有进度记录时用）。
///
/// 为什么必须把真实下标补齐：播放页用 `(线路, 集)` 这个身份去找下载任务 —— 合流
/// 快路径直接复用任务里的直链（免解析），代理会话也按同一身份启停。下标一旦错位，
/// 播放页会走 `prepareStructuredEpisode` 建出一个**身份错误**的假任务，所以宁可
/// 补占位也不能重排。
///
/// 规则：
///   - 线路按 `sourceIndex` 铺到最大值，缺的线路补一条只有一个占位集的线路；
///   - 每条线路的集按 `episodeIndexOf(episodeNumber)` 定位，铺到最大下标，中间缺的
///     集补占位；
///   - 有直链的集 → [PlayPathType.direct]（能直接播、也能合流）；没有直链的集
///     （刚入队还没解析）与占位 → [PlayPathType.local] + 空地址：播它只会明确失败
///     （"本地播放失败"），**不会**在下载列表里造出多余任务；
///   - 名字取记录里的集名/线路名，缺的留空 —— 播放页的选集面板会回退显示「第 N 集」。
///
/// 刻意不写进度（调用方传 `writable: false`）：这条路径反查不到进度记录，按既有
/// 口径不产生"只有下载过的几集"的权威记录。
List<VideoPlaySource> buildSourcesFromDownloadRecord(DownloadRecord record) {
  if (record.episodes.isEmpty) return const <VideoPlaySource>[];

  var maxSourceIndex = 0;
  for (final ep in record.episodes.values) {
    if (ep.sourceIndex > maxSourceIndex) maxSourceIndex = ep.sourceIndex;
  }

  final sources = <VideoPlaySource>[];
  for (var s = 0; s <= maxSourceIndex; s++) {
    final byEpisodeIndex = <int, DownloadEpisode>{};
    var maxEpisodeIndex = -1;
    var sourceName = '';
    for (final ep in record.episodes.values) {
      if (ep.sourceIndex != s) continue;
      final index = episodeIndexOf(ep.episodeNumber);
      if (index < 0) continue;
      byEpisodeIndex[index] = ep;
      if (index > maxEpisodeIndex) maxEpisodeIndex = index;
      if (sourceName.isEmpty) sourceName = ep.sourceName;
    }
    if (maxEpisodeIndex < 0) {
      // 这条线路没有任何下载任务：补一个占位集，只为让线路下标对得上。
      sources.add(VideoPlaySource(
        name: sourceName,
        episodes: [_episodeFromDownload(null)],
      ));
      continue;
    }
    sources.add(VideoPlaySource(
      name: sourceName,
      episodes: [
        for (var e = 0; e <= maxEpisodeIndex; e++)
          _episodeFromDownload(byEpisodeIndex[e]),
      ],
    ));
  }
  return sources;
}

/// 下载记录里的一集 → 播放结构里的一集（[episode] 为 null 表示占位）。
VideoPlayEpisode _episodeFromDownload(DownloadEpisode? episode) {
  final url = episode?.networkM3u8Url.trim() ?? '';
  return VideoPlayEpisode(
    name: episode?.episodeName ?? '',
    path: url.isNotEmpty
        ? PlayResourcePath(url: url, type: PlayPathType.direct)
        : const PlayResourcePath(url: '', type: PlayPathType.local),
  );
}
