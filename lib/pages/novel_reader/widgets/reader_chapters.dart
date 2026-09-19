part of 'novel_reader.dart';

/// 滚动模式下已加载的一章。
class _LoadedChapter {
  const _LoadedChapter(this.chapter, this.content);

  final int chapter;
  final String content;
}

/// 滚动模式下单章内容块（正文）。
class _ChapterBlock extends StatelessWidget {
  const _ChapterBlock({
    required this.chapter,
    required this.fontSize,
    required this.lineHeight,
    required this.textColor,
  });

  final _LoadedChapter chapter;
  final double fontSize;
  final double lineHeight;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          chapter.content,
          style: TextStyle(
            fontSize: fontSize,
            height: lineHeight,
            color: textColor,
          ),
        ),
      ],
    );
  }
}

/// 章节抽屉。
class _ChaptersDrawer extends StatefulWidget {
  const _ChaptersDrawer({
    required this.controller,
    required this.onSelect,
  });

  final NovelReaderController controller;
  final void Function(int chapter) onSelect;

  @override
  State<_ChaptersDrawer> createState() => _ChaptersDrawerState();
}

class _ChaptersDrawerState extends State<_ChaptersDrawer> {
  bool desc = false;

  @override
  Widget build(BuildContext context) {
    final chapters = widget.controller.chapters;
    final current = widget.controller.chapter - 1;
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
                      child: Text('目录', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  TextButton.icon(
                    icon: Icon(
                      !desc ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 18,
                    ),
                    label: Text(!desc ? '升序' : '降序'),
                    onPressed: () => setState(() => desc = !desc),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: chapters.length,
                itemBuilder: (context, index) {
                  final realIndex = desc ? chapters.length - 1 - index : index;
                  final chapter = chapters[realIndex];
                  final isActive = current == realIndex;
                  return InkWell(
                    onTap: () => widget.onSelect(realIndex + 1),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          chapter.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                isActive ? FontWeight.bold : FontWeight.normal,
                            color: isActive
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
