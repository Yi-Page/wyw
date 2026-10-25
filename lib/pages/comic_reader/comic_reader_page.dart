import 'dart:async';

import 'package:flutter/material.dart';

import 'package:wyw/services/platform/screen_orientation.dart';

import 'widgets/comic_reader.dart';
import 'comic_reader_controller.dart';
import 'models/comic_reader_types.dart';

/// 阅读器路由参数。
class ComicReaderPageRouteArgs {
  const ComicReaderPageRouteArgs({
    required this.comicId,
    required this.comicTitle,
    required this.chapters,
    this.initialChapter = 1,
    this.initialPage = 1,
    this.initialImageIndex = 0,
    this.sourceKey,
    this.onProgressChanged,
    this.autoResume = false,
  });

  final String comicId;

  final String comicTitle;

  final List<ComicReaderChapter> chapters;

  final int initialChapter;

  /// 旧口径的屏号（仅当 [initialImageIndex] 为 0 时使用）。
  final int initialPage;

  /// 续读位置：章内**图片序号**（1-based；0 = 未指定）。优先于 [initialPage]。
  final int initialImageIndex;

  final String? sourceKey;

  final void Function(ComicReaderProgress progress)? onProgressChanged;

  /// 进入时自动定位到历史记录的上次看的章/页（插件入口续读用）。
  final bool autoResume;
}

/// 漫画阅读器页面入口。
///
/// 页面负责界面：[ComicReaderController] 为路由级 Store 单例（[comicReaderModule] provide），
/// 页面进入时用路由参数 [configure] 注入，交给 [ComicReader] 渲染。
class ComicReaderPage extends StatefulWidget {
  const ComicReaderPage({
    super.key,
    required this.args,
    required this.controller,
  });

  static const String routePath = '/reader';

  final ComicReaderPageRouteArgs args;

  /// 路由级 Store 单例（由 [comicReaderModule] 在 child 构建上下文解析后传入）。
  final ComicReaderController controller;

  @override
  State<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends State<ComicReaderPage> {
  ComicReaderController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.configure(
      comicId: widget.args.comicId,
      comicTitle: widget.args.comicTitle,
      chapters: widget.args.chapters,
      initialChapter: widget.args.initialChapter,
      initialPage: widget.args.initialPage,
      initialImageIndex: widget.args.initialImageIndex,
      sourceKey: widget.args.sourceKey,
      onProgressChanged: widget.args.onProgressChanged,
      autoResume: widget.args.autoResume,
    );
    // 阅读器方向：占用方向服务，按设置里的「漫画阅读器默认方向」生效
    // （默认竖屏锁定）；退出时释放，不再把方向锁泄漏给后面的页面。
    unawaited(
      ScreenOrientationService.instance.acquire(
        ScreenOrientationService.ownerReader,
        ScreenOrientationService.readerPolicyFromSettings(),
      ),
    );
  }

  @override
  void dispose() {
    // 强制释放阅读器方向占用：这是此前「退出阅读器后整个 App 都转不动」的根因。
    unawaited(
      ScreenOrientationService.instance.release(
        ScreenOrientationService.ownerReader,
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: ComicReader(controller: _controller),
    );
  }
}
