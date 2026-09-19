library;

// ============================================================================
// 阅读器 part 文件组织说明
// ----------------------------------------------------------------------------
// 本库按功能层拆分为多个 part 文件（与 novel_reader 的 part 组织保持一致）：
//   - comic_image.dart           通用漫画图片组件（进度/重试/尺寸缓存，可复用）
//   - reader_images.dart         图片渲染核心（画廊模式 _GalleryMode / 连续模式 _ContinuousMode）
//   - reader_scaffold.dart       阅读器外壳 UI（顶栏/底栏/设置抽屉/图片保存）
//   - reader_gesture.dart        手势交互层（点击翻页/双击缩放/长按/拖动）
//   - reader_chapters.dart       章节列表抽屉
// 各 part 通过 _ComicReaderState / _ComicReaderScaffoldState 等私有状态深度
// 耦合，part 可在保持模块分离的同时共享私有内部状态，避免把内部 API 全部公开。
// ============================================================================

import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:wyw/bean/styles/media_chrome_colors.dart';
import 'package:flutter_memory_info/flutter_memory_info.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/network/image_cache_manager.dart';
import 'package:wyw/utils/device.dart';

import '../image/image_downloader.dart';
import '../image/image_stitcher.dart';
import '../comic_reader_controller.dart';
import '../image/comic_image_provider.dart';
import '../models/comic_paging.dart';
import '../models/comic_reader_mode.dart';
import '../models/comic_reader_settings.dart';
import '../models/comic_reader_types.dart';
import 'comic_reader_settings_sheet.dart';
import 'volume_listener.dart';

part '../image/comic_image.dart';
part 'reader_images.dart';
part 'reader_scaffold.dart';
part 'reader_gesture.dart';
part 'reader_chapters.dart';

extension _ComicReaderContext on BuildContext {
  /// 可空访问器：供异步回调等 ancestor 可能已卸载的场景安全读取。
  _ComicReaderState? get maybeReader =>
      findAncestorStateOfType<_ComicReaderState>();

  _ComicReaderScaffoldState? get maybeReaderScaffold =>
      findAncestorStateOfType<_ComicReaderScaffoldState>();

  /// 非空访问器：仅用于同步场景（build / 事件回调），此时 ancestor 必然存在。
  _ComicReaderState get reader =>
      maybeReader ??
      (throw StateError('_ComicReaderState not found in ancestor chain'));

  _ComicReaderScaffoldState get readerScaffold =>
      maybeReaderScaffold ??
      (throw StateError(
          '_ComicReaderScaffoldState not found in ancestor chain'));
}

/// 漫画阅读器视图。
///
/// 负责阅读器的界面与渲染；数据/业务状态由 [ComicReaderController] 承载。
class ComicReader extends StatefulWidget {
  const ComicReader({super.key, required this.controller});

  final ComicReaderController controller;

  @override
  State<ComicReader> createState() => _ComicReaderState();
}

