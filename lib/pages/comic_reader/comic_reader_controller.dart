// ignore_for_file: library_private_types_in_public_api

import 'package:mobx/mobx.dart';
import 'package:wyw/services/history/history_progress_reporter.dart';
import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/history_type.dart';

import 'models/comic_paging.dart' as paging;
import 'models/comic_reader_mode.dart';
import 'models/comic_reader_settings.dart';
import 'models/comic_reader_types.dart';

part 'comic_reader_controller.g.dart';

/// 阅读器控制器（路由级 Store 单例，见 [comicReaderModule] 的 provide）。
///
/// 承载阅读器的数据与业务状态（章节、页码、模式、图片列表、设置、进度），
/// 与界面解耦；路由参数经 [configure] 注入，界面通过 [ComicReader] 委托访问。
class ComicReaderController = _ComicReaderController
    with _$ComicReaderController;

abstract class _ComicReaderController with Store {
  // ---- configure 注入的路由参数 ----

  late String comicId;

  late String comicTitle;

  /// 可选漫画源标识，用于图片缓存 key 隔离。
  String? sourceKey;

  late List<ComicReaderChapter> chapters;

  String author = '';

  List<String> tags = const [];

  /// 阅读进度回调（页码为图片序号，从 1 开始）。
  void Function(ComicReaderProgress progress)? onProgressChanged;

  /// 逐章**阅读前沿**（chapterId → 图片序号，1-based；0 = 未看过）。
  ///
  /// 规范单位：与阅读模式 / 屏幕方向 / 每屏张数无关，写历史时组装成完整快照。
  final Map<String, int> _frontierImageByChapterId = {};

  /// 逐章**水位线**（chapterId → 曾经到达过的最大图片序号）。
  ///
  /// 单调递增，用于完成判定：往回翻不会让"已读完"回退。
  final Map<String, int> _seenUpToByChapterId = {};

  /// 逐章图片总数（chapterId → imageCount）。
  final Map<String, int> _imageCountByChapterId = {};

  /// 图片加载完成后要定位到的图片序号（0 = 无）。
  ///
  /// 屏号依赖"每屏几张"（模式 + 屏幕方向 + 设置）与本章图片总数，而
  /// [configure]/[toChapter] 执行时这两者还不是最新值，所以这里只挂起规范单位，
  /// 等图片加载完成（[handleJumpToLastPage]）再换算成屏号。
  int _pendingResumeImage = 0;

  /// 历史上次看的章（0-based；-1 表示无历史）。
  int _lastChapterFromHistory = -1;

  // ---- 可观察状态 ----

  @observable
  int chapter = 1;

  @observable
  int page = 1;

  @observable
  ComicReaderMode mode = ComicReaderMode.galleryLeftToRight;

  @observable
  List<String>? images;

  @observable
  bool isLoading = false;

  @observable
  bool jumpToLastPageOnLoad = false;

  /// 当前屏幕方向（由视图层在方向变化时更新）。
  @observable
  bool portrait = true;

  void configure({
    required String comicId,
    required String comicTitle,
    required List<ComicReaderChapter> chapters,
    int initialChapter = 1,
    int initialPage = 1,

    /// 续读位置（规范单位：图片序号，1-based；0 = 未指定）。
    ///
    /// 优先于 [initialPage]；[initialPage] 只用于旧口径的屏号。
    int initialImageIndex = 0,
    String author = '',
    List<String> tags = const [],
    String? sourceKey,
    void Function(ComicReaderProgress progress)? onProgressChanged,

    /// 进入时是否自动定位到历史记录的上次看的章/页（插件入口续读用）。
    bool autoResume = false,
  }) {
    this.comicId = comicId;
    this.comicTitle = comicTitle;
    this.chapters = chapters;
    this.author = author;
    this.tags = tags;
    this.sourceKey = sourceKey;
    this.onProgressChanged = onProgressChanged;
    _frontierImageByChapterId.clear();
    _seenUpToByChapterId.clear();
    _imageCountByChapterId.clear();
    _pendingResumeImage = 0;
    // mode 决定"每屏几张"，换算单位前必须先定好。
    mode = ComicReaderMode.fromKey(ComicReaderSettings.getString('readerMode'));
    _applyHistoryProgress();

    // 自动续读：调用方未显式指定章/页（均为默认 1）且有历史时，
    // 定位到历史上次看的章与页。
    final noExplicitPosition =
        initialChapter == 1 && initialPage == 1 && initialImageIndex <= 0;
    if (autoResume &&
        noExplicitPosition &&
        _lastChapterFromHistory >= 0 &&
        _lastChapterFromHistory < maxChapter) {
      chapter = _lastChapterFromHistory + 1;
      _setPendingResume(_frontierImageByChapterId[eid] ?? 0);
    } else {
      chapter = initialChapter.clamp(1, maxChapter);
      if (initialImageIndex > 0) {
        _setPendingResume(initialImageIndex);
      } else {
        // 旧口径：initialPage 是"屏号"，按原样使用。
        page = initialPage < 1 ? 1 : initialPage;
      }
    }
    images = null;
    isLoading = false;
    jumpToLastPageOnLoad = false;
  }

