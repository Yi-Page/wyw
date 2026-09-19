import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wyw/pages/comic_reader/models/comic_paging.dart';

/// 回归：连续模式"当前页" = 视口顶部（水位线）那张；
/// 末图比视口矮时，必须靠**尾部占位**才能让末图顶端越过水位线、读到末页。
///
/// 旧实现取 `itemPositions.value.first`：方向对，但顺序来自包内
/// `Set<Element>` 注册顺序、无排序保证；且没有尾部占位时末图永远读不到。
void main() {
  const maxPage = 5;
  const viewport = 600.0;
  const normalExtent = 400.0;

  Future<ItemPositionsListener> pumpList(
    WidgetTester tester, {
    required double lastImageExtent,
    required bool withTail,
  }) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final positions = ItemPositionsListener.create();
    // 与阅读器一致：尾部占位 = 视口长度 - 末图长度（末图更高时为 0）
    final tail = withTail
        ? (viewport - lastImageExtent).clamp(0.0, viewport) + 2
        : 0.0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScrollablePositionedList.builder(
          initialScrollIndex: 1,
          itemPositionsListener: positions,
          itemCount: maxPage + 2,
          addSemanticIndexes: false,
          physics: const ClampingScrollPhysics(),
          itemBuilder: (context, index) {
            if (index == 0) return const SizedBox();
            if (index == maxPage + 1) return SizedBox(height: tail);
            return SizedBox(
              height: index == maxPage ? lastImageExtent : normalExtent,
            );
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return positions;
  }

  Future<void> dragToEnd(WidgetTester tester) async {
    await tester.drag(
        find.byType(ScrollablePositionedList), const Offset(0, -6000));
    await tester.pumpAndSettle();
  }

  int topImage(ItemPositionsListener positions) =>
      readingTopImageIndex(positions.itemPositions.value, maxIndex: maxPage);

  testWidgets('末图矮 + 没有尾部占位：读不到末页（旧 bug 的成因）',
      (tester) async {
    final positions = await pumpList(
      tester,
      lastImageExtent: 120,
      withTail: false,
    );
    await dragToEnd(tester);
    // 滚到底了，但末图顶端到不了视口顶部 → 当前页停在 4
    expect(topImage(positions), lessThan(maxPage));
  });

  testWidgets('末图矮 + 有尾部占位：滚到底当前页就是末图', (tester) async {
    final positions = await pumpList(
      tester,
      lastImageExtent: 120,
      withTail: true,
    );
    await dragToEnd(tester);
    expect(topImage(positions), maxPage);
  });

  testWidgets('末图比视口高：不需要尾部占位也能读到末页', (tester) async {
    final positions = await pumpList(
      tester,
      lastImageExtent: 800,
      withTail: false,
    );
    await dragToEnd(tester);
    expect(topImage(positions), maxPage);
  });

  testWidgets('起始位置：顶端是第 1 张', (tester) async {
    final positions = await pumpList(
      tester,
      lastImageExtent: 120,
      withTail: true,
    );
    expect(topImage(positions), 1);
  });
}
