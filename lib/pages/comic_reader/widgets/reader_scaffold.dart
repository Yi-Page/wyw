// ignore_for_file: use_build_context_synchronously

part of 'comic_reader.dart';

class _ComicReaderScaffold extends StatefulWidget {
  const _ComicReaderScaffold({required this.child});

  final Widget child;

  @override
  State<_ComicReaderScaffold> createState() => _ComicReaderScaffoldState();
}

class _ComicReaderScaffoldState extends State<_ComicReaderScaffold> {
  bool _isOpen = false;

  static const kTopBarHeight = 56.0;

  static const kBottomBarHeight = 105.0;

  bool get isOpen => _isOpen;

  bool get isReversed =>
      context.reader.mode == ComicReaderMode.galleryRightToLeft ||
      context.reader.mode == ComicReaderMode.continuousRightToLeft;

  int showFloatingButtonValue = 0;

  var lastValue = 0;

  _ComicReaderGestureDetectorState? _gestureDetectorState;

  void setFloatingButton(int value) {
    lastValue = showFloatingButtonValue;
    if (value == 0) {
      if (showFloatingButtonValue != 0) {
        showFloatingButtonValue = 0;
        update();
      }
    }
    if (value == 1 && showFloatingButtonValue == 0) {
      showFloatingButtonValue = 1;
      update();
    } else if (value == -1 && showFloatingButtonValue == 0) {
      showFloatingButtonValue = -1;
      update();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void openOrClose() {
    if (!_isOpen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      if (!ComicReaderSettings.getBool('showSystemStatusBar')) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
    setState(() {
      _isOpen = !_isOpen;
    });
  }

  bool? rotation;

  void update() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: AbsorbPointer(
            absorbing: context.reader.isPageAnimating,
            child: widget.child,
          ),
        ),
        if (ComicReaderSettings.getBool('showPageNumberInReader'))
          buildPageInfoText(),
        if (ComicReaderSettings.getBool('enableClockAndBatteryInfoInReader'))
          buildStatusInfo(),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 180),
          right: 16,
          bottom: showFloatingButtonValue == 0 ? -58 : 36,
          child: buildEpChangeButton(),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 180),
          top: _isOpen
              ? 0
              : -(kTopBarHeight + MediaQuery.of(context).padding.top),
          left: 0,
          right: 0,
          height: kTopBarHeight + MediaQuery.of(context).padding.top,
          child: buildTop(),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 180),
          bottom: _isOpen
              ? 0
              : -(kBottomBarHeight + MediaQuery.of(context).padding.bottom),
          left: 0,
          right: 0,
          child: buildBottom(),
        ),
      ],
    );
  }

  Widget buildTop() {
    final colorScheme = Theme.of(context).colorScheme;
    final epName = context.reader.chapters
        .elementAtOrNull(context.reader.chapter - 1)
        ?.title;

    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: MediaQuery.of(context).padding.left,
          right: MediaQuery.of(context).padding.right,
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            const BackButton(),
            const SizedBox(width: 8),
            Expanded(
              child: epName == null
                  ? Text(
                      context.reader.comicTitle,
                      style: const TextStyle(fontSize: 18),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          context.reader.comicTitle,
                          style: const TextStyle(fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          epName,
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: '设置',
              child: IconButton(
                icon: const Icon(Icons.settings),
                onPressed: openSetting,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget buildBottom() {
    final reader = context.reader;
    // 显示规范单位（章内图片序号）：一屏两张时是 2/4/6，不是屏号 1/2/3
    final displayImage =
        reader.frontierImage > 0 ? reader.frontierImage : 1;
    var text = 'E${reader.chapter} : P$displayImage';
    if (reader.chapters.isEmpty) {
      text = 'P$displayImage';
    }

    final buttons = <Widget>[
      if (isDesktop())
        Tooltip(
          message: '全屏 (F12)',
          child: IconButton(
            icon: const Icon(Icons.fullscreen),
            onPressed: () {
              context.reader.fullscreen();
            },
          ),
        ),
      if (Platform.isAndroid)
        Tooltip(
          message: '屏幕旋转',
          child: IconButton(
            icon: Icon(
              rotation == null
                  ? Icons.screen_rotation
                  : rotation == false
                      ? Icons.screen_lock_portrait
                      : Icons.screen_lock_landscape,
            ),
            onPressed: () {
              if (rotation == null) {
                setState(() {
                  rotation = false;
                });
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.portraitUp,
                  DeviceOrientation.portraitDown,
                ]);
              } else if (rotation == false) {
                setState(() {
                  rotation = true;
                });
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ]);
              } else {
                setState(() {
                  rotation = null;
                });
                SystemChrome.setPreferredOrientations(DeviceOrientation.values);
              }
            },
          ),
        ),
      Tooltip(
        message: '自动翻页',
        child: IconButton(
          icon: context.reader.autoPageTurningTimer != null
              ? const Icon(Icons.timer)
              : const Icon(Icons.timer_sharp),
          onPressed: () {
            context.reader.autoPageTurning();
            update();
          },
        ),
      ),
      if (context.reader.chapters.isNotEmpty)
        Tooltip(
          message: '章节',
          child: IconButton(
            icon: const Icon(Icons.library_books),
            onPressed: openChapterDrawer,
          ),
        ),
      Tooltip(
        message: '保存当前图片',
        child: IconButton(
          icon: const Icon(Icons.download),
          onPressed: saveCurrentImage,
        ),
      ),
    ];

    final colorScheme = Theme.of(context).colorScheme;
    Widget child = SizedBox(
      height: kBottomBarHeight,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: () => !isReversed
                    ? context.reader.chapter > 1
                        ? context.reader.toPrevChapter()
                        : context.reader.toPage(1)
                    : context.reader.chapter < context.reader.maxChapter
                        ? context.reader.toNextChapter()
                        : context.reader.toPage(context.reader.maxPage),
                icon: const Icon(Icons.first_page),
              ),
              Expanded(child: buildSlider()),
              IconButton.filledTonal(
                onPressed: () => !isReversed
                    ? context.reader.chapter < context.reader.maxChapter
                        ? context.reader.toNextChapter()
                        : context.reader.toPage(context.reader.maxPage)
                    : context.reader.chapter > 1
                        ? context.reader.toPrevChapter()
                        : context.reader.toPage(1),
                icon: const Icon(Icons.last_page),
              ),
              const SizedBox(width: 8),
            ],
          ),
          LayoutBuilder(
            builder: (context, constrains) {
              final small = (constrains.maxWidth - buttons.length * 50) < 120;
              return Row(
                children: [
                  if (!small)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Container(
                        height: 24,
                        padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(child: Text(text)),
                      ),
                    ),
                  const Spacer(),
                  for (var button in buttons)
                    if (!small)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: button,
                      )
                    else ...<Widget>[button, const Spacer()],
                  if (!small) const SizedBox(width: 4),
                ],
              );
            },
          ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.92),
        border: isOpen
            ? Border(
                top: BorderSide(
                  color: colorScheme.outlineVariant,
                  width: 0.5,
                ),
              )
            : null,
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Padding(
        padding: EdgeInsets.only(
          left: MediaQuery.of(context).padding.left,
          right: MediaQuery.of(context).padding.right,
        ),
        child: child,
      ),
    );
  }

  var sliderFocus = FocusNode();

  Widget buildSlider() {
    final reader = context.reader;
    // 进度条也走规范单位（图片序号）：一屏两张时按张拖动，与页码显示一致
    final total = reader.imageCount > 0 ? reader.imageCount : 1;
    final displayImage = reader.frontierImage.clamp(1, total);
    return Slider(
      value: displayImage.toDouble(),
      min: 1,
      max: total.clamp(displayImage, 1 << 16).toDouble(),
      divisions: (total - 1).clamp(2, 1 << 16),
      onChanged: (i) {
        // 进度条拖动期间高频触发：走无动画跳页，避免动画计数堆积导致
        // AbsorbPointer 吞手势（表现为跳转后卡住、无法滚动）。
        context.reader.jumpToImage(i.toInt());
      },
    );
  }

  Widget buildPageInfoText() {
    final reader = context.reader;
    var epName = reader.chapters.elementAtOrNull(reader.chapter - 1)?.title ??
        'E${reader.chapter}';
    if (epName.length > 8) {
      epName = '${epName.substring(0, 8)}...';
    }
    final pageText =
        '${reader.frontierImage > 0 ? reader.frontierImage : 1}/${reader.imageCount}';
    final text = reader.chapters.isNotEmpty ? '$epName : $pageText' : pageText;

    return Positioned(
      bottom: 13,
      left: 25,
      child: Stack(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.4
                ..color = Theme.of(context).colorScheme.onInverseSurface,
            ),
          ),
          Text(text),
        ],
      ),
    );
  }

  Widget buildStatusInfo() {
    return Positioned(
      bottom: 13,
      right: 25,
      child: Row(
        children: [
          const _ClockWidget(),
          const SizedBox(width: 10),
          const _BatteryWidget(),
        ],
      ),
    );
  }

  void openChapterDrawer() {
    _gestureDetectorState?.ignoreNextTap();
    final reader = context.reader;
    WywDialog.showBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      constraints: const BoxConstraints(maxWidth: 500),
      builder: (context) {
        return _ChaptersView(reader);
      },
    );
  }

  /// 底栏「保存当前图片」入口。
  ///
  /// 单图/连续模式直接存；画廊一屏多张时弹浮层让用户点选或"拼接本屏"。
  Future<void> saveCurrentImage() async {
    final indices = await selectImageIndices();
    if (indices == null || indices.isEmpty) return;
    await _saveIndices(indices);
  }

  /// 右键/次要点击菜单的保存入口：先按点击位置命中，命中不到再走统一选择流程。
  Future<void> saveImageAt(Offset location) async {
    final reader = context.reader;
    final images = reader.images;
    final viewController = reader._imageViewController;
    if (images == null || images.isEmpty || viewController == null) return;
    final key = viewController.getImageKeyByOffset(location);
    final index = key == null ? -1 : images.indexOf(key);
    if (index >= 0) {
      await _saveIndices([index]);
      return;
    }
    // 点在图片盒子之外：交给统一流程（多图一屏会弹选择/拼接浮层）
    await saveCurrentImage();
  }

  void openSetting() {
    _gestureDetectorState?.ignoreNextTap();
    final reader = context.reader;
    showComicReaderSettingsSheet(
      context: context,
      onChanged: (key) {
        if (key == 'readerMode') {
          reader.mode = ComicReaderMode.fromKey(
            ComicReaderSettings.getString('readerMode'),
          );
        }
        if (key == 'enableTurnPageByVolumeKey') {
          if (ComicReaderSettings.getBool('enableTurnPageByVolumeKey')) {
            reader.handleVolumeEvent();
          } else {
            reader.stopVolumeEvent();
          }
        }
        reader.update();
      },
    );
  }

  Widget buildEpChangeButton() {
    final reader = context.reader;
    final extraWidth = MediaQuery.of(context).padding.left +
        MediaQuery.of(context).padding.right;
    if (reader.chapters.isEmpty) return const SizedBox();
    switch (showFloatingButtonValue) {
      case 0:
        return Container(
          width: 58 + extraWidth,
          height: 58,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            lastValue == 1
                ? Icons.arrow_forward_ios
                : Icons.arrow_back_ios_outlined,
            size: 24,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        );
      case -1:
      case 1:
        return SizedBox(
          width: 58 + extraWidth,
          height: 58,
          child: Material(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
            elevation: 2,
            child: InkWell(
              onTap: () {
                if (showFloatingButtonValue == 1) {
                  context.reader.toNextChapter();
                } else if (showFloatingButtonValue == -1) {
                  context.reader.toPrevChapter();
                }
                setFloatingButton(0);
              },
              borderRadius: BorderRadius.circular(16),
              child: Center(
                child: Icon(
                  _getArrowIcon(isReversed, showFloatingButtonValue),
                  size: 24,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
        );
      default:
        return const SizedBox();
    }
  }

  IconData _getArrowIcon(bool reversed, int value) {
    if (reversed) {
      return value == 1
          ? Icons.arrow_back_ios_outlined
          : Icons.arrow_forward_ios;
    } else {
      return value == 1
          ? Icons.arrow_forward_ios
          : Icons.arrow_back_ios_outlined;
    }
  }

  /// 当前屏要保存的图片索引列表（1 个 = 单图；多个 = 拼接本屏）。
  ///
  ///   - 连续模式：1 项 = 1 张图，`page` 即图片序号（= 阅读前沿），直接保存；
  ///   - 画廊单图一屏：直接保存；
  ///   - 画廊多图一屏：弹浮层让用户点选具体某张，或选择"拼接本屏"。
  Future<List<int>?> selectImageIndices() async {
    final reader = context.reader;
    final images = reader.images;
    if (images == null || images.isEmpty) return null;
    final imageViewController = reader._imageViewController;

    if (imageViewController is _ContinuousModeState) {
      return [(reader.page - 1).clamp(0, images.length - 1)];
    }
    if (imageViewController is! _GalleryModeState) return null;

    final range = imageViewController.getCurrentPageImageRange();
    if (range == null) return null;
    final (start, end) = range;
    final count = (end - start).clamp(0, images.length - start);
    if (count <= 0) return null;
    if (count == 1) return [start];
    return _showSelectImagesOverlay(start: start, count: count);
  }

  /// 保存一组图片：单张直存，多张按屏幕排布拼成一张。
  Future<void> _saveIndices(List<int> indices) async {
    final reader = context.reader;
    final images = reader.images;
    if (images == null || images.isEmpty || indices.isEmpty) return;

    final valid = [
      for (final index in indices)
        if (index >= 0 && index < images.length) index,
    ];
    if (valid.isEmpty) return;

    final parts = <Uint8List>[];
    for (final index in valid) {
      final bytes = await _loadImageBytes(reader, images[index]);
      if (bytes == null) {
        if (!context.mounted) return;
        WywDialog.showToast(message: '图片尚未加载完成', context: context);
        return;
      }
      parts.add(bytes);
    }

    Uint8List data;
    String filename;
    if (parts.length == 1) {
      data = parts.first;
      filename =
          '${reader.comicTitle}_EP${reader.chapter}_P${valid.first + 1}${_detectFileType(data)}';
    } else {
      final stitched = stitchImages(
        parts,
        vertical: reader.mode == ComicReaderMode.galleryTopToBottom,
        reverseOrder: reader.mode == ComicReaderMode.galleryRightToLeft,
      );
      if (stitched == null) {
        if (!context.mounted) return;
        WywDialog.showToast(message: '拼接失败：图片解码出错', context: context);
        return;
      }
      data = stitched;
      filename = '${reader.comicTitle}_EP${reader.chapter}'
          '_P${valid.first + 1}-${valid.last + 1}${_detectFileType(data)}';
    }
    if (!context.mounted) return;
    await saveReaderImage(data, filename, context);
  }

  /// 读取图片字节：`file://` 直读，否则走图片缓存。
  Future<Uint8List?> _loadImageBytes(
    _ComicReaderState reader,
    String imageKey,
  ) async {
    if (imageKey.startsWith('file://')) {
      final file = File(imageKey.substring(7));
      if (!await file.exists()) return null;
      return file.readAsBytes();
    }
    final info = await AppImageCacheManager.instance.getFileFromCache(
      '$imageKey@${reader.sourceKey}@${reader.cid}@${reader.eid}',
    );
    if (info == null || !await info.file.exists()) return null;
    return info.file.readAsBytes();
  }

  /// 画廊多图一屏：浮层选择要保存的图（点图直接选、或点按钮、或拼接本屏）。
  Future<List<int>?> _showSelectImagesOverlay({
    required int start,
    required int count,
  }) {
    if (_isOpen) {
      openOrClose();
    }

    final completer = Completer<List<int>?>();
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    var removed = false;

    void complete(List<int>? value) {
      if (!completer.isCompleted) completer.complete(value);
      if (!removed && entry.mounted) {
        removed = true;
        entry.remove();
      }
    }

    entry = OverlayEntry(
      builder: (overlayContext) {
        return Positioned.fill(
          child: _SelectImageOverlayContent(
            count: count,
            startIndex: start,
            onTapImage: (offset) {
              final reader = context.reader;
              final images = reader.images;
              final key =
                  reader._imageViewController?.getImageKeyByOffset(offset);
              final index =
                  (images == null || key == null) ? -1 : images.indexOf(key);
              if (index < start || index >= start + count) {
                // 点到本屏图片之外：保留浮层让用户重试
                WywDialog.showToast(
                  message: '请点击本屏图片，或选择下方按钮',
                  context: context,
                );
                return;
              }
              complete([index]);
            },
            onPick: (index) => complete([index]),
            onStitch: () =>
                complete([for (var i = 0; i < count; i++) start + i]),
            onDismiss: () => complete(null),
          ),
        );
      },
    );
    overlay.insert(entry);

    return completer.future;
  }

  String _detectFileType(Uint8List data) {
    if (data.length < 4) return '.png';
    if (data[0] == 0xFF && data[1] == 0xD8) return '.jpg';
    if (data[0] == 0x89 && data[1] == 0x50) return '.png';
    if (data[0] == 0x47 && data[1] == 0x49) return '.gif';
    if (data[0] == 0x52 && data[1] == 0x49) return '.webp';
    return '.png';
  }
}

/// 保存阅读器图片字节。
///
/// 桌面端写系统「下载」目录（`saver_gallery` 无桌面实现），
/// 移动端走系统相册/图库。
Future<void> saveReaderImage(
  Uint8List data,
  String filename,
  BuildContext context,
) async {
  try {
    if (isDesktop()) {
      final dir = await getDownloadsDirectory();
      if (!context.mounted) return;
      if (dir == null) {
        WywDialog.showToast(message: '保存失败：未找到下载目录', context: context);
        return;
      }
      final file = File(p.join(dir.path, filename));
      await file.writeAsBytes(data);
      if (!context.mounted) return;
      WywDialog.showToast(
        message: '已保存到 ${file.path}',
        context: context,
        duration: const Duration(seconds: 2),
      );
    } else {
      final saveResult = await SaverGallery.saveImage(
        data,
        fileName: filename,
        skipIfExists: false,
      );
      if (!context.mounted) return;
      if (!saveResult.isSuccess) {
        WywDialog.showToast(
          message: '保存失败：${saveResult.errorMessage}',
          context: context,
        );
        logger.e('保存失败：${saveResult.errorMessage}');
      } else {
        WywDialog.showToast(
          message: '已保存',
          context: context,
          duration: const Duration(seconds: 1),
        );
      }
    }
  } catch (e) {
    if (!context.mounted) return;
    WywDialog.showToast(message: '保存失败：$e', context: context);
  }
}

class _BatteryWidget extends StatefulWidget {
  const _BatteryWidget();

  @override
  _BatteryWidgetState createState() => _BatteryWidgetState();
}

class _BatteryWidgetState extends State<_BatteryWidget> {
  late Battery _battery;
  late int _batteryLevel = 100;
  Timer? _timer;
  bool _hasBattery = false;
  BatteryState state = BatteryState.unknown;

  @override
  void initState() {
    super.initState();
    _battery = Battery();
    _checkBatteryAvailability();
  }

  void _checkBatteryAvailability() async {
    try {
      _batteryLevel = await _battery.batteryLevel;
      state = await _battery.batteryState;
      if (_batteryLevel > 0 && state != BatteryState.unknown) {
        if (!mounted) return;
        setState(() {
          _hasBattery = true;
        });
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          _battery.batteryLevel.then((level) {
            if (_batteryLevel != level) {
              setState(() {
                _batteryLevel = level;
              });
            }
          });
        });
      }
    } catch (_) {
      // 静默可接受：平台不支持电量查询属预期分支
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasBattery) {
      return const SizedBox.shrink();
    }
    return _batteryInfo(_batteryLevel);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _batteryInfo(int batteryLevel) {
    IconData batteryIcon;
    Color batteryColor = Theme.of(context).colorScheme.onSurface;

    if (state == BatteryState.charging) {
      batteryIcon = Icons.battery_charging_full;
    } else if (batteryLevel >= 96) {
      batteryIcon = Icons.battery_full_sharp;
    } else if (batteryLevel >= 84) {
      batteryIcon = Icons.battery_6_bar_sharp;
    } else if (batteryLevel >= 72) {
      batteryIcon = Icons.battery_5_bar_sharp;
    } else if (batteryLevel >= 60) {
      batteryIcon = Icons.battery_4_bar_sharp;
    } else if (batteryLevel >= 48) {
      batteryIcon = Icons.battery_3_bar_sharp;
    } else if (batteryLevel >= 36) {
      batteryIcon = Icons.battery_2_bar_sharp;
    } else if (batteryLevel >= 24) {
      batteryIcon = Icons.battery_1_bar_sharp;
    } else if (batteryLevel >= 12) {
      batteryIcon = Icons.battery_0_bar_sharp;
    } else {
      batteryIcon = Icons.battery_alert_sharp;
      batteryColor = Theme.of(context).colorScheme.error;
    }

    return Row(
      children: [
        Icon(
          batteryIcon,
          size: 16,
          color: batteryColor,
          shadows: List.generate(9, (index) {
            if (index == 4) {
              return null;
            }
            double offsetX = (index % 3 - 1) * 0.8;
            double offsetY = ((index / 3).floor() - 1) * 0.8;
            return Shadow(
              color: Theme.of(context).colorScheme.onInverseSurface,
              offset: Offset(offsetX, offsetY),
            );
          }).whereType<Shadow>().toList(),
        ),
        Stack(
          children: [
            Text(
              '$batteryLevel%',
              style: TextStyle(
                fontSize: 14,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.4
                  ..color = Theme.of(context).colorScheme.onInverseSurface,
              ),
            ),
            Text('$batteryLevel%'),
          ],
        ),
      ],
    );
  }
}

class _ClockWidget extends StatefulWidget {
  const _ClockWidget();

  @override
  _ClockWidgetState createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<_ClockWidget> {
  late String _currentTime;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _currentTime = _getCurrentTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final time = _getCurrentTime();
      if (_currentTime != time) {
        setState(() {
          _currentTime = time;
        });
      }
    });
  }

  String _getCurrentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Text(
          _currentTime,
          style: TextStyle(
            fontSize: 14,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..color = Theme.of(context).colorScheme.onInverseSurface,
          ),
        ),
        Text(_currentTime),
      ],
    );
  }
}

