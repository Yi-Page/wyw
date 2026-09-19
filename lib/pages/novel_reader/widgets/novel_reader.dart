library;

// ============================================================================
// 阅读器 part 文件组织说明
// ----------------------------------------------------------------------------
// 本库按功能层拆分为多个 part 文件（与 comic_reader 的 part 组织保持一致）：
//   - reader_chapters.dart  章节列表抽屉
//   - reader_scaffold.dart  阅读器外壳 UI（顶栏/底栏/设置等）
// 各 part 与主库的 _NovelReaderState 等私有状态深度耦合，part 可在保持
// 模块分离的同时共享私有内部状态，避免把内部 API 全部公开。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

import '../novel_reader_controller.dart';
import '../models/novel_reader_settings.dart';
import '../models/novel_reader_mode.dart';

part 'reader_chapters.dart';
part 'reader_scaffold.dart';

/// 小说阅读器视图。
///
/// 支持两种阅读方式：
/// - [NovelReaderMode.scroll]：上下滚动，章节间连续（滚动到底自动加载下一章）
/// - [NovelReaderMode.page]：分页翻页，翻到章末自动进入下一章
///
/// 数据/业务状态由 [NovelReaderController] 承载。
class NovelReaderView extends StatefulWidget {
  const NovelReaderView({super.key, required this.controller});

  final NovelReaderController controller;

  @override
  State<NovelReaderView> createState() => _NovelReaderState();
}

class _NovelReaderState extends State<NovelReaderView> {
  late NovelReaderController controller;
  final ScrollController _scrollController = ScrollController();
  bool _barsVisible = true;

  // 滚动模式：连续阅读已加载章节的正文（index 从 1 起）
  final List<_LoadedChapter> _loadedChapters = [];
  bool _loadingMore = false;

