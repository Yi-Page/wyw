// ignore_for_file: use_build_context_synchronously

part of 'comic_reader.dart';

class _ComicReaderImages extends StatefulWidget {
  const _ComicReaderImages({super.key});

  @override
  State<_ComicReaderImages> createState() => _ComicReaderImagesState();
}

class _ComicReaderImagesState extends State<_ComicReaderImages> {
  String? error;

  bool inProgress = false;

  late _ComicReaderState reader;

  @override
  void initState() {
    reader = context.reader;
    reader.isLoading = true;
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    ImageDownloader.cancelAllLoadingImages();
  }

  void _handleJumpToLastPage() {
    reader._handleJumpToLastPage();
  }

  /// 加载当前章节图片。
  ///
  /// 这个 State 以 chapter 为 Key（见 [_ComicReaderImages] 的构建处），
  /// 切章后整个 State 重建，旧 State 的 in-flight load 因 !mounted 直接作废，
  /// 天然不会出现旧章节覆盖新章节的问题，无需会话号。
  void load() async {
    if (inProgress) return;
    inProgress = true;
    try {
      final images = await reader.loadChapterImages(reader.chapter);
      if (!mounted) return;
      setState(() {
        reader.images = images;
        error = null;
        reader.isLoading = false;
        inProgress = false;
        _handleJumpToLastPage();
        Future.microtask(() {
          reader.updateHistory();
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        reader.isLoading = false;
        inProgress = false;
      });
    }
    // load() 是异步方法，await 间隙后 State 可能已被销毁；
    // 此时再沿 context 向上找 ancestor 会因 `!` 崩溃，必须先查 mounted。
    if (!mounted) return;
    context.readerScaffold.update();
  }

  @override
  Widget build(BuildContext context) {
    if (reader.isLoading) {
      load();
      return const Center(child: CircularProgressIndicator());
    } else if (error != null) {
      return GestureDetector(
        onTap: () {
          context.readerScaffold.openOrClose();
        },
        child: SizedBox.expand(
          child: _NetworkError(
            message: error!,
            retry: () {
              setState(() {
                reader.isLoading = true;
                error = null;
              });
            },
          ),
        ),
      );
    } else {
      if (reader.mode.isGallery) {
        return _GalleryMode(
            key: Key('${reader.mode.key}_${reader.imagesPerPage}'));
      } else {
        return _ContinuousMode(key: Key(reader.mode.key));
      }
    }
  }
}

class _NetworkError extends StatelessWidget {
  const _NetworkError({required this.message, required this.retry});

  final String message;

  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image, size: 48, color: colorScheme.error),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: retry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _GalleryMode extends StatefulWidget {
  const _GalleryMode({super.key});

  @override
  State<_GalleryMode> createState() => _GalleryModeState();
}

class _GalleryModeState extends State<_GalleryMode>
    implements _ImageViewController {
  late PageController controller;

  int get preCacheCount => ComicReaderSettings.getInt('preloadImageCount');

  final photoViewControllers = <int, PhotoViewController>{};

  final scaleStateControllers = <int, PhotoViewScaleStateController>{};

  late _ComicReaderState reader;

  int get totalPages => reader.totalPages;

  final imageStates = <State<ComicImage>>{};

  bool isLongPressing = false;

  int fingers = 0;

  @override
  void initState() {
    reader = context.reader;
    // 切章时 toChapter 已把 page 复位到 1（toLastPage 则在加载完成后由
    // handleJumpToLastPage 调到末页），这里直接按当前页码建控制器即可。
    controller = PageController(initialPage: reader.page);
    reader._imageViewController = this;
    Future.microtask(() {
      if (!context.mounted) return;
      context.readerScaffold.setFloatingButton(0);
    });
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// 获取某页（1-based）对应的图片索引范围 [start, end)。
  ///
  /// 换算唯一来源在 controller（[ComicReaderController.imageRangeOfPage]）。
  (int start, int end) getPageImagesRange(int page) =>
      reader.imageRangeOfPage(page);

  /// 获取当前页的图片索引范围；无图片时返回 null。
  (int, int)? getCurrentPageImageRange() {
    if (reader.images == null || reader.images!.isEmpty) {
      return null;
    }
    return getPageImagesRange(reader.page);
  }

  void cache(int startPage) {
    for (int i = startPage - 1; i <= startPage + preCacheCount; i++) {
      if (i == startPage || i <= 0 || i > totalPages) {
        continue;
      }
      _cachePage(i, i == startPage + 1 || i == startPage - 1);
    }
  }

  void _cachePage(int page, bool shouldPreCache) {
    var (startIndex, endIndex) = getPageImagesRange(page);
    for (int i = startIndex; i < endIndex; i++) {
      shouldPreCache
          ? _precacheImage(i + 1, context)
          : _preDownloadImage(i + 1, context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Listener(
      onPointerDown: (event) {
        fingers++;
      },
      onPointerUp: (event) {
        fingers--;
      },
      onPointerCancel: (event) {
        fingers--;
      },
      onPointerMove: (event) {
        if (isLongPressing) {
          var controller = photoViewControllers[reader.page]!;
          Offset value = event.delta;
          controller.updateMultiple(position: controller.position + value);
        }
      },
      child: PhotoViewGallery.builder(
        backgroundDecoration: BoxDecoration(color: colorScheme.surface),
        reverse: reader.mode == ComicReaderMode.galleryRightToLeft,
        scrollDirection: reader.mode == ComicReaderMode.galleryTopToBottom
            ? Axis.vertical
            : Axis.horizontal,
        itemCount: totalPages + 2,
        builder: (BuildContext context, int index) {
          if (index == 0 || index == totalPages + 1) {
            return PhotoViewGalleryPageOptions.customChild(
              child: const SizedBox(),
            );
          } else {
            var (startIndex, endIndex) = getPageImagesRange(index);
            List<String> pageImages = reader.images!.sublist(
              startIndex,
              endIndex,
            );

            cache(index);

            photoViewControllers[index] ??= PhotoViewController();
            scaleStateControllers[index] ??= PhotoViewScaleStateController();

            if (reader.imagesPerPage == 1 || pageImages.length == 1) {
              return PhotoViewGalleryPageOptions(
                filterQuality: FilterQuality.medium,
                controller: photoViewControllers[index],
                scaleStateController: scaleStateControllers[index],
                imageProvider: _createImageProviderFromKey(
                  pageImages[0],
                  context,
                  startIndex + 1,
                ),
                errorBuilder: (_, error, s) {
                  return _NetworkError(
                    message: error.toString(),
                    retry: () {
                      PaintingBinding.instance.imageCache.evict(
                        _createImageProviderFromKey(
                          pageImages[0],
                          context,
                          startIndex + 1,
                        ),
                      );
                      precacheImage(
                        _createImageProviderFromKey(
                          pageImages[0],
                          context,
                          startIndex + 1,
                        ),
                        context,
                      );
                    },
                  );
                },
              );
            }

            final viewportSize = MediaQuery.of(context).size;
            return PhotoViewGalleryPageOptions.customChild(
              childSize: viewportSize,
              controller: photoViewControllers[index],
              scaleStateController: scaleStateControllers[index],
              minScale: PhotoViewComputedScale.contained * 1.0,
              maxScale: PhotoViewComputedScale.covered * 10.0,
              child: buildPageImages(pageImages, startIndex),
            );
          }
        },
        pageController: controller,
        loadingBuilder: (context, event) {
          return PhotoView.customChild(
            childSize: MediaQuery.of(context).size,
            initialScale: PhotoViewComputedScale.contained,
            minScale: PhotoViewComputedScale.contained * 1.0,
            maxScale: PhotoViewComputedScale.covered * 10.0,
            backgroundDecoration: BoxDecoration(
              color: colorScheme.surface,
            ),
            child: Center(
              child: SizedBox(
                width: 20.0,
                height: 20.0,
                child: CircularProgressIndicator(
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  value: event == null || event.expectedTotalBytes == null
                      ? null
                      : event.cumulativeBytesLoaded / event.expectedTotalBytes!,
                ),
              ),
            ),
          );
        },
        onPageChanged: (i) {
          if (i == 0) {
            if (reader.isFirstChapterOfGroup ||
                !reader.toPrevChapter(toLastPage: true)) {
              controller.jumpToPage(1);
            }
          } else if (i == totalPages + 1) {
            if (reader.isLastChapterOfGroup || !reader.toNextChapter()) {
              controller.jumpToPage(totalPages);
            }
          } else {
            reader.setPage(i);
            context.readerScaffold.update();
          }
          // 移除其他页面的控制器，重置其状态
          final keys = photoViewControllers.keys.toList();
          for (var key in keys) {
            if (key != i) {
              photoViewControllers.remove(key);
              scaleStateControllers.remove(key);
            }
          }
        },
      ),
    );
  }

  Widget buildPageImages(List<String> images, int startIndex) {
    Axis axis = (reader.mode == ComicReaderMode.galleryTopToBottom)
        ? Axis.vertical
        : Axis.horizontal;

    bool reverse = reader.mode == ComicReaderMode.galleryRightToLeft;
    if (reverse) {
      images = images.reversed.toList();
    }

    List<Widget> imageWidgets;

    if (images.length == 2) {
      imageWidgets = [
        Expanded(
          child: ComicImage(
            width: double.infinity,
            height: double.infinity,
            image:
                _createImageProviderFromKey(images[0], context, startIndex + 1),
            fit: BoxFit.contain,
            alignment: axis == Axis.vertical
                ? Alignment.bottomCenter
                : Alignment.centerRight,
            onInit: (state) => imageStates.add(state),
            onDispose: (state) => imageStates.remove(state),
            onRetryTap: () =>
                context.readerScaffold._gestureDetectorState?.ignoreNextTap(),
          ),
        ),
        Expanded(
          child: ComicImage(
            width: double.infinity,
            height: double.infinity,
            image:
                _createImageProviderFromKey(images[1], context, startIndex + 2),
            fit: BoxFit.contain,
            alignment: axis == Axis.vertical
                ? Alignment.topCenter
                : Alignment.centerLeft,
            onInit: (state) => imageStates.add(state),
            onDispose: (state) => imageStates.remove(state),
            onRetryTap: () =>
                context.readerScaffold._gestureDetectorState?.ignoreNextTap(),
          ),
        ),
      ];
    } else {
      imageWidgets = images.map((imageKey) {
        startIndex++;
        ImageProvider imageProvider = _createImageProviderFromKey(
          imageKey,
          context,
          startIndex,
        );
        return Expanded(
          child: ComicImage(
            image: imageProvider,
            fit: BoxFit.contain,
            onInit: (state) => imageStates.add(state),
            onDispose: (state) => imageStates.remove(state),
            onRetryTap: () =>
                context.readerScaffold._gestureDetectorState?.ignoreNextTap(),
          ),
        );
      }).toList();
    }

    return axis == Axis.vertical
        ? Column(children: imageWidgets)
        : Row(children: imageWidgets);
  }

  @override
  Future<void> animateToPage(int page) {
    final current = controller.page;
    if (current == null) {
      controller.jumpToPage(page);
      return Future.value();
    }
    if ((page - current.round()).abs() > 1) {
      controller.jumpToPage(page > current ? page - 1 : page + 1);
    }
    return controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 200),
      curve: Curves.ease,
    );
  }

  @override
  void toPage(int page) {
    controller.jumpToPage(page);
  }

  @override
  void handleDoubleTap(Offset location) {
    final scaleStateController = scaleStateControllers[reader.page];
    if (scaleStateController == null) return;
    scaleStateController.scaleState =
        scaleStateController.scaleState == PhotoViewScaleState.zoomedIn
            ? PhotoViewScaleState.zoomedOut
            : PhotoViewScaleState.zoomedIn;
  }

  @override
  void handleLongPressDown(Offset location) {
    if (!ComicReaderSettings.getBool('enableLongPressToZoom') || fingers != 1) {
      return;
    }
    var photoViewController = photoViewControllers[reader.page]!;
    _initialScale = photoViewController.scale ?? 1.0;
    double target = _initialScale * 1.75;
    var size = reader.size;
    Offset zoomPosition;
    if (ComicReaderSettings.getString('longPressZoomPosition') != 'center') {
      zoomPosition = Offset(
        size.width / 2 - location.dx,
        size.height / 2 - location.dy,
      );
    } else {
      zoomPosition = Offset(0, 0);
    }
    photoViewController.updateMultiple(scale: target, position: zoomPosition);
    isLongPressing = true;
  }

  @override
  void handleLongPressUp(Offset location) {
    if (!ComicReaderSettings.getBool('enableLongPressToZoom') ||
        !isLongPressing) {
      return;
    }
    var photoViewController = photoViewControllers[reader.page]!;
    photoViewController.updateMultiple(
        scale: _initialScale, position: Offset.zero);
    isLongPressing = false;
  }

  double _initialScale = 1.0;

  Timer? keyRepeatTimer;

  @override
  void handleKeyEvent(KeyEvent event) {
    bool? forward;
    if (reader.mode == ComicReaderMode.galleryLeftToRight &&
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      forward = true;
    } else if (reader.mode == ComicReaderMode.galleryRightToLeft &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      forward = true;
    } else if (reader.mode == ComicReaderMode.galleryTopToBottom &&
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      forward = true;
    } else if (reader.mode == ComicReaderMode.galleryTopToBottom &&
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      forward = false;
    } else if (reader.mode == ComicReaderMode.galleryLeftToRight &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      forward = false;
    } else if (reader.mode == ComicReaderMode.galleryRightToLeft &&
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      forward = false;
    }
    if (event is KeyDownEvent) {
      if (keyRepeatTimer != null) {
        keyRepeatTimer!.cancel();
        keyRepeatTimer = null;
      }
      if (forward == true) {
        reader.toPage(reader.page + 1);
      } else if (forward == false) {
        reader.toPage(reader.page - 1);
      }
    }
    if (event is KeyRepeatEvent && keyRepeatTimer == null) {
      keyRepeatTimer = Timer.periodic(
        ComicReaderSettings.getBool('enablePageAnimation')
            ? const Duration(milliseconds: 200)
            : const Duration(milliseconds: 50),
        (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          } else if (forward == true) {
            reader.toPage(reader.page + 1);
          } else if (forward == false) {
            reader.toPage(reader.page - 1);
          }
        },
      );
    }
    if (event is KeyUpEvent && keyRepeatTimer != null) {
      keyRepeatTimer!.cancel();
      keyRepeatTimer = null;
    }
  }

  @override
  bool handleOnTap(Offset location) {
    return false;
  }

  @override
  String? getImageKeyByOffset(Offset offset) {
    final images = reader.images;
    if (images == null || images.isEmpty) return null;
    var range = getCurrentPageImageRange();
    if (range == null) return null;

    var (startIndex, endIndex) = range;
    int actualImageCount = endIndex - startIndex;
    // 本屏没有图片（页码越界/切换中）时不要回退取图，否则会越界。
    if (actualImageCount <= 0 || startIndex >= images.length) return null;

    if (actualImageCount == 1) {
      return images[startIndex];
    }

    for (var imageState in imageStates) {
      if ((imageState as _ComicImageState).containsPoint(offset)) {
        var imageKey =
            (imageState.widget.image as ComicReaderImageProvider).imageKey;
        int index = images.indexOf(imageKey);
        if (index >= startIndex && index < endIndex) {
          return imageKey;
        }
      }
    }

    return images[startIndex];
  }
}

double get _kChangeChapterOffset =>
    ComicReaderSettings.getDouble('continuousChapterSwitchThreshold');

class _ContinuousMode extends StatefulWidget {
  const _ContinuousMode({super.key});

  @override
  State<_ContinuousMode> createState() => _ContinuousModeState();
}

class _ContinuousModeState extends State<_ContinuousMode>
    implements _ImageViewController {
  late _ComicReaderState reader;

  var itemScrollController = ItemScrollController();
  var itemPositionsListener = ItemPositionsListener.create();
  var scrollOffsetController = ScrollOffsetController();
  var photoViewController = PhotoViewController();
  var scaleStateController = PhotoViewScaleStateController();
  double _scrollOffset = 0.0;

  /// 列表尾部占位长度（主轴向）：让**末图顶端**也能越过视口顶部（水位线）。
  ///
  /// 见 [_syncTailExtent]：按实测末图长度动态算成 `视口长度 - 末图长度`，
  /// 末图比视口高时为 0（不需要留白）。
  double _tailExtent = 0;

  /// 让末图顶端略微越过水位线，避免浮点误差导致它不算"当前页"。
  static const double _tailEpsilon = 2;

  /// 视口在主轴向的长度（上→下用高度，横向模式用宽度）。
  double get _viewportExtent =>
      reader.mode == ComicReaderMode.continuousTopToBottom
          ? reader.size.height
          : reader.size.width;

  var isCTRLPressed = false;
  static var _isMouseScrolling = false;
  var fingers = 0;
  bool disableScroll = false;

  late List<bool> cached;

  int get preCacheCount => ComicReaderSettings.getInt('preloadImageCount');

  bool delayedIsScrolling = false;

  final imageStates = <State<ComicImage>>{};

  void delayedSetIsScrolling(bool value) {
    Future.delayed(
      const Duration(milliseconds: 300),
      () {
        if (!mounted) return;
        delayedIsScrolling = value;
      },
    );
  }

  bool prepareToPrevChapter = false;
  bool prepareToNextChapter = false;
  bool jumpToNextChapter = false;
  bool jumpToPrevChapter = false;

  bool isZoomedIn = false;
  bool isLongPressing = false;

  double _initialScale = 1.0;

  @override
  void initState() {
    reader = context.reader;
    reader._imageViewController = this;
    itemPositionsListener.itemPositions.addListener(onPositionChanged);
    photoViewController.addIgnorableListener(_onPhotoViewChanged);
    cached = List.filled(reader.maxPage + 2, false);
    Future.delayed(
      const Duration(milliseconds: 100),
      () {
        // State 可能在延迟期间被销毁（如立即退出阅读器），
        // 此时不能再触发预下载。
        if (!mounted) return;
        cacheImages(reader.page);
      },
    );
    super.initState();
  }

  void _onPhotoViewChanged() {
    if (prepareToNextChapter || prepareToPrevChapter) {
      setState(() {
        prepareToPrevChapter = false;
        prepareToNextChapter = false;
      });
      context.readerScaffold.setFloatingButton(0);
    }
    final zoomed = (photoViewController.scale ?? 1.0) != 1.0;
    if (zoomed != isZoomedIn) {
      setState(() {
        isZoomedIn = zoomed;
      });
    }
  }

  @override
  void dispose() {
    itemPositionsListener.itemPositions.removeListener(onPositionChanged);
    photoViewController.removeIgnorableListener(_onPhotoViewChanged);
    scaleStateController.dispose();
    super.dispose();
  }

  void onPositionChanged() {
    final positions = itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) {
      return;
    }
    // 尾部占位要先按实测的末图长度算好，否则末图顶端顶不到屏幕顶部。
    _syncTailExtent(positions);
    // 当前页 = 视口**水位线**（顶部）上的那张图。
    //
    // 旧实现取 `.first.index`，虽然方向对，但 itemPositions 的顺序来自包内
    // Set<Element> 注册顺序、没有排序保证，会跳；这里显式按 leadingEdge 取最小。
    final top = readingTopImageIndex(positions, maxIndex: reader.maxPage);
    if (top <= 0) {
      return;
    }
    final page = top.clamp(1, reader.maxPage);
    if (page != reader.page) {
      reader.setPage(page);
      context.readerScaffold.update();
    }
    cacheImages(page);
  }

  /// 维持尾部占位长度 = `视口长度 - 末图长度`（末图比视口高时为 0）。
  ///
  /// 末图比视口矮时，若不额外留白，滚到底它的顶端也到不了屏幕顶部，
  /// "当前页"就永远停在倒数第二张 → 进度与"读完"判定都偏。
  /// 末图长度只能等它进入视口后从 [ItemPosition] 实测（懒加载，布局前未知）。
  void _syncTailExtent(Iterable<ItemPosition> positions) {
    final viewport = _viewportExtent;
    if (viewport <= 0 || reader.maxPage < 1) return;
    double? lastExtent;
    for (final position in positions) {
      if (position.index == reader.maxPage) {
        lastExtent =
            (position.itemTrailingEdge - position.itemLeadingEdge) * viewport;
        break;
      }
    }
    if (lastExtent == null || lastExtent <= 0) return;
    final desired =
        (viewport - lastExtent + _tailEpsilon).clamp(0.0, viewport.toDouble());
    if ((desired - _tailExtent).abs() > 0.5) {
      setState(() => _tailExtent = desired);
    }
  }

  void smoothTo(double offset) {
    if (HardwareKeyboard.instance.isShiftPressed) {
      return;
    }
    double k = 1;
    final customSpeed = ComicReaderSettings.getDouble('readerScrollSpeed');
    if (customSpeed != 0) {
      k *= customSpeed;
    }
    scrollOffsetController.animateScroll(
      offset: offset * k,
      duration: const Duration(milliseconds: 160),
      curve: Curves.linear,
    );
  }

  void onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      if (!_isMouseScrolling) {
        setState(() {
          _isMouseScrolling = true;
        });
      }
      if (isCTRLPressed) {
        return;
      }
      smoothTo(event.scrollDelta.dy);
    }
  }

  void cacheImages(int current) {
    for (int i = current + 1; i <= current + preCacheCount; i++) {
      if (i <= reader.maxPage && !cached[i]) {
        _preDownloadImage(i, context);
        cached[i] = true;
      }
    }
  }

  void onScroll(double offset, double minExtent, double maxExtent) {
    _scrollOffset = offset;
    if (prepareToPrevChapter) {
      jumpToNextChapter = false;
      jumpToPrevChapter = offset < minExtent - _kChangeChapterOffset;
    } else if (prepareToNextChapter) {
      jumpToNextChapter = offset > maxExtent + _kChangeChapterOffset;
      jumpToPrevChapter = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget widget = ScrollablePositionedList.builder(
      initialScrollIndex: reader.page,
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      scrollOffsetController: scrollOffsetController,
      itemCount: reader.maxPage + 2,
      addSemanticIndexes: false,
      scrollDirection: reader.mode == ComicReaderMode.continuousTopToBottom
          ? Axis.vertical
          : Axis.horizontal,
      reverse: reader.mode == ComicReaderMode.continuousRightToLeft,
      physics: isCTRLPressed || _isMouseScrolling || disableScroll
          ? const NeverScrollableScrollPhysics()
          : isZoomedIn
              ? const ClampingScrollPhysics()
              : const BouncingScrollPhysics(),
      itemBuilder: (context, index) {
        if (index == 0) {
          return const SizedBox();
        }
        if (index == reader.maxPage + 1) {
          // 尾部占位：让末图顶端能越过视口顶部（水位线），见 [_syncTailExtent]。
          return reader.mode == ComicReaderMode.continuousTopToBottom
              ? SizedBox(height: _tailExtent)
              : SizedBox(width: _tailExtent);
        }
        double? width, height;
        if (reader.mode == ComicReaderMode.continuousLeftToRight ||
            reader.mode == ComicReaderMode.continuousRightToLeft) {
          height = double.infinity;
        } else {
          width = double.infinity;
        }

        ImageProvider image = _createImageProvider(index, context);

        // 相邻图片之间会因为亚像素对齐出现细小的背景色缝隙，
        // 让图片向四周多绘制一个物理像素，与相邻项重叠以盖住缝隙。
        final paintExtend = 1.0 / MediaQuery.devicePixelRatioOf(context);

        return ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: ComicImage(
            filterQuality: FilterQuality.medium,
            image: image,
            width: width,
            height: height,
            fit: BoxFit.fill,
            paintExtend: paintExtend,
            onInit: (state) => imageStates.add(state),
            onDispose: (state) => imageStates.remove(state),
            onRetryTap: () =>
                context.readerScaffold._gestureDetectorState?.ignoreNextTap(),
          ),
        );
      },
    );

    widget = Stack(
      children: [
        Positioned.fill(child: buildBackground(context)),
        Positioned.fill(child: widget),
      ],
    );

    widget = Listener(
      onPointerDown: (event) {
        fingers++;
        if (fingers > 1 && !disableScroll) {
          setState(() {
            disableScroll = true;
          });
        }
        if (_isMouseScrolling) {
          setState(() {
            _isMouseScrolling = false;
          });
        }
      },
      onPointerUp: (event) {
        fingers--;
        if (fingers <= 1 && disableScroll) {
          setState(() {
            disableScroll = false;
          });
        }
        if (fingers == 0) {
          if (jumpToPrevChapter) {
            context.readerScaffold.setFloatingButton(0);
            reader.toPrevChapter(toLastPage: true);
          } else if (jumpToNextChapter) {
            context.readerScaffold.setFloatingButton(0);
            reader.toNextChapter();
          }
        }
      },
      onPointerCancel: (event) {
        fingers--;
        if (fingers <= 1 && disableScroll) {
          setState(() {
            disableScroll = false;
          });
        }
      },
      onPointerPanZoomUpdate: (event) {
        if (event.scale == 1.0) {
          smoothTo(0 - event.panDelta.dy);
        }
      },
      onPointerMove: (event) {
        Offset value = event.delta;
        if (photoViewController.scale == 1 || fingers != 1) {
          return;
        }
        var offset = Offset(value.dx, value.dy);
        if (isLongPressing) {
          offset += value;
        }
        photoViewController.updateMultiple(
          position: photoViewController.position + offset,
        );
      },
      onPointerSignal: onPointerSignal,
      child: widget,
    );

    widget = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          delayedSetIsScrolling(true);
        } else if (notification is ScrollEndNotification) {
          delayedSetIsScrolling(false);
        }

        var scale = photoViewController.scale ?? 1.0;

        if (notification is ScrollUpdateNotification &&
            (scale - 1).abs() < 0.05) {
          final metrics = notification.metrics;
          onScroll(
            metrics.pixels,
            metrics.minScrollExtent,
            metrics.maxScrollExtent,
          );
          if (_scrollOffset <= metrics.minScrollExtent &&
              !reader.isFirstChapterOfGroup) {
            if (!prepareToPrevChapter) {
              jumpToPrevChapter = false;
              jumpToNextChapter = false;
              context.readerScaffold.setFloatingButton(-1);
              setState(() {
                prepareToPrevChapter = true;
              });
            }
          } else if (_scrollOffset >= metrics.maxScrollExtent &&
              !reader.isLastChapterOfGroup) {
            if (!prepareToNextChapter) {
              jumpToPrevChapter = false;
              jumpToNextChapter = false;
              context.readerScaffold.setFloatingButton(1);
              setState(() {
                prepareToNextChapter = true;
              });
            }
          } else {
            context.readerScaffold.setFloatingButton(0);
            if (prepareToPrevChapter || prepareToNextChapter) {
              jumpToPrevChapter = false;
              jumpToNextChapter = false;
              setState(() {
                prepareToPrevChapter = false;
                prepareToNextChapter = false;
              });
            }
          }
        }

        return true;
      },
      child: widget,
    );
    var width = reader.size.width;
    var height = reader.size.height;
    if (ComicReaderSettings.getBool('limitImageWidth') &&
        width / height > 0.7 &&
        reader.mode == ComicReaderMode.continuousTopToBottom) {
      width = height * 0.7;
    }

    return PhotoView.customChild(
      backgroundDecoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
      ),
      childSize: Size(width, height),
      minScale: 1.0,
      maxScale: 2.5,
      strictScale: true,
      controller: photoViewController,
      scaleStateController: scaleStateController,
      child: SizedBox(width: width, height: height, child: widget),
    );
  }

  Widget buildBackground(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: MediaQuery.of(context).padding.top + 16),
        if (prepareToPrevChapter) const _ChapterSwitchHint(isPrev: true),
        const Spacer(),
        if (prepareToNextChapter) const _ChapterSwitchHint(isPrev: false),
        const SizedBox(height: 36),
      ],
    );
  }

  @override
  Future<void> animateToPage(int page) {
    return itemScrollController.scrollTo(
      index: page,
      duration: const Duration(milliseconds: 200),
      curve: Curves.ease,
    );
  }

  @override
  void handleDoubleTap(Offset location) {
    scaleStateController.scaleState =
        scaleStateController.scaleState == PhotoViewScaleState.zoomedIn
            ? PhotoViewScaleState.zoomedOut
            : PhotoViewScaleState.zoomedIn;
  }

  @override
  void handleLongPressDown(Offset location) {
    if (!ComicReaderSettings.getBool('enableLongPressToZoom') ||
        delayedIsScrolling) {
      return;
    }
    _initialScale = photoViewController.scale ?? 1.0;
    double target = _initialScale * 1.75;
    var size = reader.size;
    Offset zoomPosition;
    if (ComicReaderSettings.getString('longPressZoomPosition') != 'center') {
      zoomPosition = Offset(
        size.width / 2 - location.dx,
        size.height / 2 - location.dy,
      );
    } else {
      zoomPosition = Offset(0, 0);
    }
    photoViewController.updateMultiple(scale: target, position: zoomPosition);
    isLongPressing = true;
  }

  @override
  void handleLongPressUp(Offset location) {
    if (!ComicReaderSettings.getBool('enableLongPressToZoom')) {
      return;
    }
    photoViewController.updateMultiple(
        scale: _initialScale, position: Offset.zero);
    isLongPressing = false;
  }

  @override
  void toPage(int page) {
    itemScrollController.jumpTo(index: page);
  }

  @override
  void handleKeyEvent(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight) {
      setState(() {
        if (event is KeyDownEvent) {
          isCTRLPressed = true;
        } else if (event is KeyUpEvent) {
          isCTRLPressed = false;
        }
      });
    }
    if (event is KeyUpEvent) {
      return;
    }
    bool? forward;
    if (reader.mode == ComicReaderMode.continuousLeftToRight &&
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      forward = true;
    } else if (reader.mode == ComicReaderMode.continuousRightToLeft &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      forward = true;
    } else if (reader.mode == ComicReaderMode.continuousTopToBottom &&
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      forward = true;
    } else if (reader.mode == ComicReaderMode.continuousTopToBottom &&
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      forward = false;
    } else if (reader.mode == ComicReaderMode.continuousLeftToRight &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      forward = false;
    } else if (reader.mode == ComicReaderMode.continuousRightToLeft &&
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      forward = false;
    }
    if (forward == true) {
      scrollOffsetController.animateScroll(
        offset: MediaQuery.of(context).size.height * 0.25,
        duration: const Duration(milliseconds: 200),
        curve: Curves.ease,
      );
    } else if (forward == false) {
      scrollOffsetController.animateScroll(
        offset: -MediaQuery.of(context).size.height * 0.25,
        duration: const Duration(milliseconds: 200),
        curve: Curves.ease,
      );
    }
  }

  @override
  bool handleOnTap(Offset location) {
    if (delayedIsScrolling) {
      return true;
    }
    return false;
  }

  @override
  String? getImageKeyByOffset(Offset offset) {
    String? imageKey;
    for (var imageState in imageStates) {
      if ((imageState as _ComicImageState).containsPoint(offset)) {
        imageKey =
            (imageState.widget.image as ComicReaderImageProvider).imageKey;
      }
    }
    return imageKey;
  }
}

