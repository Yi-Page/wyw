// ignore_for_file: library_private_types_in_public_api

import 'package:mobx/mobx.dart';

import 'models/novel_reader_settings.dart';
import 'models/novel_reader_mode.dart';
import 'models/novel_reader_types.dart';

part 'novel_reader_controller.g.dart';

/// 小说阅读器控制器（路由级 Store 单例，见 [novelReaderModule] 的 provide）。
///
/// 承载小说的数据与业务状态（章节、正文、阅读方式、进度、设置），与界面解耦。
/// 路由参数经 [configure] 注入；界面通过 [NovelReaderView] 委托访问。
class NovelReaderController = _NovelReaderController
    with _$NovelReaderController;

abstract class _NovelReaderController with Store {
  // ---- configure 注入的路由参数 ----

  late String novelId;

  late String novelTitle;

  /// 可选小说源标识，用于缓存 key 隔离。
  String? sourceKey;

  late List<NovelReaderChapter> chapters;

  /// 阅读进度回调。
  void Function(NovelReaderProgress progress)? onProgressChanged;

  // ---- 可观察状态 ----

  @observable
  int chapter = 1;

  @observable
  double fontSize = 18;

  @observable
  double lineHeight = 1.6;

  @observable
  NovelReaderMode mode = NovelReaderMode.scroll;

  @observable
  String? content;

  @observable
  bool isLoading = false;

  @observable
  bool jumpToLastOnLoad = false;

  /// 连续阅读已加载到的章节（滚动模式从 [chapter] 往前连续加载）。
  @observable
  int loadedUpTo = 1;

  /// 已加载正文的章节缓存（连续阅读时避免重复拉取）。
  final Map<int, String> _contentCache = {};

  void configure({
    required String novelId,
    required String novelTitle,
    required List<NovelReaderChapter> chapters,
    int initialChapter = 1,
    String? sourceKey,
    void Function(NovelReaderProgress progress)? onProgressChanged,
  }) {
    this.novelId = novelId;
    this.novelTitle = novelTitle;
    this.chapters = chapters;
    this.sourceKey = sourceKey;
    this.onProgressChanged = onProgressChanged;
    chapter = initialChapter.clamp(1, maxChapter);
    fontSize = NovelReaderSettings.getDouble('novelFontSize');
    lineHeight = NovelReaderSettings.getDouble('novelLineHeight');
    mode = NovelReaderMode.fromKey(
      NovelReaderSettings.getT<String>('novelMode'),
    );
    content = null;
    isLoading = false;
    jumpToLastOnLoad = false;
    loadedUpTo = chapter;
    _contentCache.clear();
  }

  // ---- 读取（computed）----

  int get maxChapter => chapters.isEmpty ? 1 : chapters.length;

  bool get isFirstChapter => chapter == 1;

  bool get isLastChapter => chapter == maxChapter;

  String get currentChapterId {
    final ch = (chapter >= 1 && chapter <= chapters.length)
        ? chapters[chapter - 1]
        : null;
    return ch?.id ?? '0';
  }

  String get currentChapterTitle {
    final ch = (chapter >= 1 && chapter <= chapters.length)
        ? chapters[chapter - 1]
        : null;
    return ch?.title ?? '';
  }

  // ---- 写入（带持久化的方法） ----

  void setFontSize(double value) {
    if ((fontSize - value).abs() > 0.01) {
      fontSize = value;
      NovelReaderSettings.set('novelFontSize', value);
    }
  }

  void setLineHeight(double value) {
    if ((lineHeight - value).abs() > 0.01) {
      lineHeight = value;
      NovelReaderSettings.set('novelLineHeight', value);
    }
  }

  void setMode(NovelReaderMode value) {
    if (mode != value) {
      mode = value;
      NovelReaderSettings.set('novelMode', value.key);
    }
  }

  /// 返回 true 表示切章成功。
  /// [toLast] 为 true 时，正文加载完成后跳到本章末尾。
  bool toChapter(int c, {bool toLast = false}) {
    if (c >= 1 && c <= maxChapter && !isLoading) {
      chapter = c;
      loadedUpTo = c;
      content = _contentCache[c];
      jumpToLastOnLoad = toLast;
      notifyProgress();
      return true;
    }
    return false;
  }

  bool toNextChapter() => toChapter(chapter + 1);

  bool toPrevChapter({bool toLast = false}) =>
      toChapter(chapter - 1, toLast: toLast);

  /// 静默更新当前章节（滚动定位用），不重置内容/不标记跳末页。
  void setChapterSilently(int c) {
    if (c >= 1 && c <= maxChapter && c != chapter) {
      chapter = c;
      loadedUpTo = c;
    }
  }

  /// 加载指定章节的正文（带缓存）。
  Future<String> loadContent(int chapter) async {
    final cached = _contentCache[chapter];
    if (cached != null) {
      return cached;
    }
    final ch = chapters[chapter - 1];
    final String body;
    if (ch.content != null) {
      body = ch.content!;
    } else if (ch.loadContent != null) {
      body = await ch.loadContent!();
    } else {
      throw '章节 $chapter 没有可用的正文数据';
    }
    _contentCache[chapter] = body;
    return body;
  }

  /// 连续阅读：加载下一章并推进 [loadedUpTo]。
  /// 返回 true 表示成功加载了下一章；false 表示已是最后一章或正在加载。
  Future<bool> loadNextChapter() async {
    if (isLoading) return false;
    final next = loadedUpTo + 1;
    if (next > maxChapter) return false;
    isLoading = true;
    try {
      await loadContent(next);
      loadedUpTo = next;
      chapter = next;
      notifyProgress();
      return true;
    } finally {
      isLoading = false;
    }
  }

  /// 正文加载完成后处理"跳到本章末尾"标记。
  void handleJumpToLast() {
    if (jumpToLastOnLoad) {
      jumpToLastOnLoad = false;
    }
  }

  void notifyProgress() => notifyProgressWith(0);

  void notifyProgressWith(double scrollY) {
    onProgressChanged?.call(NovelReaderProgress(
      chapter: chapter,
      chapterId: currentChapterId,
      scrollY: scrollY,
    ));
  }
}