class _ComicReaderState extends State<ComicReader>
    with _ComicReaderWindow, _VolumeListener, _ImagePerPageHandler {
  late ComicReaderController controller;

  @override
  void initState() {
    controller = widget.controller;
    if (!ComicReaderSettings.getBool('showSystemStatusBar') && !isDesktop()) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    }
    if (ComicReaderSettings.getBool('enableTurnPageByVolumeKey')) {
      handleVolumeEvent();
    }
    setImageCacheSize();
    super.initState();
  }

  bool _isInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller.portrait = isPortrait;
    if (!_isInitialized) {
      _lastImagesPerPage = controller.imagesPerPage;
      _lastOrientation = isPortrait;
      _isInitialized = true;
    } else {
      // 屏幕方向变化
      _checkImagesPerPageChange();
    }
    initReaderWindow();
  }

  void setImageCacheSize() async {
    int? availableRAM;
    try {
      availableRAM = await MemoryInfo.getFreePhysicalMemorySize();
    } catch (e) {
      WywLogger().d('${LogTag.reader} 获取可用内存失败（跳过图片缓存自适应）', error: e);
      return;
    }
    if (availableRAM == null) return;
    int maxImageCacheSize;
    if (availableRAM < 1 << 30) {
      maxImageCacheSize = 100 << 20;
    } else if (availableRAM < 2 << 30) {
      maxImageCacheSize = 200 << 20;
    } else if (availableRAM < 4 << 30) {
      maxImageCacheSize = 300 << 20;
    } else {
      maxImageCacheSize = 500 << 20;
    }
    logger.i(
      'ComicReader: Detect available RAM: $availableRAM, set image cache size to $maxImageCacheSize',
    );
    PaintingBinding.instance.imageCache.maximumSizeBytes = maxImageCacheSize;
  }

  @override
  void dispose() {
    autoPageTurningTimer?.cancel();
    if (isFullscreen) {
      fullscreen();
    }
    focusNode.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    stopVolumeEvent();
    PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;
    disposeReaderWindow();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        _checkImagesPerPageChange();
        // 关键：必须在 Observer 构建期间读到 chapter，MobX 才能跟踪它；
        // 章节一变就重建 _ComicReaderImages（Key 变化 → State 重建 → 重新加载）。
        final currentChapter = chapter;
        return KeyboardListener(
          focusNode: focusNode,
          autofocus: true,
          onKeyEvent: onKeyEvent,
          child: _ComicReaderScaffold(
            child: _ComicReaderGestureDetector(
              child: _ComicReaderImages(
                key: Key('$currentChapter'),
              ),
            ),
          ),
        );
      },
    );
  }

  void onKeyEvent(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.f12 && event is KeyUpEvent) {
      fullscreen();
    }
    _imageViewController?.handleKeyEvent(event);
  }

  // ---- 委托给控制器（供 part 文件使用） ----

  List<ComicReaderChapter> get chapters => controller.chapters;

  String get comicTitle => controller.comicTitle;

  String get cid => controller.comicId;

  String get sourceKey => controller.sourceKey ?? '';

  String get eid => controller.eid;

  @override
  int get page => controller.page;

  @override
  set page(int value) => controller.setPage(value);

  int get chapter => controller.chapter;

  @override
  int get maxPage => controller.maxPage;

  /// 当前位置（规范单位：图片序号）。
  ///
  /// 画廊 = 当前屏阅读方向上的最后一张（6 张图每屏 2 张 → 2/4/6）；
  /// 连续模式 = 视口顶部（水位线）那张。
  int get frontierImage => controller.frontierImage;

  /// 本章图片总数（规范单位的分母）。
  int get imageCount => controller.images?.length ?? 0;

  int get totalPages => controller.totalPages;

  int get maxChapter => controller.maxChapter;

  bool get isLoading => controller.isLoading;

  set isLoading(bool value) => controller.isLoading = value;

  @override
  List<String>? get images => controller.images;

  set images(List<String>? value) => controller.images = value;

  @override
  ComicReaderMode get mode => controller.mode;

  set mode(ComicReaderMode value) => controller.mode = value;

  @override
  bool get isPortrait =>
      MediaQuery.of(context).orientation == Orientation.portrait;

  bool get isOnChapterCommentsPage => controller.isOnChapterCommentsPage;

  @override
  int get imagesPerPage => controller.imagesPerPage;

  @override
  bool showSingleImageOnFirstPage() => controller.showSingleImageOnFirstPage();

  bool get isFirstChapterOfGroup => controller.isFirstChapterOfGroup;

  bool get isLastChapterOfGroup => controller.isLastChapterOfGroup;

  /// 第 [page] 屏覆盖的图片区间（0-based 半开）；换算唯一来源在 controller。
  (int, int) imageRangeOfPage(int page) => controller.imageRangeOfPage(page);

  /// 指定章（0-based）的阅读前沿（图片序号，1-based）；未看过返回 0。
  int imageIndexOfChapter(int chapterIndex) =>
      controller.imageIndexOfChapter(chapterIndex);

  /// 指定章（0-based）图片总数；未知返回 0。
  int imageCountOfChapter(int chapterIndex) =>
      controller.imageCountOfChapter(chapterIndex);

  Timer? autoPageTurningTimer;

  void _handleJumpToLastPage() => controller.handleJumpToLastPage();

  void update() {
    setState(() {});
  }

  void updateHistory() {
    controller.notifyProgress();
  }

  int _animationCount = 0;

  int? _pendingPage;

  bool get isPageAnimating => _animationCount > 0;

  @override
  bool toNextPage() => toPage(page + 1);

  @override
  bool toPrevPage() => toPage(page - 1);

  /// 记录当前页（不带动画，供滑动翻页时同步页码）。
  void setPage(int value) => controller.setPage(value);

  /// 带翻页动画的跳页；动画关闭时直接跳转。
  bool toPage(int page) {
    if (page >= 1 && page <= controller.totalPages) {
      if (page == this.page && page != 1 && page != controller.totalPages) {
        return false;
      }
      final hasAnimation = ComicReaderSettings.getBool('enablePageAnimation');
      final vc = _imageViewController;
      if (hasAnimation && vc != null) {
        _pendingPage = page;
        _animationCount++;
        update();
        vc.animateToPage(page).whenComplete(() {
          _animationCount--;
          if (_pendingPage == page) {
            _pendingPage = null;
          }
          update();
        });
      } else {
        controller.setPage(page);
        vc?.toPage(page);
        update();
      }
      return true;
    }
    return false;
  }

  /// 直接跳页（无动画、不占用动画计数器），供进度条拖动使用。
  ///
  /// 进度条 onChanged 在拖动期间会高频触发，若走带动画的 toPage 会导致
  /// [_animationCount] 堆积、[isPageAnimating] 长时间为 true，
  /// AbsorbPointer 吞掉所有手势，表现为「卡住、无法滚动」。
  void jumpToPage(int page) {
    if (page < 1 || page > controller.totalPages) return;
    _animationCount = 0;
    _pendingPage = null;
    controller.setPage(page);
    _imageViewController?.toPage(page);
    update();
  }

  /// 跳到第 [imageIndex] 张图（规范单位）：按当前模式换算成屏/列表项后跳转。
  void jumpToImage(int imageIndex) {
    jumpToPage(pageOfImageIndex(
      imageIndex: imageIndex,
      imagesPerPage: controller.imagesPerPage,
      singleImageOnFirstPage: controller.showSingleImageOnFirstPage(),
      imageCount: imageCount,
    ));
  }

  @override
  bool toNextChapter() => controller.toNextChapter();

  @override
  bool toPrevChapter({bool toLastPage = false}) =>
      controller.toPrevChapter(toLastPage: toLastPage);

  bool toChapter(int c, {bool toLastPage = false}) =>
      controller.toChapter(c, toLastPage: toLastPage);

  /// 自动翻页开关（切换启动/停止）。
  ///
  /// 定时器放在视图层：翻页必须驱动 [_imageViewController] 真正移动视图，
  /// 而非仅修改 controller 中的页码数据。
  void autoPageTurning() {
    if (autoPageTurningTimer != null) {
      autoPageTurningTimer!.cancel();
      autoPageTurningTimer = null;
      update();
    } else {
      final interval = ComicReaderSettings.getInt('autoPageTurningInterval');
      autoPageTurningTimer = Timer.periodic(Duration(seconds: interval), (_) {
        if (page == maxPage) {
          autoPageTurningTimer!.cancel();
        }
        toNextPage();
      });
      update();
    }
  }

  Future<List<String>> loadChapterImages(int chapter) =>
      controller.loadImages(chapter);

  _ImageViewController? _imageViewController;

  var focusNode = FocusNode();

  /// 阅读器尺寸（不一定等于屏幕尺寸）。
  Size get size {
    final renderBox = context.findRenderObject() as RenderBox;
    return renderBox.size;
  }
}

