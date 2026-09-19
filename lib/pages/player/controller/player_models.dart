/// Parameters required to initialize a player session.
///
/// Kept as a single value class so the entrypoint (search → video page)
/// has a single source of truth for what the player needs to know.
///
/// wyw's player pipeline is driven by webview-based video source sniffing
/// (`lib/webview/video/`), so this stays at the URL + headers level — no
/// bangumi/episode metadata. Anything the legacy upstream pipeline used to
/// thread through here
/// (bangumi id, episode number, plugin name, road index, local playback
/// flag) is intentionally absent; reintroduce only when the wyw-side
/// sniffer learns to surface it.
class PlaybackInitParams {
  final String videoUrl;
  final int offset;
  final Map<String, String> httpHeaders;
  final bool adBlockerEnabled;
  final String referer;
  final String videoTitle;
  final String videoCover;

  /// 历史记录使用的稳定源 ID。
  ///
  /// 播放 URL 可能是本地代理（合流播放）/本地文件路径，不能直接作为历史
  /// key（代理 URL 会失效、本地路径无法反查下载记录）。传入原始媒体直链
  /// 或下载剧集的稳定标识；为空时回退到 [videoUrl]。
  final String? historySourceId;

  const PlaybackInitParams({
    required this.videoUrl,
    required this.offset,
    required this.httpHeaders,
    required this.adBlockerEnabled,
    required this.referer,
    required this.videoTitle,
    required this.videoCover,
    this.historySourceId,
  });
}