/// 画廊"一屏多张"时的保存选择浮层。
///
/// 三种选择方式并存：直接点图（命中即所点）、点具体某张的按钮、或"拼接本屏"。
/// 点在图外只提示不关浮层，避免误触时静默保存了别的图。
class _SelectImageOverlayContent extends StatefulWidget {
  const _SelectImageOverlayContent({
    required this.count,
    required this.startIndex,
    required this.onTapImage,
    required this.onPick,
    required this.onStitch,
    required this.onDismiss,
  });

  /// 本屏图片张数。
  final int count;

  /// 本屏第一张图的 0-based 索引（按钮标签显示全局张号）。
  final int startIndex;

  final void Function(Offset) onTapImage;

  /// 参数为 0-based 全局图片索引。
  final void Function(int) onPick;

  final void Function() onStitch;

  final void Function() onDismiss;

  @override
  State<_SelectImageOverlayContent> createState() =>
      _SelectImageOverlayContentState();
}

class _SelectImageOverlayContentState
    extends State<_SelectImageOverlayContent> {
  @override
  void dispose() {
    // 浮层被外部移除（切页/退出）时视为取消
    widget.onDismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        widget.onTapImage(details.globalPosition);
      },
      child: Container(
        color: MediaChromeColors.scrim.withValues(alpha: 0.2),
        child: Align(
          alignment: const Alignment(0, -0.8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    const Text('点击要保存的图片，或选择：',
                        style: TextStyle(fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (var i = 0; i < widget.count; i++)
                      OutlinedButton(
                        onPressed: () => widget.onPick(widget.startIndex + i),
                        child: Text('第 ${widget.startIndex + i + 1} 张'),
                      ),
                    if (widget.count > 1)
                      FilledButton.tonalIcon(
                        onPressed: widget.onStitch,
                        icon: const Icon(Icons.merge_type, size: 16),
                        label: Text('拼接本屏 ${widget.count} 张'),
                      ),
                    TextButton(
                      onPressed: widget.onDismiss,
                      child: const Text('取消'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
