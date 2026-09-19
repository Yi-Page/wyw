import 'package:wyw/services/storage/video_play_model.dart';

/// 通用历史记录进度抽象
///
/// 所有实现一律可通过 toMap() 转成以 String 为键、dynamic 为值的 Map 存入 HistoryEntry.progress；
/// 类型化包装（Video/Read/Comic）使用侧提供 fromMap 反序列化；
/// Custom 透传原始 Map。
abstract class HistoryProgress {
  Map<String, dynamic> toMap();
}

/// 视频进度：videoUrl + positionMs + durationMs
class VideoProgress implements HistoryProgress {
  final String videoUrl;
  final int positionMs;
  final int durationMs;

  const VideoProgress({
    required this.videoUrl,
    required this.positionMs,
    this.durationMs = 0,
  });

  @override
  Map<String, dynamic> toMap() => {
        'videoUrl': videoUrl,
        'positionMs': positionMs,
        'durationMs': durationMs,
      };

  factory VideoProgress.fromMap(Map m) => VideoProgress(
        videoUrl: m['videoUrl'] as String,
        positionMs: (m['positionMs'] as num).toInt(),
        durationMs: ((m['durationMs'] as num?)?.toInt()) ?? 0,
      );
}

/// 阅读进度：chapterId + charIndex + scrollY，以及重新进入小说阅读器所需的完整参数。
///
/// [chapters] 为可序列化的原始章节描述
/// （含 id / title / content 或 plugin / method / args），
/// 用于从历史页直接重建阅读器（等价于插件调用 `navigateToNovelReader` 时传入的 chapters）。
class ReadProgress implements HistoryProgress {
  final String chapterId;
  final int charIndex;
  final double scrollY;

  /// 小说 id
  final String novelId;

  /// 小说标题
  final String novelTitle;

  /// 来源插件 key
  final String sourceKey;

  /// 当前章节号（从 1 开始）
  final int chapter;

  /// 章节原始描述列表（可 JSON/Hive 序列化）
  final List<Map<String, dynamic>> chapters;

  const ReadProgress({
    required this.chapterId,
    this.charIndex = 0,
    this.scrollY = 0,
    this.novelId = '',
    this.novelTitle = '',
    this.sourceKey = '',
    this.chapter = 1,
    this.chapters = const [],
  });

  @override
  Map<String, dynamic> toMap() => {
        'chapterId': chapterId,
        'charIndex': charIndex,
        'scrollY': scrollY,
        'novelId': novelId,
        'novelTitle': novelTitle,
        'sourceKey': sourceKey,
        'chapter': chapter,
        'chapters': chapters,
      };

