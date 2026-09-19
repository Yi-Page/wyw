import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// 漫画进度的**规范单位**与换算规则（纯函数，便于单测）。
///
/// **规范单位 = 章内图片序号（1-based）**：
///   - 与阅读模式无关（画廊/连续）、与屏幕方向无关、与"每屏几张"无关；
///   - 历史/进度一律持久化它，屏号只在视图层内部使用。
///
/// 两个量必须分开：
///   - **位置（水位线）**：视口顶部那张图 = "正在读哪张" —— [readingTopImageIndex]；
///     画廊一屏多张没有滚动，取该屏**最后一张**（= 已看过几张）—— [imageIndexOfPage]；
///   - **完成（水位线水位）**：曾经到达过的最大图片序号，单调不回退 —— 由 controller
///     维护，判定见 `isComicChapterFinished`（services/storage/history_progress.dart）。

/// 第 [page] 屏（1-based）覆盖的图片区间 `[start, end)`（0-based，半开）。
///
/// [imageCount] 用于夹取末屏（0 = 未知，只按每屏张数推算）。
(int, int) imageRangeOfPage({
  required int page,
  required int imagesPerPage,
  required bool singleImageOnFirstPage,
  int imageCount = 0,
}) {
  final perPage = imagesPerPage < 1 ? 1 : imagesPerPage;
  final p = page < 1 ? 1 : page;
  // 首屏单图：第 1 屏只放 1 张，从第 2 屏起才按每屏张数
  final singleFirstPage = singleImageOnFirstPage && p == 1;
  var start = singleImageOnFirstPage
      ? (p == 1 ? 0 : (p - 2) * perPage + 1)
      : (p - 1) * perPage;
  var end = start + (singleFirstPage ? 1 : perPage);
  if (imageCount > 0) {
    if (start > imageCount) start = imageCount;
    if (end > imageCount) end = imageCount;
  }
  if (end < start) end = start;
  return (start, end);
}

/// 第 [page] 屏阅读方向上的**最后一张**图（1-based 图片序号）。
///
/// 画廊一屏多张时，这一屏看完就等于"看到这一屏的最后一张"——6 张图每屏 2 张时，
/// 三屏分别是 2 / 4 / 6（而不是屏号 1 / 2 / 3）。无图返回 0。
int imageIndexOfPage({
  required int page,
  required int imagesPerPage,
  required bool singleImageOnFirstPage,
  required int imageCount,
}) {
  if (imageCount <= 0) return 0;
  final (_, end) = imageRangeOfPage(
    page: page,
    imagesPerPage: imagesPerPage,
    singleImageOnFirstPage: singleImageOnFirstPage,
    imageCount: imageCount,
  );
  return end;
}

/// 包含第 [imageIndex] 张图（1-based）的屏号（1-based）——[imageIndexOfPage] 的逆。
///
/// [imageCount] 用于夹取（0 = 未知）。
int pageOfImageIndex({
  required int imageIndex,
  required int imagesPerPage,
  required bool singleImageOnFirstPage,
  int imageCount = 0,
}) {
  final perPage = imagesPerPage < 1 ? 1 : imagesPerPage;
  var i = imageIndex < 1 ? 1 : imageIndex;
  if (imageCount > 0 && i > imageCount) i = imageCount;
  if (perPage == 1) return i;
  if (singleImageOnFirstPage) {
    return i == 1 ? 1 : ((i - 2) ~/ perPage) + 2;
  }
  return ((i - 1) ~/ perPage) + 1;
}

/// 阅读**当前位置**：视口"水位线"（顶部边缘）上的那张图。
///
/// 取可见项里 `itemLeadingEdge` **最小**的一张 —— 即"顶端已经越过屏幕顶部"的那张，
/// 也就是连续模式下正在阅读的那张。包内 `leading/trailing` 已按阅读方向归一化，
/// 所以三种连续模式（上→下 / 左→右 / 右→左）口径一致。
///
/// 末图比视口矮时，它的顶端永远到不了屏幕顶部 → 需要在列表尾部留出
/// `视口长度 - 末图长度` 的占位（见 `_ContinuousModeState._tailExtent`），
/// 否则进度与"读完"判定会永远停在倒数第二张。
///
/// 列表首尾的两个 0 高占位（index 0 / maxIndex+1）由 [minIndex]/[maxIndex] 排除。
/// 无有效可见项返回 0。
int readingTopImageIndex(
  Iterable<ItemPosition> positions, {
  int minIndex = 1,
  required int maxIndex,
}) {
  var best = 0;
  var bestLeading = double.infinity;
  for (final position in positions) {
    if (position.index < minIndex) continue;
    if (maxIndex > 0 && position.index > maxIndex) continue;
    if (position.itemLeadingEdge < bestLeading) {
      bestLeading = position.itemLeadingEdge;
      best = position.index;
    }
  }
  return best;
}