  /// 记录"图片加载完成后要定位到的图片序号"，并给出一个即时可用的屏号。
  void _setPendingResume(int imageIndex) {
    if (imageIndex <= 0) {
      _pendingResumeImage = 0;
      page = 1;
      return;
    }
    _pendingResumeImage = imageIndex;
    page = paging.pageOfImageIndex(
      imageIndex: imageIndex,
      imagesPerPage: imagesPerPage,
      singleImageOnFirstPage: showSingleImageOnFirstPage(),
    );
  }

  /// 进入时从历史记录回填逐章进度（不回填则会丢其它章的进度）。
  ///
  /// 新数据用规范单位 `imageIndex`；旧数据只有 `pageIndex`（屏号），按**当前模式**
  /// 的每屏张数换算成图片序号；旧数据里靠容差判出的"已完成"会被抬成水位线=图片总数，
  /// 避免迁移后把已读条目打回未完成。
  void _applyHistoryProgress() {
    _lastChapterFromHistory = -1;
    final historySourceId = sourceKey == null ? comicId : '$sourceKey:$comicId';
    final entry = HistoryProgressReporter()
        .findEntry(type: HistoryType.comic, sourceId: historySourceId);
    if (entry == null) return;
    final history = ComicProgress.fromMap(entry.progress);
    _lastChapterFromHistory = history.lastChapterIndex;
    for (final cp in history.chapterProgress) {
      final id = cp['chapterId'] as String?;
      if (id == null || id.isEmpty) continue;
      final imageCount = (cp['imageCount'] as num?)?.toInt() ??
          (cp['maxPage'] as num?)?.toInt() ??
          0;
      if (imageCount > 0) _imageCountByChapterId[id] = imageCount;

      var imageIndex = (cp['imageIndex'] as num?)?.toInt() ?? 0;
      final legacyPage = (cp['pageIndex'] as num?)?.toInt() ?? 0;
      if (imageIndex <= 0 && legacyPage > 0) {
        imageIndex = paging.imageIndexOfPage(
          page: legacyPage,
          imagesPerPage: imagesPerPage,
          singleImageOnFirstPage: showSingleImageOnFirstPage(),
          imageCount: imageCount,
        );
      }
      if (imageIndex > 0) _frontierImageByChapterId[id] = imageIndex;

      var seen = (cp['seenUpToImage'] as num?)?.toInt() ?? 0;
      if (seen <= 0) {
        // 旧数据没有水位线：已完成（旧容差判定）抬到图片总数，否则以当前位置起算。
        final legacyFinished =
            imageCount > 0 && legacyPage >= imageCount - 1;
        seen = legacyFinished ? imageCount : imageIndex;
      }
      if (seen > 0) _seenUpToByChapterId[id] = seen;
    }
  }

  // ---- 读取（computed）----

  int get maxChapter => chapters.isEmpty ? 1 : chapters.length;

