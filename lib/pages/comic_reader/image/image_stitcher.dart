import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 把同一屏的多张图拼成一张（"保存本屏 / 两张拼一张"）。
///
/// 排布与屏幕一致：
///   - [vertical]：屏幕上纵向排列（`galleryTopToBottom`）时上下拼接，否则左右拼接；
///   - [reverseOrder]：屏幕为"右→左"（列表被反序显示）时，第一张在右侧。
///
/// 交叉方向按最大边长对齐并居中。编码：全为 JPEG 时输出 JPEG（体积小），
/// 否则输出 PNG（无损，兼容混格式/带透明通道的图）。
///
/// 任一张解码失败返回 null（调用方据此提示"保存失败"）。
Uint8List? stitchImages(
  List<Uint8List> parts, {
  required bool vertical,
  required bool reverseOrder,
}) {
  if (parts.isEmpty) return null;
  final decoded = <img.Image>[];
  for (final bytes in parts) {
    // 解码器对"不是图片的字节"（例如下载到的是错误页 HTML）会直接抛异常，
    // 例如 PSD 的 isValidFile 会越界读取，所以这里必须兜住。
    img.Image? image;
    try {
      image = img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
    if (image == null) return null;
    decoded.add(image);
  }
  // 屏幕上的显示顺序：右→左时第一张在最右（列表反序）
  final ordered = reverseOrder ? decoded.reversed.toList() : decoded;

  final width = vertical
      ? ordered.map((i) => i.width).reduce((a, b) => a > b ? a : b)
      : ordered.fold<int>(0, (sum, i) => sum + i.width);
  final height = vertical
      ? ordered.fold<int>(0, (sum, i) => sum + i.height)
      : ordered.map((i) => i.height).reduce((a, b) => a > b ? a : b);
  if (width <= 0 || height <= 0) return null;

  final canvas = img.Image(width: width, height: height, numChannels: 4);
  // 交叉方向尺寸不齐时居中留白，避免导出透明条带
  img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));
  var cursor = 0;
  for (final image in ordered) {
    final dstX = vertical ? (width - image.width) ~/ 2 : cursor;
    final dstY = vertical ? cursor : (height - image.height) ~/ 2;
    // 各图互不重叠，直接拷贝即可（不做 alpha 混合，避免通道数差异带来的干扰）。
    img.compositeImage(
      canvas,
      image,
      dstX: dstX,
      dstY: dstY,
      dstW: image.width,
      dstH: image.height,
      blend: img.BlendMode.direct,
    );
    cursor += vertical ? image.height : image.width;
  }

  final allJpeg = parts.every(
    (bytes) => bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8,
  );
  return allJpeg ? img.encodeJpg(canvas, quality: 92) : img.encodePng(canvas);
}

/// 是否全是 JPEG 字节（用于决定拼接输出的编码格式与文件扩展名）。
bool isJpegBytes(Uint8List bytes) =>
    bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