abstract mixin class _ImagePerPageHandler {
  late int _lastImagesPerPage;

  late bool _lastOrientation;

  bool get isPortrait;

  int get page;

  set page(int value);

  ComicReaderMode get mode;

  int get maxPage;

  List<String>? get images;

  bool showSingleImageOnFirstPage() =>
      ComicReaderSettings.getBool('showSingleImageOnFirstPage');

  int get imagesPerPage;

  void _checkImagesPerPageChange() {
    int currentImagesPerPage = imagesPerPage;
    bool currentOrientation = isPortrait;

    if (_lastImagesPerPage != currentImagesPerPage ||
        _lastOrientation != currentOrientation) {
      _adjustPageForImagesPerPageChange(
        _lastImagesPerPage,
        currentImagesPerPage,
      );
      _lastImagesPerPage = currentImagesPerPage;
      _lastOrientation = currentOrientation;
    }
  }

  void _adjustPageForImagesPerPageChange(
    int oldImagesPerPage,
    int newImagesPerPage,
  ) {
    // 以**阅读前沿**（不是旧屏首图）为锚：换方向/换每屏张数后位置不倒退。
    final imageCount = images?.length ?? 0;
    var anchor = mode.isGallery
        ? imageIndexOfPage(
            page: page,
            imagesPerPage: oldImagesPerPage,
            singleImageOnFirstPage: showSingleImageOnFirstPage(),
            imageCount: imageCount,
          )
        : page;
    if (anchor < 1) anchor = 1;
    final newPage = pageOfImageIndex(
      imageIndex: anchor,
      imagesPerPage: newImagesPerPage,
      singleImageOnFirstPage: showSingleImageOnFirstPage(),
      imageCount: imageCount,
    );
    page = newPage.clamp(1, maxPage);
  }
}