  int get maxPage {
    // 图片为空（null 或空列表）时按 1 处理，避免 page.clamp(1, 0) 崩溃
    if (images == null || images!.isEmpty) return 1;
    return !showSingleImageOnFirstPage()
        ? (images!.length / imagesPerPage).ceil()
        : 1 + ((images!.length - 1) / imagesPerPage).ceil();
  }

  int get totalPages => maxPage;

  /// 第 [page] 屏（1-based）覆盖的图片区间 `[start, end)`（0-based，半开）。
  ///
  /// 画廊"一屏多张"的换算唯一来源；视图层不再自己算。
  (int, int) imageRangeOfPage(int page) => paging.imageRangeOfPage(
        page: page,
        imagesPerPage: imagesPerPage,
        singleImageOnFirstPage: showSingleImageOnFirstPage(),
        imageCount: images?.length ?? 0,
      );

  /// 当前位置（规范单位：图片序号，1-based；0 = 无图）。
  ///
  /// 画廊 = 当前屏阅读方向上的**最后一张**（这一屏读到哪）；
  /// 连续模式 1 项 = 1 张图，`page` 本身就是图片序号。
  int get frontierImage {
    final list = images;
    if (list == null || list.isEmpty) return 0;
    if (mode.isGallery) {
      return paging.imageIndexOfPage(
        page: page,
        imagesPerPage: imagesPerPage,
        singleImageOnFirstPage: showSingleImageOnFirstPage(),
        imageCount: list.length,
      );
    }
    return page.clamp(1, list.length);
  }

  String get eid {
    final ch = (chapter >= 1 && chapter <= chapters.length)
        ? chapters[chapter - 1]
        : null;
    return ch?.id ?? '0';
  }

  bool get isFirstChapterOfGroup => chapter == 1;

  bool get isLastChapterOfGroup => chapter == maxChapter;

  bool get isOnChapterCommentsPage => false;

  /// 一屏显示的图片数量。
  int get imagesPerPage {
    if (mode.isContinuous) return 1;
    if (portrait) {
      return ComicReaderSettings.getInt('readerScreenPicNumberForPortrait');
    } else {
      return ComicReaderSettings.getInt('readerScreenPicNumberForLandscape');
    }
  }

  bool showSingleImageOnFirstPage() =>
      ComicReaderSettings.getBool('showSingleImageOnFirstPage');

  int get preCacheCount => ComicReaderSettings.getInt('preloadImageCount');

  // ---- 写入 ----

  void setPage(int value) {
    if (page != value) {
      page = value;
      notifyProgress();
    }
  }

  /// 返回 true 表示翻页成功。
  bool toPage(int p) {
    if (p >= 1 && p <= totalPages) {
      if (p == page && p != 1 && p != totalPages) {
        return false;
      }
      page = p;
      notifyProgress();
      return true;
    }
    return false;
  }

  bool toNextPage() => toPage(page + 1);

  bool toPrevPage() => toPage(page - 1);

  /// 返回 true 表示切章成功。
  ///
  /// 切章就是「复位到进入前的状态」：页码回到第 1 页、清空图片、进入加载态。
  /// 视图层 [_ComicReaderImages] 以 chapter 为 Key，章节一变整个 State 重建，
  /// 自然地重新走一遍「无图→显示加载→拿图→显示」，无需会话号/待跳页等机制。
  ///
  /// [toLastPage] 为 true 时，图片加载完成后跳到本章最后一页（上划进入上一章）。
  bool toChapter(int c, {bool toLastPage = false}) {
    if (c >= 1 && c <= maxChapter) {
      chapter = c;
      if (toLastPage) {
        // 上划进上一章：加载完成后跳到本章最后一屏
        _pendingResumeImage = 0;
        page = 1;
      } else {
        // 定位到该章已读到的图片序号（未看过从第 1 屏开始）；
        // 屏号在图片加载完成后按最新模式/方向换算。
        _setPendingResume(imageIndexOfChapter(c - 1));
      }
      images = null;
      isLoading = true;
      jumpToLastPageOnLoad = toLastPage;
      notifyProgress();
      return true;
    }
    return false;
  }

  bool toNextChapter() => toChapter(chapter + 1);

