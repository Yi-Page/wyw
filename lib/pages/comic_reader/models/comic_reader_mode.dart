/// 阅读模式枚举。
///
/// 与 venera 保持一致：
/// - `gallery*`：分页浏览模式（一屏可显示多张图），左右/右左/上下
/// - `continuous*`：连续滚动模式，类似网页长图
enum ComicReaderMode {
  galleryLeftToRight('galleryLeftToRight'),
  galleryRightToLeft('galleryRightToLeft'),
  galleryTopToBottom('galleryTopToBottom'),
  continuousTopToBottom('continuousTopToBottom'),
  continuousLeftToRight('continuousLeftToRight'),
  continuousRightToLeft('continuousRightToLeft');

  final String key;

  bool get isGallery => key.startsWith('gallery');

  bool get isContinuous => key.startsWith('continuous');

  const ComicReaderMode(this.key);

  static ComicReaderMode fromKey(String key) {
    for (var mode in values) {
      if (mode.key == key) {
        return mode;
      }
    }
    return galleryLeftToRight;
  }
}
