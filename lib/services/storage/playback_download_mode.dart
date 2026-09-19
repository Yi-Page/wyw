/// 进入播放页时的「播放 ↔ 下载」协作模式。
///
/// 三种模式：
///  - [playOnly]：只播放不下载。即使该视频已有下载任务，也不自动切换
///    本地代理播放（任务仍在后台正常下载）。
///  - [playAndDownload]：边播放边下载（默认）。进入播放页时若该视频已有
///    下载任务，自动切换到本地代理播放，播放即下载。
///  - [downloadOnly]：不播放只下载。进入播放页时先弹窗确认，确认后创建/
///    继续下载任务并返回上一页，不进入播放器。
enum PlaybackDownloadMode {
  playOnly('playOnly', '只播放不下载'),
  playAndDownload('playAndDownload', '边播放边下载'),
  downloadOnly('downloadOnly', '不播放只下载');

  const PlaybackDownloadMode(this.value, this.label);

  /// 持久化到设置里的字符串值（保持稳定，勿随意修改）。
  final String value;

  /// 设置页展示名。
  final String label;

  static PlaybackDownloadMode fromValue(String? value) {
    for (final mode in values) {
      if (mode.value == value) return mode;
    }
    return PlaybackDownloadMode.playAndDownload;
  }
}
