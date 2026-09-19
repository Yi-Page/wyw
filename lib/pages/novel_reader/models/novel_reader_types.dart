/// 小说章节模型。
///
/// 与漫画的 [ComicReaderChapter] 对应，但内容是**文本**而非图片。
/// 章节正文有两种提供方式：
/// - [content]：直接传入已解析好的正文文本
/// - [loadContent]：惰性加载回调（例如从小说源接口拉取），返回该章正文
///
/// 若两者都提供，优先使用 [content]。
class NovelReaderChapter {
  const NovelReaderChapter({
    required this.id,
    required this.title,
    this.content,
    this.loadContent,
  });

  /// 章节唯一 id（用于缓存 key / 历史记录）
  final String id;

  /// 章节标题
  final String title;

  /// 预加载的正文文本（可为空）
  final String? content;

  /// 惰性加载该章正文
  final Future<String> Function()? loadContent;
}

/// 小说阅读进度回调数据。
class NovelReaderProgress {
  const NovelReaderProgress({
    required this.chapter,
    required this.chapterId,
    this.scrollY = 0,
    this.charOffset = 0,
  });

  /// 当前章节（从 1 开始）
  final int chapter;

  /// 当前章节 id
  final String chapterId;

  /// 章节内滚动位置（0.0 ~ 1.0）
  final double scrollY;

  /// 章节内字符偏移（可选，用于精确恢复）
  final int charOffset;
}
