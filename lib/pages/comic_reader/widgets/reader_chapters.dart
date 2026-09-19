part of 'comic_reader.dart';

/// 章节抽屉视图。
class _ChaptersView extends StatefulWidget {
  const _ChaptersView(this.reader);

  final _ComicReaderState reader;

  @override
  State<_ChaptersView> createState() => _ChaptersViewState();
}

class _ChaptersViewState extends State<_ChaptersView> {
  bool desc = false;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollToCurrentAfterBuild();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 打开时自动滚动到当前章（上次看的章节）。
  void _scrollToCurrentAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToCurrent();
    });
  }

  void _scrollToCurrent() {
    final chapters = widget.reader.chapters;
    final current = widget.reader.chapter - 1;
    if (chapters.isEmpty || !_scrollController.hasClients) return;
    // 行高 = 48（minHeight）+ 上下 padding 16 = 64
    const itemExtent = 64.0;
    final targetIndex = desc ? chapters.length - 1 - current : current;
    final targetOffset = (targetIndex * itemExtent).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(targetOffset);
  }

  @override
  Widget build(BuildContext context) {
    final chapters = widget.reader.chapters;
    final current = widget.reader.chapter - 1;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('章节', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  TextButton.icon(
                    icon: Icon(
                      !desc ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 18,
                    ),
                    label: Text(!desc ? '升序' : '降序'),
                    onPressed: () {
                      setState(() {
                        desc = !desc;
                      });
                      _scrollToCurrentAfterBuild();
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                // 固定行高：与 _scrollToCurrent 的定位计算保持一致
                itemExtent: 64,
                itemCount: chapters.length,
                itemBuilder: (context, index) {
                  final realIndex = desc ? chapters.length - 1 - index : index;
                  final chapter = chapters[realIndex];
                  final isActive = current == realIndex;
                  // 规范单位：图片序号（与阅读模式无关，画廊一屏多张也准）
                  final imageIndex = widget.reader.imageIndexOfChapter(realIndex);
                  final imageCount = widget.reader.imageCountOfChapter(realIndex);
                  final progressText = imageIndex >= 1
                      ? (imageCount > 0
                          ? '看到第 $imageIndex / $imageCount 张'
                          : '看到第 $imageIndex 张')
                      : null;
                  return InkWell(
                    onTap: () {
                      widget.reader.toChapter(realIndex + 1);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: isActive
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 4,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  chapter.title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: isActive
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isActive
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (progressText != null)
                                  Text(
                                    progressText,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          if (isActive)
                            Icon(
                              Icons.play_circle_fill,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