  // 分页模式
  final PageController _pageController = PageController();
  List<String> _pages = const [];
  int _currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
    controller = widget.controller;
    _scrollController.addListener(_onScroll);
    _initChapter();
  }

  /// 首次进入：根据当前模式加载内容。
  Future<void> _initChapter() async {
    if (controller.mode == NovelReaderMode.page) {
      await _loadPageChapter(controller.chapter);
    } else {
      await _loadScrollChapter(controller.chapter);
    }
  }

  // ===== 滚动模式 =====

  Future<void> _loadScrollChapter(int chapter) async {
    controller.isLoading = true;
    try {
      final c = await controller.loadContent(chapter);
      if (!mounted) return;
      _loadedChapters
        ..clear()
        ..add(_LoadedChapter(chapter, c));
      controller.content = c;
      controller.setChapterSilently(chapter);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        if (controller.jumpToLastOnLoad) {
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
          controller.handleJumpToLast();
        } else {
          _scrollController.jumpTo(0);
        }
      });
    } catch (e, s) {
      if (!mounted) return;
      WywLogger().e('${LogTag.reader} 滚动模式加载章节失败 chapter=$chapter',
          error: e, stackTrace: s);
      WywDialog.showToast(message: '加载章节失败：$e');
    } finally {
      if (mounted) controller.isLoading = false;
    }
  }

  /// 滚动接近底部时自动加载下一章（连续阅读）。
  Future<void> _maybeLoadNextChapter() async {
    if (!_scrollController.hasClients) return;
    if (controller.isLoading || _loadingMore) return;
    if (controller.loadedUpTo >= controller.maxChapter) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent - pos.pixels < 300) {
      _loadingMore = true;
      final ok = await controller.loadNextChapter();
      _loadingMore = false;
      if (ok && mounted) {
        final c = controller.content;
        if (c != null) {
          setState(() {
            _loadedChapters.add(_LoadedChapter(controller.chapter, c));
          });
        }
      }
    }
  }

  // ===== 分页模式 =====

  Future<void> _loadPageChapter(int chapter) async {
    controller.isLoading = true;
    try {
      final c = await controller.loadContent(chapter);
      if (!mounted) return;
      controller.content = c;
      controller.setChapterSilently(chapter);
      setState(() {
        _pages = _paginateText(c);
        _currentPageIndex = 0;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (controller.jumpToLastOnLoad && _pages.isNotEmpty) {
          _pageController.jumpToPage(_pages.length - 1);
          _currentPageIndex = _pages.length - 1;
          controller.handleJumpToLast();
        } else {
          _pageController.jumpToPage(0);
          _currentPageIndex = 0;
        }
      });
    } catch (e, s) {
      if (!mounted) return;
      WywLogger().e('${LogTag.reader} 分页模式加载章节失败 chapter=$chapter',
          error: e, stackTrace: s);
      WywDialog.showToast(message: '加载章节失败：$e');
    } finally {
      if (mounted) controller.isLoading = false;
    }
  }

  void _onPageChanged(int index) {
    _currentPageIndex = index;
    if (_pages.isEmpty) return;
    final ratio = index / (_pages.length - 1);
    controller.notifyProgressWith(ratio.clamp(0.0, 1.0));
    // 翻到本章最后一页时，进入下一章（连续阅读）
    if (index == _pages.length - 1 &&
        !controller.isLastChapter &&
        !controller.isLoading) {
      _loadPageChapter(controller.chapter + 1);
    }
  }

  // ===== 通用 =====

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    final ratio = _scrollController.offset / max;
    controller.notifyProgressWith(ratio.clamp(0.0, 1.0));
    _maybeLoadNextChapter();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _toChapter(int c) {
    if (controller.toChapter(c)) {
      if (controller.mode == NovelReaderMode.page) {
        _loadPageChapter(controller.chapter);
      } else {
        _loadScrollChapter(controller.chapter);
      }
    }
  }

  void _toggleBars() => setState(() => _barsVisible = !_barsVisible);

  /// 把正文按可视区域分页。字号/行距改变时由重建触发重新计算。
  List<String> _paginateText(String text) {
    if (text.isEmpty) return const [''];
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    const hPad = 20.0;
    const vPadTop = 40.0;
    const vPadBottom = 40.0;
    final usableW = width - hPad * 2;
    final usableH = height - vPadTop - vPadBottom;
    if (usableW <= 0 || usableH <= 0) return [text];

    final style = TextStyle(
      fontSize: controller.fontSize,
      height: controller.lineHeight,
    );
    final pages = <String>[];
    var start = 0;
    while (start < text.length) {
      // 二分查找能填满一页的最大字符数
      var lo = start + 1;
      var hi = text.length;
      while (lo < hi) {
        final mid = (lo + hi + 1) ~/ 2;
        final painter = TextPainter(
          text: TextSpan(text: text.substring(start, mid), style: style),
          textDirection: TextDirection.ltr,
          maxLines: null,
        )..layout(maxWidth: usableW);
        if (painter.height <= usableH) {
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      // lo 即本页能容纳的字符下标（含）
      final end = lo;
      pages.add(text.substring(start, end));
      if (end <= start) break; // 防御：避免死循环
      start = end;
    }
    if (pages.isEmpty) pages.add(text);
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final (bgColor, textColor) = NovelCanvasPalette.resolve(
            NovelReaderSettings.getT<String>('novelBackground'));
        return Scaffold(
          backgroundColor: bgColor,
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleBars,
                  child: _buildBody(textColor),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                top: _barsVisible ? 0 : -80,
                left: 0,
                right: 0,
                child: _buildTopBar(),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                bottom: _barsVisible ? 0 : -80,
                left: 0,
                right: 0,
                child: _buildBottomBar(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(Color textColor) {
    if (controller.mode == NovelReaderMode.page) {
      return _buildPageBody(textColor);
    }
    return _buildScrollBody(textColor);
  }

  // ===== 滚动模式主体 =====

  Widget _buildScrollBody(Color textColor) {
    if (_loadedChapters.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < _loadedChapters.length; i++) ...[
            if (i > 0) const SizedBox(height: 28),
            _ChapterBlock(
              chapter: _loadedChapters[i],
              fontSize: controller.fontSize,
              lineHeight: controller.lineHeight,
              textColor: textColor,
            ),
          ],
          if (controller.loadedUpTo < controller.maxChapter)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('— 全书完 —',
                    style: TextStyle(
                        color: NovelCanvasPalette.inkSecondary, fontSize: 14)),
              ),
            ),
        ],
      ),
    );
  }

  // ===== 分页模式主体 =====

  Widget _buildPageBody(Color textColor) {
    if (controller.isLoading && _pages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pages.isEmpty) {
      return const Center(child: Text('正在加载章节…'));
    }
    return PageView.builder(
      controller: _pageController,
      itemCount: _pages.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Text(
            _pages[index],
            style: TextStyle(
              fontSize: controller.fontSize,
              height: controller.lineHeight,
              color: textColor,
            ),
          ),
        );
      },
    );
  }

  // ===== 顶/底栏 =====

  Widget _buildTopBar() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: Row(
        children: [
          const BackButton(),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  controller.novelTitle,
                  style: const TextStyle(fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  controller.currentChapterTitle,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: _openSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final modeText =
        controller.mode == NovelReaderMode.page && _pages.isNotEmpty
            ? '${_currentPageIndex + 1}/${_pages.length}'
            : '';
    final text = controller.mode == NovelReaderMode.page
        ? '${controller.chapter}/${controller.maxChapter} 章 · $modeText'
        : '第 ${controller.chapter}/${controller.maxChapter} 章';
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      width: double.infinity,
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 8),
          IconButton.filledTonal(
            icon: const Icon(Icons.first_page),
            onPressed: controller.isFirstChapter
                ? null
                : () => _toChapter(controller.chapter - 1),
          ),
          const Spacer(),
          Text(text),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.library_books),
            tooltip: '章节',
            onPressed: _openChapterDrawer,
          ),
          IconButton.filledTonal(
            icon: const Icon(Icons.last_page),
            onPressed: controller.isLastChapter
                ? null
                : () => _toChapter(controller.chapter + 1),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  void _openChapterDrawer() {
    WywDialog.showBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      constraints: const BoxConstraints(maxWidth: 500),
      builder: (context) => _ChaptersDrawer(
        controller: controller,
        onSelect: (c) {
          _toChapter(c);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  void _openSettings() {
    WywDialog.showBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      constraints: const BoxConstraints(maxWidth: 500),
      builder: (context) => _NovelReaderSettingsPanel(
        controller: controller,
      ),
    );
  }
}
