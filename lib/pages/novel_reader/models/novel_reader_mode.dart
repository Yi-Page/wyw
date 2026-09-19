/// 小说阅读方式。
enum NovelReaderMode {
  /// 上下滚动阅读（章节间连续，滚动到底自动加载下一章）
  scroll,

  /// 分页阅读（左右翻页，翻到章末自动进入下一章）
  page;

  static NovelReaderMode fromKey(String key) =>
      key == 'page' ? NovelReaderMode.page : NovelReaderMode.scroll;

  String get key => this == NovelReaderMode.page ? 'page' : 'scroll';
}