ImageProvider _createImageProviderFromKey(
  String imageKey,
  BuildContext context,
  int page,
) {
  var reader = context.reader;
  return ComicReaderImageProvider(
    imageKey,
    reader.sourceKey,
    reader.cid,
    reader.eid,
    page,
    // 连续模式需要降采样提升性能
    enableResize: reader.mode.isContinuous,
  );
}

ImageProvider _createImageProvider(int page, BuildContext context) {
  var reader = context.reader;
  var imageKey = reader.images![page - 1];
  return _createImageProviderFromKey(imageKey, context, page);
}

/// 用 Flutter 的 [precacheImage] 预解码缓存图片。
void _precacheImage(int page, BuildContext context) {
  if (page <= 0 || page > context.reader.images!.length) {
    return;
  }
  precacheImage(_createImageProvider(page, context), context);
}

/// 预下载图片到本地缓存。
void _preDownloadImage(int page, BuildContext context) {
  if (page <= 0 || page > context.reader.images!.length) {
    return;
  }
  var reader = context.reader;
  var imageKey = reader.images![page - 1];
  if (imageKey.startsWith('file://')) {
    return;
  }
  ImageDownloader.loadComicImage(
    imageKey,
    sourceKey: reader.sourceKey,
    cid: reader.cid,
    eid: reader.eid,
  );
}

/// 滑动换章时的简单提示。
class _ChapterSwitchHint extends StatelessWidget {
  const _ChapterSwitchHint({required this.isPrev});

  final bool isPrev;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final msg = isPrev ? '继续下滑进入上一章' : '继续上滑进入下一章';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPrev ? Icons.arrow_downward : Icons.arrow_upward,
            color: colorScheme.onSurface,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(msg),
        ],
      ),
    );
  }
}
