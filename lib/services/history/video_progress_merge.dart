import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/video_play_model.dart';

/// 进度状态 ↔ 当前（插件最新）结构的合并。
///
/// 单位：整部剧。结构（线路/集的 name 与 path）由**骨架**提供，状态
/// （positionMs / durationMs / resolvedUrl / lastPlayedAt）由**历史**提供。
///
/// 集级身份仍是**下标** `(sourceIndex, episodeIndex)`（模型没有集 id），
/// 因此这里配一道**二级校验**：线路名、集标识一致才合并，避免插件换序 /
/// 插集导致进度串到别的集上。校验是"保守"的——任一侧标识缺失就退回按下标
/// 合并（宁可保留进度，不要误丢）。
List<VideoPlaySource> mergeVideoProgressState({
  required List<VideoPlaySource> skeleton,
  required VideoPlaybackProgress? history,
}) {
  if (history == null || history.sources.isEmpty) return skeleton;

  final merged = <VideoPlaySource>[];
  for (var s = 0; s < skeleton.length; s++) {
    final src = skeleton[s];
    final histSrc = s < history.sources.length ? history.sources[s] : null;

    if (histSrc != null && !_sameSource(src, histSrc)) {
      WywLogger().i('${LogTag.history} 进度回填跳过线路（名称不一致）'
          ' s=$s skeleton=${src.name} history=${histSrc.name}');
      merged.add(src);
      continue;
    }

    final eps = <VideoPlayEpisode>[];
    for (var e = 0; e < src.episodes.length; e++) {
      final ep = src.episodes[e];
      final histEp = (histSrc != null && e < histSrc.episodes.length)
          ? histSrc.episodes[e]
          : null;
      if (histEp == null || !_sameEpisode(ep, histEp)) {
        if (histEp != null) {
          WywLogger().i('${LogTag.history} 进度回填跳过剧集（标识不一致）'
              ' s=$s e=$e skeleton=${episodeIdentityOf(ep)} '
              'history=${episodeIdentityOf(histEp)}');
        }
        eps.add(ep);
        continue;
      }
      eps.add(ep.copyWith(
        positionMs: histEp.positionMs,
        durationMs: histEp.durationMs,
        resolvedUrl: histEp.resolvedUrl.isNotEmpty
            ? histEp.resolvedUrl
            : ep.resolvedUrl,
        lastPlayedAt: histEp.lastPlayedAt ?? ep.lastPlayedAt,
      ));
    }
    merged.add(VideoPlaySource(name: src.name, episodes: eps));
  }
  return merged;
}

/// 线路是否同一：名称任一侧为空时视为未知 → 接受（保守）。
bool _sameSource(VideoPlaySource a, VideoPlaySource b) {
  if (a.name.isEmpty || b.name.isEmpty) return true;
  return a.name == b.name;
}

/// 集是否同一：集标识任一侧为空时视为未知 → 接受（保守）。
bool _sameEpisode(VideoPlayEpisode a, VideoPlayEpisode b) {
  final ia = episodeIdentityOf(a);
  final ib = episodeIdentityOf(b);
  if (ia.isEmpty || ib.isEmpty) return true;
  return ia == ib;
}

/// 集标识：优先插件传入的集参数 `path.args[0]`（resolve 型集都带，最稳），
/// 其次该集路径 URL，最后退回集名。三者皆空时返回空串（= 未知）。
String episodeIdentityOf(VideoPlayEpisode ep) {
  final args = ep.path.args;
  if (args != null && args.isNotEmpty) {
    final first = args.first;
    if (first != null) {
      final s = first.toString();
      if (s.isNotEmpty) return s;
    }
  }
  if (ep.path.url.isNotEmpty) return ep.path.url;
  return ep.name;
}