  factory ReadProgress.fromMap(Map m) => ReadProgress(
        chapterId: m['chapterId'] as String,
        charIndex: (m['charIndex'] as num?)?.toInt() ?? 0,
        scrollY: ((m['scrollY'] as num?)?.toDouble()) ?? 0,
        novelId: (m['novelId'] as String?) ?? '',
        novelTitle: (m['novelTitle'] as String?) ?? '',
        sourceKey: (m['sourceKey'] as String?) ?? '',
        chapter: (m['chapter'] as num?)?.toInt() ?? 1,
        chapters: (m['chapters'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            const [],
      );
}

/// 漫画进度：逐章进度 + 上次看到的章，以及重新进入阅读器所需的完整参数。
///
/// [chapterId]/[pageIndex] 为旧格式残留字段（= 上次看的章与页），新格式下
/// 以 [chapterProgress]（每章 chapterId/pageIndex/maxPage）为准；
/// 从旧记录反序列化时若没有 [chapterProgress]，用 chapterId/pageIndex 包成单章。
///
/// [chapters] 为可序列化的原始章节描述
/// （含 id / title / images 或 plugin / method / args），
/// 用于从历史页直接重建阅读器（等价于插件调用 `navigateToReader` 时传入的 chapters）。
class ComicProgress implements HistoryProgress {
  final String chapterId;
  final int pageIndex;

  /// 漫画 id
  final String comicId;

  /// 漫画标题
  final String comicTitle;

  /// 来源插件 key（如 `jm` / `copy_manga`）
  final String sourceKey;

  /// 章节原始描述列表（可 JSON/Hive 序列化）
  final List<Map<String, dynamic>> chapters;

  /// 每章进度（chapterId / pageIndex / maxPage）。
  final List<Map<String, dynamic>> chapterProgress;

  /// 上次看到的章（0-based；越界调用方夹取；-1 表示未知）。
  final int lastChapterIndex;

  const ComicProgress({
    required this.chapterId,
    required this.pageIndex,
    this.comicId = '',
    this.comicTitle = '',
    this.sourceKey = '',
    this.chapters = const [],
    this.chapterProgress = const [],
    this.lastChapterIndex = -1,
  });

  @override
  Map<String, dynamic> toMap() => {
        'chapterId': chapterId,
        'pageIndex': pageIndex,
        'comicId': comicId,
        'comicTitle': comicTitle,
        'sourceKey': sourceKey,
        'chapters': chapters,
        'chapterProgress': chapterProgress,
        'lastChapterIndex': lastChapterIndex,
      };

  factory ComicProgress.fromMap(Map m) {
    final chapters = (m['chapters'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        const <Map<String, dynamic>>[];
    final chapterId = (m['chapterId'] as String?) ?? '';
    final pageIndex = (m['pageIndex'] as num?)?.toInt() ?? 0;
    final chapterProgress = (m['chapterProgress'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        const <Map<String, dynamic>>[];

    // 旧格式：只有 chapterId/pageIndex，包成单章进度。
    final effectiveProgress = chapterProgress.isNotEmpty
        ? chapterProgress
        : (chapterId.isEmpty
            ? const <Map<String, dynamic>>[]
            : <Map<String, dynamic>>[
                {'chapterId': chapterId, 'pageIndex': pageIndex, 'maxPage': 0},
              ]);

    var lastChapterIndex = (m['lastChapterIndex'] as num?)?.toInt() ?? -1;
    if (lastChapterIndex < 0) {
      // 旧格式：按 chapterId 在 chapters 里定位上次章。
      final idx = chapters.indexWhere((c) => c['id'] == chapterId);
      if (idx >= 0) lastChapterIndex = idx;
    }

    return ComicProgress(
      chapterId: chapterId,
      pageIndex: pageIndex,
      comicId: (m['comicId'] as String?) ?? '',
      comicTitle: (m['comicTitle'] as String?) ?? '',
      sourceKey: (m['sourceKey'] as String?) ?? '',
      chapters: chapters,
      chapterProgress: effectiveProgress,
      lastChapterIndex: lastChapterIndex,
    );
  }
}

/// 自定义进度：透传原始 data Map
class CustomProgress implements HistoryProgress {
  final Map<String, dynamic> data;
  const CustomProgress(this.data);

  @override
  Map<String, dynamic> toMap() => data;
}

/// 漫画单章是否读完：**水位线**达到本章图片总数即算读完。
///
/// 水位线（`seenUpToImage`）是"曾经到达过的最大图片序号"，单调不回退，
/// 所以往回翻不会把已完成打回未完成；也不再依赖"当前位置"或末图高度。
///
/// 旧数据没有水位线：沿用既有的"页码 >= 图片数 - 1"容差，避免把旧记录里
/// 已完成（靠容差判出来的）条目打回未完成。
bool isComicChapterFinished(Map<String, dynamic> chapterProgress) {
  final imageCount = (chapterProgress['imageCount'] as num?)?.toInt() ??
      (chapterProgress['maxPage'] as num?)?.toInt() ??
      0;
  if (imageCount <= 0) return false;
  if (chapterProgress.containsKey('seenUpToImage')) {
    final seen = (chapterProgress['seenUpToImage'] as num?)?.toInt() ?? 0;
    return seen >= imageCount;
  }
  final page = (chapterProgress['pageIndex'] as num?)?.toInt() ?? 0;
  return page >= imageCount - 1;
}

/// 视频播放进度（v3，整部剧级）。
///
/// 与播放进入的 `VideoPageRouteArgs` 同构：携带完整播放源列表（含每集
/// 已解析直链与独立观看进度）+ 上次看到的线路/集，历史页据此重建播放上下文。
///
/// 兼容旧格式：progress 只含 `videoUrl/positionMs/durationMs`（v2 VideoProgress）
/// 时，`fromMap` 会包装成单源单集，历史页回退为"按 videoUrl 直链续播"。
class VideoPlaybackProgress implements HistoryProgress {
  final String videoId;

  /// 插件 key（'' 表示应用本地/无插件）。
  final String sourceKey;

  /// 完整播放源列表（含每集独立进度与已解析直链）。
  final List<VideoPlaySource> sources;

  /// 上次观看的线路（0-based；越界时调用方夹取）。
  final int lastSourceIndex;

  /// 上次观看的集（0-based；越界时调用方夹取）。
  final int lastEpisodeIndex;

  /// 最近一次解析出的媒体直链（续播回退；等同上次观看集的 effectiveUrl）。
  final String videoUrl;

  /// 最近一次观看时间（排序用，与 HistoryEntry.lastWatchTime 同步；null 表示未知）。
  final DateTime? lastWatchTime;

  const VideoPlaybackProgress({
    required this.videoId,
    this.sourceKey = '',
    this.sources = const [],
    this.lastSourceIndex = 0,
    this.lastEpisodeIndex = 0,
    this.videoUrl = '',
    this.lastWatchTime,
  });

  /// 当前集（夹取到合法范围后取值；无集时返回 null）。
  VideoPlayEpisode? get currentEpisode {
    if (sources.isEmpty) return null;
    final s = lastSourceIndex.clamp(0, sources.length - 1);
    final src = sources[s];
    if (src.episodes.isEmpty) return null;
    final e = lastEpisodeIndex.clamp(0, src.episodes.length - 1);
    return src.episodes[e];
  }

  @override
  Map<String, dynamic> toMap() => {
        'videoId': videoId,
        'sourceKey': sourceKey,
        'sources': [for (final s in sources) s.toMap()],
        'lastSourceIndex': lastSourceIndex,
        'lastEpisodeIndex': lastEpisodeIndex,
        'videoUrl': videoUrl,
        'lastWatchTime': lastWatchTime?.toIso8601String(),
      };

  factory VideoPlaybackProgress.fromMap(Map m) {
    final sources = (m['sources'] as List?)
            ?.map((e) =>
                VideoPlaySource.fromMap((e as Map).cast<String, dynamic>()))
            .toList() ??
        const <VideoPlaySource>[];
    final videoId = (m['videoId'] as String?) ?? '';
    final sourceKey = (m['sourceKey'] as String?) ?? '';

    return VideoPlaybackProgress(
      videoId: videoId,
      sourceKey: sourceKey,
      sources: sources,
      lastSourceIndex: (m['lastSourceIndex'] as num?)?.toInt() ?? 0,
      lastEpisodeIndex: (m['lastEpisodeIndex'] as num?)?.toInt() ?? 0,
      videoUrl: (m['videoUrl'] as String?) ?? '',
      lastWatchTime: m['lastWatchTime'] is String
          ? DateTime.tryParse(m['lastWatchTime'] as String)
          : null,
    );
  }
}
