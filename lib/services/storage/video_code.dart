/// 作品级身份编码（进度记录的 `sourceId`、下载记录的归属）。
///
/// 规则：`<pluginName>:<videoId>`；`pluginName` 为空时退化为裸 `videoId`
/// （与 v2 旧记录、手动播放的既有口径一致，**不可更改**，否则老记录失联）。
///
/// 本类只提供**构造与拆分规则**，不代表调用点可以随手拼：
///   - 只有插件入口构造 code（见 `VideoEntryLauncher.openFromPlugin`）；
///   - 其余入口一律读取记录里已有的 code（`HistoryEntry.sourceId` /
///     `DownloadRecord.code`），不再各自拼接。
///
/// 历史上 `init_page` / `video_controller` / `download_controller` 各自拼过
/// 同一份 key，导致同一作品出现两套身份（进度用 `plugin:videoId`、下载用
/// `plugin_videoId.hashCode`），两边互相找不到。
abstract final class VideoCode {
  /// 宿主自产内容（无插件）的命名空间，用于下载记录的命名空间回退。
  static const String hostPlugin = 'wyw';

  /// 唯一的构造规则。
  ///
  /// `videoId` 为空时返回空串（调用方必须视为"不可进入播放"并拒绝）。
  static String of({required String pluginName, required String videoId}) {
    if (videoId.isEmpty) return '';
    return pluginName.isEmpty ? videoId : '$pluginName:$videoId';
  }

  /// code 的插件命名空间（无前缀时为空串）。
  ///
  /// 注意：只在**确定 code 带插件前缀**的场合使用（构造腿）。
  /// 裸 code（如手动播放的 URL）含 `:` 会被误切，因此按 code **反查记录**
  /// 一律用记录自身字段派生的 code 做全等比较，不做字符串拆解。
  static String pluginOf(String code) {
    final i = code.indexOf(':');
    return i <= 0 ? '' : code.substring(0, i);
  }

  /// code 里的作品 id（无前缀时即 code 本身）。
  static String videoIdOf(String code) {
    final i = code.indexOf(':');
    return i <= 0 ? code : code.substring(i + 1);
  }

  /// 按记录字段还原 code：新记录直接读 [code]，老记录从 sourceKey/videoId 派生。
  ///
  /// 老记录（`code` 字段加入之前创建）的 `sourceKey`/`videoId` 可能为空串，
  /// 此时返回空串——表示"无法与任何进度记录关联"，调用方按无进度处理。
  static String ofRecord({
    required String code,
    required String sourceKey,
    required String videoId,
  }) {
    if (code.isNotEmpty) return code;
    return of(pluginName: sourceKey, videoId: videoId);
  }
}
