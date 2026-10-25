import 'package:hive_ce/hive.dart';

import 'package:wyw/services/storage/video_code.dart';

part 'download_module.g.dart';

@HiveType(typeId: 7)
class DownloadRecord {
  @HiveField(0)
  int mediaId;

  @HiveField(1)
  String mediaName;

  @HiveField(2)
  String mediaCover;

  @HiveField(3)
  String pluginName;

  @HiveField(4)
  Map<int, DownloadEpisode> episodes;

  @HiveField(5)
  DateTime createdAt;

  /// 结构化视频 id（插件进入时提供；无则为空串）
  @HiveField(6, defaultValue: '')
  String videoId;

  /// 插件 key（与 pluginName 解耦；空串表示本地/无插件）
  @HiveField(7, defaultValue: '')
  String sourceKey;

  /// 归属的**进度记录 code**（作品级身份，见 `VideoCode`）。
  ///
  /// 下载记录与进度记录之间的唯一引用：由它可反查进度记录（含完整源/集列表），
  /// 进度侧也可由 code 反查本记录。空串表示"无法关联"（`code` 字段加入之前
  /// 创建的老记录，且 `sourceKey`/`videoId` 也为空），按无进度处理。
  @HiveField(8, defaultValue: '')
  String code;

  /// 记录自身的 code（老记录从 sourceKey/videoId 派生）。
  String get effectiveCode =>
      VideoCode.ofRecord(code: code, sourceKey: sourceKey, videoId: videoId);

  String get key => '${pluginName}_$mediaId';

  DownloadRecord(
    this.mediaId,
    this.mediaName,
    this.mediaCover,
    this.pluginName,
    this.episodes,
    this.createdAt, {
    this.videoId = '',
    this.sourceKey = '',
    this.code = '',
  });
}

@HiveType(typeId: 8)
class DownloadEpisode {
  @HiveField(0)
  int episodeNumber;

  @HiveField(1)
  String episodeName;

  @HiveField(2)
  int road;

  /// 0=pending 1=resolving 2=downloading 3=completed 4=failed 5=paused
  @HiveField(3)
  int status;

  @HiveField(4)
  double progressPercent;

  @HiveField(5)
  int totalSegments;

  @HiveField(6)
  int downloadedSegments;

  @HiveField(7)
  String localM3u8Path;

  @HiveField(8)
  String downloadDirectory;

  @HiveField(9)
  String networkM3u8Url;

  @HiveField(10)
  DateTime? completedAt;

  @HiveField(11, defaultValue: '')
  String errorMessage;

  @HiveField(12, defaultValue: 0)
  int totalBytes;

  /// 缓存的弹幕数据 (JSON 字符串格式)
  @HiveField(14, defaultValue: '')
  String danmakuData;

  /// DanDanPlay 媒体 ID (用于弹幕查询缓存)
  @HiveField(15, defaultValue: 0)
  int danDanBangumiID;

  /// 线路 0-based（结构化下载时使用）
  @HiveField(16, defaultValue: 0)
  int sourceIndex;

  /// 线路名（结构化下载时使用）
  @HiveField(17, defaultValue: '')
  String sourceName;

  DownloadEpisode(
    this.episodeNumber,
    this.episodeName,
    this.road,
    this.status,
    this.progressPercent,
    this.totalSegments,
    this.downloadedSegments,
    this.localM3u8Path,
    this.downloadDirectory,
    this.networkM3u8Url,
    this.completedAt,
    this.errorMessage,
    this.totalBytes, {
    this.danmakuData = '',
    this.danDanBangumiID = 0,
    this.sourceIndex = 0,
    this.sourceName = '',
  });
}

class DownloadStatus {
  static const int pending = 0;
  static const int resolving = 1;
  static const int downloading = 2;
  static const int completed = 3;
  static const int failed = 4;
  static const int paused = 5;
}

/// 结构化集数 → 全局唯一 episodeNumber（作为 DownloadRecord.episodes 的 Map 键）。
///
/// 单线路集数上限 100000；反解用 [sourceIndexOf] / [episodeIndexOf]。
int structuredEpisodeNumber(int sourceIndex, int episodeIndex) =>
    (sourceIndex + 1) * 100000 + (episodeIndex + 1);

/// 从全局唯一 episodeNumber 反解出线路 index（0-based）。
int sourceIndexOf(int episodeNumber) => episodeNumber ~/ 100000 - 1;

/// 从全局唯一 episodeNumber 反解出集数 index（0-based）。
int episodeIndexOf(int episodeNumber) => episodeNumber % 100000 - 1;

/// 选集面板里「剧集 → 下载任务」映射的键（线路:集数，均 0-based）。
///
/// Kazumi 那边用剧集页 URL 当这个键；wyw 的 [DownloadEpisode] 没有 URL 字段，
/// 但带结构化线路/集数，所以用索引当键（见 `DownloadController.episodeDownloadsFor`）。
String episodeDownloadKey(int sourceIndex, int episodeIndex) =>
    '$sourceIndex:$episodeIndex';
