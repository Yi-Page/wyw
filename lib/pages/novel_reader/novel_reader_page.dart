import 'package:flutter/material.dart';

import 'widgets/novel_reader.dart';
import 'novel_reader_controller.dart';
import 'models/novel_reader_types.dart';

/// 小说阅读器路由参数。
class NovelReaderPageRouteArgs {
  const NovelReaderPageRouteArgs({
    required this.novelId,
    required this.novelTitle,
    required this.chapters,
    this.initialChapter = 1,
    this.sourceKey,
    this.onProgressChanged,
  });

  final String novelId;
  final String novelTitle;
  final List<NovelReaderChapter> chapters;
  final int initialChapter;
  final String? sourceKey;
  final void Function(NovelReaderProgress progress)? onProgressChanged;
}

/// 小说阅读器页面入口。
///
/// 页面负责界面：[NovelReaderController] 为路由级 Store 单例（[novelReaderModule] provide），
/// 进入时用路由参数 configure 注入，交给 [NovelReaderView] 渲染。
class NovelReaderPage extends StatefulWidget {
  const NovelReaderPage({
    super.key,
    required this.args,
    required this.controller,
  });

  static const String routePath = '/novel';

  final NovelReaderPageRouteArgs args;

  /// 路由级 Store 单例（由 [novelReaderModule] 在 child 构建上下文解析后传入）。
  final NovelReaderController controller;

  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage> {
  NovelReaderController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.configure(
      novelId: widget.args.novelId,
      novelTitle: widget.args.novelTitle,
      chapters: widget.args.chapters,
      initialChapter: widget.args.initialChapter,
      sourceKey: widget.args.sourceKey,
      onProgressChanged: widget.args.onProgressChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NovelReaderView(controller: _controller),
    );
  }
}