  bool toPrevChapter({bool toLastPage = false}) =>
      toChapter(chapter - 1, toLastPage: toLastPage);

  /// 加载指定章节的图片链接列表。
  Future<List<String>> loadImages(int chapter) async {
    final ch = chapters[chapter - 1];
    if (ch.images != null) {
      return ch.images!;
    }
    if (ch.loadImages != null) {
      return await ch.loadImages!();
    }
    throw '章节 $chapter 没有可用的图片数据';
  }

  /// 指定章（0-based）的**阅读前沿**（图片序号，1-based）；未看过返回 0。
  int imageIndexOfChapter(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= chapters.length) return 0;
    return _frontierImageByChapterId[chapters[chapterIndex].id] ?? 0;
  }

  /// 指定章（0-based）图片总数；未知返回 0。
  int imageCountOfChapter(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= chapters.length) return 0;
    return _imageCountByChapterId[chapters[chapterIndex].id] ?? 0;
  }

  /// 图片加载完成后：先处理"跳到本章最后一屏"，否则把挂起的图片序号换算成屏号。
  ///
  /// 换算放在这里而不是 [configure]/[toChapter]，是因为屏号依赖"每屏几张"
  /// （模式 + 屏幕方向 + 设置）和本章图片总数，此时才都是最新值。
  void handleJumpToLastPage() {
    if (jumpToLastPageOnLoad) {
      jumpToLastPageOnLoad = false;
      _pendingResumeImage = 0;
      page = maxPage;
      notifyProgress();
      return;
    }
    final pending = _pendingResumeImage;
    if (pending > 0) {
      _pendingResumeImage = 0;
      page = paging
          .pageOfImageIndex(
            imageIndex: pending,
            imagesPerPage: imagesPerPage,
            singleImageOnFirstPage: showSingleImageOnFirstPage(),
            imageCount: images?.length ?? 0,
          )
          .clamp(1, maxPage);
    }
  }

  /// 上报进度：写入规范单位（前沿 + 水位线）并组装逐章快照。
  void notifyProgress() {
    final cid = eid;
    final frontier = cid == '0' ? 0 : frontierImage;
    if (cid != '0') {
      final list = images;
      if (list != null && list.isNotEmpty) {
        _imageCountByChapterId[cid] = list.length;
      }
      if (frontier > 0) {
        _frontierImageByChapterId[cid] = frontier;
        // 水位线单调递增：往回翻不回退，"已读完"才不会抖。
        final seen = _seenUpToByChapterId[cid] ?? 0;
        if (frontier > seen) _seenUpToByChapterId[cid] = frontier;
      }
    }
    onProgressChanged?.call(ComicReaderProgress(
      chapter: chapter,
      page: page,
      maxPage: images?.length ?? 1,
      chapterId: cid,
      imageIndex: frontier,
      imageCount: images?.length ?? 0,
      seenUpToImage: cid == '0' ? 0 : (_seenUpToByChapterId[cid] ?? 0),
      chapterProgress: [
        for (final ch in chapters)
          ComicChapterProgress(
            chapterId: ch.id,
            // 旧字段：按当前模式的每屏张数换算成屏号，只为兼容旧版本读取。
            pageIndex: _legacyPageIndexOfChapter(ch.id),
            maxPage: _imageCountByChapterId[ch.id] ?? 0,
            imageIndex: _frontierImageByChapterId[ch.id] ?? 0,
            imageCount: _imageCountByChapterId[ch.id] ?? 0,
            seenUpToImage: _seenUpToByChapterId[ch.id] ?? 0,
          ),
      ],
    ));
  }

  /// 旧口径屏号（仅供旧版本读取；新版本一律用 `imageIndex`）。
  int _legacyPageIndexOfChapter(String chapterId) {
    final imageIndex = _frontierImageByChapterId[chapterId] ?? 0;
    if (imageIndex <= 0) return 0;
    return paging.pageOfImageIndex(
      imageIndex: imageIndex,
      imagesPerPage: imagesPerPage,
      singleImageOnFirstPage: showSingleImageOnFirstPage(),
      imageCount: _imageCountByChapterId[chapterId] ?? 0,
    );
  }
}
