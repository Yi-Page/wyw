import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wyw/pages/comic_reader/models/comic_paging.dart';
import 'package:wyw/services/storage/history_progress.dart';

/// 漫画进度模型回归：规范单位（图片序号）、屏号换算、阅读前沿、完成水位线。
void main() {
  group('imageRangeOfPage', () {
    test('每屏 1 张时屏号 == 图片序号', () {
      for (var page = 1; page <= 5; page++) {
        expect(
          imageRangeOfPage(
            page: page,
            imagesPerPage: 1,
            singleImageOnFirstPage: false,
            imageCount: 5,
          ),
          (page - 1, page),
        );
      }
    });

    test('每屏 2 张：屏 → 图片区间，末屏夹取', () {
      expect(
        imageRangeOfPage(
            page: 1,
            imagesPerPage: 2,
            singleImageOnFirstPage: false,
            imageCount: 10),
        (0, 2),
      );
      expect(
        imageRangeOfPage(
            page: 3,
            imagesPerPage: 2,
            singleImageOnFirstPage: false,
            imageCount: 10),
        (4, 6),
      );
      // 5 张图、每屏 2 张 → 末屏只有 1 张
      expect(
        imageRangeOfPage(
            page: 3,
            imagesPerPage: 2,
            singleImageOnFirstPage: false,
            imageCount: 5),
        (4, 5),
      );
    });

    test('首屏单图：第 1 屏只放 1 张，其后按每屏张数', () {
      expect(
        imageRangeOfPage(
            page: 1,
            imagesPerPage: 2,
            singleImageOnFirstPage: true,
            imageCount: 9),
        (0, 1),
      );
      expect(
        imageRangeOfPage(
            page: 2,
            imagesPerPage: 2,
            singleImageOnFirstPage: true,
            imageCount: 9),
        (1, 3),
      );
      expect(
        imageRangeOfPage(
            page: 3,
            imagesPerPage: 2,
            singleImageOnFirstPage: true,
            imageCount: 9),
        (3, 5),
      );
    });

    test('图片总数未知（0）时不夹取', () {
      expect(
        imageRangeOfPage(
            page: 2, imagesPerPage: 2, singleImageOnFirstPage: false),
        (2, 4),
      );
    });
  });

  group('pageOfImageIndex 与 imageRangeOfPage 互逆', () {
    test('每屏张数 × 首屏单图 的全组合：屏内每张都回到同一屏', () {
      const imageCount = 11;
      for (final singleFirst in [false, true]) {
        for (final perPage in [1, 2, 3]) {
          for (var page = 1; page <= 7; page++) {
            final (start, end) = imageRangeOfPage(
              page: page,
              imagesPerPage: perPage,
              singleImageOnFirstPage: singleFirst,
              imageCount: imageCount,
            );
            if (end <= start) continue;
            for (var imageIndex = start + 1; imageIndex <= end; imageIndex++) {
              expect(
                pageOfImageIndex(
                  imageIndex: imageIndex,
                  imagesPerPage: perPage,
                  singleImageOnFirstPage: singleFirst,
                  imageCount: imageCount,
                ),
                page,
                reason: 'singleFirst=$singleFirst perPage=$perPage '
                    'imageIndex=$imageIndex',
              );
            }
          }
        }
      }
    });

    test('imageIndexOfPage 返回该屏最后一张（前沿）', () {
      expect(
        imageIndexOfPage(
            page: 2,
            imagesPerPage: 2,
            singleImageOnFirstPage: false,
            imageCount: 10),
        4,
      );
      expect(
        imageIndexOfPage(
            page: 3,
            imagesPerPage: 2,
            singleImageOnFirstPage: false,
            imageCount: 5),
        5,
      );
      expect(
        imageIndexOfPage(
            page: 1,
            imagesPerPage: 2,
            singleImageOnFirstPage: true,
            imageCount: 10),
        1,
      );
    });

    test('越界图片序号夹取到图片总数', () {
      expect(
        pageOfImageIndex(
            imageIndex: 99,
            imagesPerPage: 2,
            singleImageOnFirstPage: false,
            imageCount: 5),
        3,
      );
    });
  });

  group('readingTopImageIndex（视口顶部 = 水位线）', () {
    test('上→下：取顶端那张；末图矮且无尾部占位时停在倒数第二张', () {
      // 滚到底但没有尾部占位：末图(5) leading=0.33 还在下半屏，顶端那张是 4
      const noTail = [
        ItemPosition(index: 4, itemLeadingEdge: -0.33, itemTrailingEdge: 0.33),
        ItemPosition(index: 5, itemLeadingEdge: 0.33, itemTrailingEdge: 1.0),
      ];
      expect(readingTopImageIndex(noTail, maxIndex: 5), 4);
    });

    test('留出尾部占位后：末图顶端越过水位线，当前页就是末图', () {
      const withTail = [
        ItemPosition(index: 5, itemLeadingEdge: -0.05, itemTrailingEdge: 0.95),
      ];
      expect(readingTopImageIndex(withTail, maxIndex: 5), 5);
    });

    test('顶端已滚出屏幕的那张仍算当前页（顶端越过水位线）', () {
      const positions = [
        ItemPosition(index: 3, itemLeadingEdge: -0.6, itemTrailingEdge: 0.4),
        ItemPosition(index: 4, itemLeadingEdge: 0.4, itemTrailingEdge: 1.4),
      ];
      expect(readingTopImageIndex(positions, maxIndex: 5), 3);
    });

    test('右→左（reverse）同样取顶端那张', () {
      const positions = [
        ItemPosition(index: 1, itemLeadingEdge: 0.0, itemTrailingEdge: 1.0),
        ItemPosition(index: 2, itemLeadingEdge: 1.0, itemTrailingEdge: 2.0),
      ];
      expect(readingTopImageIndex(positions, maxIndex: 5), 1);
    });

    test('排除首尾 0 高占位项', () {
      const positions = [
        ItemPosition(index: 0, itemLeadingEdge: 0.0, itemTrailingEdge: 0.0),
        ItemPosition(index: 1, itemLeadingEdge: 0.0, itemTrailingEdge: 1.0),
        ItemPosition(index: 6, itemLeadingEdge: 1.0, itemTrailingEdge: 1.0),
      ];
      expect(readingTopImageIndex(positions, maxIndex: 5), 1);
    });

    test('无有效可见项返回 0', () {
      expect(readingTopImageIndex(const [], maxIndex: 5), 0);
      expect(
        readingTopImageIndex(
          const [
            ItemPosition(index: 0, itemLeadingEdge: 0, itemTrailingEdge: 0),
          ],
          maxIndex: 5,
        ),
        0,
      );
    });
  });

  group('isComicChapterFinished（水位线）', () {
    test('水位线达到图片总数即读完', () {
      expect(
        isComicChapterFinished(const {'imageCount': 10, 'seenUpToImage': 9}),
        isFalse,
      );
      expect(
        isComicChapterFinished(const {'imageCount': 10, 'seenUpToImage': 10}),
        isTrue,
      );
    });

    test('末图比视口矮也能读完（旧口径差 2 张时判不出来）', () {
      // 旧口径：位置只到 8/10，容差（>=9）也不够
      expect(
        isComicChapterFinished(
          const {'imageCount': 10, 'pageIndex': 8, 'maxPage': 10},
        ),
        isFalse,
      );
      // 新口径：滚到底后水位线到 10
      expect(
        isComicChapterFinished(const {'imageCount': 10, 'seenUpToImage': 10}),
        isTrue,
      );
    });

    test('往回翻不回退：位置变小但水位线保持', () {
      // 位置字段不参与判定，只有水位线参与
      expect(
        isComicChapterFinished(const {
          'imageCount': 10,
          'imageIndex': 2,
          'seenUpToImage': 10,
        }),
        isTrue,
      );
    });

    test('旧数据回退到既有容差（不把已读条目打回未完成）', () {
      expect(isComicChapterFinished(const {'pageIndex': 9, 'maxPage': 10}),
          isTrue);
      expect(isComicChapterFinished(const {'pageIndex': 8, 'maxPage': 10}),
          isFalse);
    });

    test('图片总数未知不算读完', () {
      expect(isComicChapterFinished(const {'seenUpToImage': 5}), isFalse);
      expect(isComicChapterFinished(const {}), isFalse);
    });
  });
}