abstract mixin class _VolumeListener {
  bool toNextPage();

  bool toPrevPage();

  bool toNextChapter();

  bool toPrevChapter({bool toLastPage = false});

  VolumeListener? volumeListener;

  void onDown() {
    if (!toNextPage()) {
      toNextChapter();
    }
  }

  void onUp() {
    if (!toPrevPage()) {
      toPrevChapter(toLastPage: true);
    }
  }

  void handleVolumeEvent() {
    if (!Platform.isAndroid) {
      return;
    }
    if (volumeListener != null) {
      volumeListener?.cancel();
    }
    volumeListener = VolumeListener(onDown: onDown, onUp: onUp)..listen();
  }

  void stopVolumeEvent() {
    if (volumeListener != null) {
      volumeListener?.cancel();
      volumeListener = null;
    }
  }
}

mixin class _ComicReaderWindow {
  bool isFullscreen = false;

  void initReaderWindow() {}

  void fullscreen() async {
    if (!isDesktop()) return;
    await windowManager.hide();
    await windowManager.setFullScreen(!isFullscreen);
    await windowManager.show();
    isFullscreen = !isFullscreen;
  }

  void disposeReaderWindow() {}
}

/// 图片视图控制器接口（Gallery / Continuous 模式实现）。
abstract interface class _ImageViewController {
  void toPage(int page);

  Future<void> animateToPage(int page);

  void handleDoubleTap(Offset location);

  void handleLongPressDown(Offset location);

  void handleLongPressUp(Offset location);

  void handleKeyEvent(KeyEvent event);

  /// 返回 true 表示事件已处理。
  bool handleOnTap(Offset location);

  String? getImageKeyByOffset(Offset offset);
}

/// 供 part 文件使用的日志便捷引用。
final logger = WywLogger();
