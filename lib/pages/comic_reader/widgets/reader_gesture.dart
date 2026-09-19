// ignore_for_file: use_build_context_synchronously

part of 'comic_reader.dart';

class _ComicReaderGestureDetector extends StatefulWidget {
  const _ComicReaderGestureDetector({required this.child});

  final Widget child;

  @override
  State<_ComicReaderGestureDetector> createState() =>
      _ComicReaderGestureDetectorState();
}

class _ComicReaderGestureDetectorState
    extends State<_ComicReaderGestureDetector> {
  late TapGestureRecognizer _tapGestureRecognizer;

  static const _kDoubleTapMaxTime = Duration(milliseconds: 200);

  static const _kLongPressMinTime = Duration(milliseconds: 250);

  static const _kDoubleTapMaxDistanceSquared = 20.0 * 20.0;

  static const _kTapToTurnPagePercent = 0.3;

  final _dragListeners = <_DragListener>[];

  int fingers = 0;

  late _ComicReaderState reader;

  bool ignoreNextTag = false;

  void ignoreNextTap() {
    ignoreNextTag = true;
  }

  void clearIgnoreNextTap() {
    ignoreNextTag = false;
  }

  @override
  void initState() {
    _tapGestureRecognizer = TapGestureRecognizer()
      ..onTapUp = onTapUp
      ..onSecondaryTapUp = (details) {
        onSecondaryTapUp(details.globalPosition);
      };
    super.initState();
    context.readerScaffold._gestureDetectorState = this;
    reader = context.reader;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.position == Offset.zero) {
          _previousEvent = null;
          return;
        }
        fingers++;
        if (ignoreNextTag) {
          ignoreNextTag = false;
          return;
        }
        _lastTapPointer = event.pointer;
        _lastTapMoveDistance = Offset.zero;
        _tapGestureRecognizer.addPointer(event);
        if (_dragInProgress) {
          for (var dragListener in _dragListeners) {
            dragListener.onStart?.call(event.position);
          }
          _dragInProgress = false;
        }
        Future.delayed(_kLongPressMinTime, () {
          if (_lastTapPointer == event.pointer && fingers == 1) {
            if (_lastTapMoveDistance!.distanceSquared < 20.0 * 20.0) {
              onLongPressedDown(event.position);
              _longPressInProgress = true;
            } else {
              _dragInProgress = true;
              for (var dragListener in _dragListeners) {
                dragListener.onStart?.call(event.position);
                dragListener.onMove?.call(_lastTapMoveDistance!);
              }
            }
          }
        });
      },
      onPointerMove: (event) {
        if (event.pointer == _lastTapPointer) {
          _lastTapMoveDistance = event.delta + _lastTapMoveDistance!;
        }
        if (_dragInProgress) {
          for (var dragListener in _dragListeners) {
            dragListener.onMove?.call(event.delta);
          }
        }
      },
      onPointerUp: (event) {
        fingers--;
        if (_longPressInProgress) {
          onLongPressedUp(event.position);
        }
        if (_dragInProgress) {
          for (var dragListener in _dragListeners) {
            dragListener.onEnd?.call();
          }
          _dragInProgress = false;
        }
        _lastTapPointer = null;
        _lastTapMoveDistance = null;
      },
      onPointerCancel: (event) {
        fingers--;
        if (_longPressInProgress) {
          onLongPressedUp(event.position);
        }
        if (_dragInProgress) {
          for (var dragListener in _dragListeners) {
            dragListener.onEnd?.call();
          }
          _dragInProgress = false;
        }
        _lastTapPointer = null;
        _lastTapMoveDistance = null;
      },
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          onMouseWheel(event.scrollDelta.dy > 0);
        }
      },
      child: widget.child,
    );
  }

  void onMouseWheel(bool forward) {
    if (HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    if (context.reader.mode.key.startsWith('gallery')) {
      if (forward) {
        if (!context.reader.toNextPage() &&
            !context.reader.isLastChapterOfGroup) {
          context.reader.toNextChapter();
        }
      } else {
        if (!context.reader.toPrevPage() &&
            !context.reader.isFirstChapterOfGroup) {
          context.reader.toPrevChapter(toLastPage: true);
        }
      }
    }
  }

  TapUpDetails? _previousEvent;

  int? _lastTapPointer;

  Offset? _lastTapMoveDistance;

  bool _longPressInProgress = false;

  bool _dragInProgress = false;

  bool get _enableDoubleTapToZoom =>
      ComicReaderSettings.getBool('enableDoubleTapToZoom');

  void onTapUp(TapUpDetails event) {
    if (event.globalPosition == Offset.zero &&
        event.localPosition == Offset.zero) {
      _previousEvent = null;
      return;
    }
    if (_longPressInProgress) {
      _longPressInProgress = false;
      return;
    }
    final location = event.globalPosition;
    if (!_enableDoubleTapToZoom) {
      onTap(location);
      return;
    }
    final previousLocation = _previousEvent?.globalPosition;
    if (previousLocation != null) {
      if ((location - previousLocation).distanceSquared <
          _kDoubleTapMaxDistanceSquared) {
        onDoubleTap(location);
        _previousEvent = null;
        return;
      } else {
        onTap(previousLocation);
      }
    }
    _previousEvent = event;
    Future.delayed(_kDoubleTapMaxTime, () {
      if (_previousEvent == event) {
        onTap(location);
        _previousEvent = null;
      }
    });
  }

  void onTap(Offset location) {
    // 图片列表未就绪（如章节加载中）时 _imageViewController 可能为 null，
    // 此时忽略点击，避免崩溃
    if (reader._imageViewController?.handleOnTap(location) == true) {
      return;
    } else if (context.readerScaffold.isOpen) {
      context.readerScaffold.openOrClose();
    } else {
      if (ComicReaderSettings.getBool('enableTapToTurnPages')) {
        bool isLeft = false, isRight = false, isTop = false, isBottom = false;
        final width = MediaQuery.of(context).size.width;
        final height = MediaQuery.of(context).size.height;
        final x = location.dx;
        final y = location.dy;
        if (x < width * _kTapToTurnPagePercent) {
          isLeft = true;
        } else if (x > width * (1 - _kTapToTurnPagePercent)) {
          isRight = true;
        }
        if (y < height * _kTapToTurnPagePercent) {
          isTop = true;
        } else if (y > height * (1 - _kTapToTurnPagePercent)) {
          isBottom = true;
        }
        bool isCenter = false;
        var prev = () => context.reader.toPrevPage();
        var next = () => context.reader.toNextPage();
        if (ComicReaderSettings.getBool('reverseTapToTurnPages')) {
          prev = () => context.reader.toNextPage();
          next = () => context.reader.toPrevPage();
        }
        switch (context.reader.mode) {
          case ComicReaderMode.galleryLeftToRight:
          case ComicReaderMode.continuousLeftToRight:
            if (isLeft) {
              prev();
            } else if (isRight) {
              next();
            } else {
              isCenter = true;
            }
            break;
          case ComicReaderMode.galleryRightToLeft:
          case ComicReaderMode.continuousRightToLeft:
            if (isLeft) {
              next();
            } else if (isRight) {
              prev();
            } else {
              isCenter = true;
            }
            break;
          case ComicReaderMode.galleryTopToBottom:
          case ComicReaderMode.continuousTopToBottom:
            if (isTop) {
              prev();
            } else if (isBottom) {
              next();
            } else {
              isCenter = true;
            }
            break;
        }
        if (!isCenter) {
          return;
        }
      }
      context.readerScaffold.openOrClose();
    }
  }

  void onDoubleTap(Offset location) {
    context.reader._imageViewController?.handleDoubleTap(location);
  }

  void onSecondaryTapUp(Offset location) {
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(value: 'settings', child: Text('设置')),
      const PopupMenuItem(value: 'chapters', child: Text('章节')),
      const PopupMenuItem(value: 'fullscreen', child: Text('全屏')),
      if (!reader.isLoading)
        const PopupMenuItem(value: 'save', child: Text('保存图片')),
      const PopupMenuItem(value: 'exit', child: Text('退出')),
    ];
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        location.dx,
        location.dy,
        location.dx,
        location.dy,
      ),
      items: items,
    ).then((value) {
      if (!context.mounted) return;
      switch (value) {
        case 'settings':
          context.readerScaffold.openSetting();
          break;
        case 'chapters':
          context.readerScaffold.openChapterDrawer();
          break;
        case 'fullscreen':
          context.reader.fullscreen();
          break;
        case 'save':
          saveImage(location);
          break;
        case 'exit':
          Navigator.of(context).pop();
          break;
      }
    });
  }

  void onLongPressedUp(Offset location) {
    context.reader._imageViewController?.handleLongPressUp(location);
  }

  void onLongPressedDown(Offset location) {
    context.reader._imageViewController?.handleLongPressDown(location);
  }

  void addDragListener(_DragListener listener) {
    _dragListeners.add(listener);
  }

  void removeDragListener(_DragListener listener) {
    _dragListeners.remove(listener);
  }

  /// 右键/次要点击菜单的「保存图片」：按点击位置命中该图；
  /// 点在图片之外则交给统一选择流程（多图一屏会给选择/拼接）。
  void saveImage(Offset location) async {
    await context.readerScaffold.saveImageAt(location);
  }

  @override
  void dispose() {
    _tapGestureRecognizer.dispose();
    super.dispose();
  }
}

class _DragListener {
  void Function(Offset point)? onStart;
  void Function(Offset offset)? onMove;
  void Function()? onEnd;

  _DragListener();
}
