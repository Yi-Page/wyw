/// 阅读器章节模型。
///
/// 与 venera 的 `ComicChapters` + `ComicSource.loadComicPages` 对应。
/// 图片数据有两种提供方式：
/// - [images]：直接传入已经解析好的图片链接列表
/// - [loadImages]：惰性加载回调（例如从漫画源接口拉取），返回该章的图片链接列表
///
/// 若两者都提供，优先使用 [images]。
class ComicReaderChapter {
  const ComicReaderChapter({
    required this.id,
    required this.title,
    this.images,
    this.loadImages,
  });

  /// 章节唯一 id（用于缓存 key / 历史记录）
  final String id;

  /// 章节标题
  final String title;

  /// 预加载的图片链接列表（可为空）
  final List<String>? images;

  /// 惰性加载该章图片链接列表
  final Future<List<String>> Function()? loadImages;
}

/// 单章阅读进度快照。
///
/// **规范单位是 [imageIndex]（章内图片序号，1-based）**；[pageIndex] 是旧口径的
/// "屏号"，只为兼容旧版本读取而继续写入（画廊一屏多张时屏号会随每屏张数/方向漂移）。
class ComicChapterProgress {
  const ComicChapterProgress({
    required this.chapterId,
    this.pageIndex = 0,
    this.maxPage = 0,
    this.imageIndex = 0,
    this.imageCount = 0,
    this.seenUpToImage = 0,
  });

  /// 章节唯一 id
  final String chapterId;

  /// 旧口径：本章看到第几屏（从 1 开始；0 = 未看过）
  final int pageIndex;

  /// 旧口径：本章图片总数（0 = 未知）
  final int maxPage;

  /// 本章**阅读前沿**：读到第几张图（1-based；0 = 未看过）
  final int imageIndex;

  /// 本章图片总数（0 = 未知）
  final int imageCount;

  /// 本章**水位线**：曾经到达过的最大图片序号（单调，用于完成判定）
  final int seenUpToImage;
}

/// 阅读进度回调数据。
class ComicReaderProgress {
  const ComicReaderProgress({
    required this.chapter,
    required this.page,
    required this.maxPage,
    required this.chapterId,
    this.imageIndex = 0,
    this.imageCount = 0,
    this.seenUpToImage = 0,
    this.chapterProgress = const [],
  });

  /// 当前章节（从 1 开始）
  final int chapter;

  /// 当前屏号（从 1 开始；连续模式下等于图片序号）
  final int page;

  /// 本章图片总数
  final int maxPage;

  /// 当前章节 id
  final String chapterId;

  /// 当前**阅读前沿**（图片序号，1-based；0 = 未知）
  final int imageIndex;

  /// 本章图片总数（0 = 未知）
  final int imageCount;

  /// 本章水位线（曾经到达过的最大图片序号）
  final int seenUpToImage;

  /// 每章阅读进度快照（controller 维护，供历史逐章持久化）。
  final List<ComicChapterProgress> chapterProgress;
}
