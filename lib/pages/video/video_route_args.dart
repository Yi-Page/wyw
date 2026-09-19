import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/video_play_model.dart';

/// 播放方式（决策层产出，播放页只执行不再决策）。
enum VideoPlayMode {
  /// 本地播放：path.type=local 或该集已完成下载。
  local,

  /// 在线播放：缓存直链直用或走解析（含静默代理挂靠，受 allowProxyPlayback 控制）。
  online,

  /// 合流播放：边下边播——确保下载任务存在后经本地代理播放。
  merge,
}

/// 播放页路由参数（与漫画阅读器的 `ComicReaderPageRouteArgs` 同构）。
///
/// 一次性传入"整部剧"的播放信息：
///   - videoId / title / cover / sourceKey：元信息（历史 key 与展示用）
///   - sources：完整播放源列表（每个源含全部集 + 每集已解析直链/独立进度）
///   - initialSource / initialEpisode：上次看到的线路与集（从进度历史恢复时带入）
///   - offsetMs：续播位置（毫秒）
///   - onProgressChanged：播放页回吐当前播放状态，调用方据此写进度历史
///   - playMode / allowProxyPlayback：决策层产出的播放方式（未经决策层的
///     入口（历史/下载页/手动）使用默认值，行为与原有一致）
class VideoPageRouteArgs {
  const VideoPageRouteArgs({
    required this.videoId,
    required this.title,
    this.cover = '',
    this.sourceKey,
    this.sources = const [],
    this.initialSource = 0,
    this.initialEpisode = 0,
    this.offsetMs = 0,
    this.onProgressChanged,
    this.playMode = VideoPlayMode.online,
    this.allowProxyPlayback = true,
  });

  final String videoId;
  final String title;
  final String cover;
  final String? sourceKey;
  final List<VideoPlaySource> sources;
  final int initialSource;
  final int initialEpisode;
  final int offsetMs;
  final void Function(VideoPlaybackProgress progress)? onProgressChanged;

  /// 播放方式（决策层产出；默认 online = 原有行为）。
  final VideoPlayMode playMode;

  /// 是否允许解析后静默挂靠「播放即下载」代理（决策层在用户明确选择
  /// 「直接播放」时置 false，保证其与「合流播放」语义可区分）。
  final bool allowProxyPlayback;

  /// 目标 sourceId（历史 key 用）：`${sourceKey}:${videoId}`，无 sourceKey 时直接用 videoId。
  String get historySourceId => (sourceKey == null || sourceKey!.isEmpty)
      ? videoId
      : '$sourceKey:$videoId';
}
