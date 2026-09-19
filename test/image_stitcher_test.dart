import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wyw/pages/comic_reader/image/image_stitcher.dart';

Uint8List solidPng(int width, int height, int r, int g, int b) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return img.encodePng(image);
}

void main() {
  test('纵向拼接：上下排列，宽度取最大、高度求和', () {
    final out = stitchImages(
      [solidPng(4, 3, 255, 0, 0), solidPng(2, 5, 0, 255, 0)],
      vertical: true,
      reverseOrder: false,
    )!;
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 4);
    expect(decoded.height, 8);
    // 第一张在最上（红）
    expect(decoded.getPixel(0, 0).r, 255);
    expect(decoded.getPixel(0, 0).g, 0);
    // 第二张在下（绿，宽 2 居中 → x=1..2）
    expect(decoded.getPixel(1, 7).g, 255);
    // 居中留白处是白色，不是透明
    final gap = decoded.getPixel(0, 7);
    expect([gap.r, gap.g, gap.b], [255, 255, 255]);
  });

  test('横向拼接：左右排列，宽度求和、高度取最大', () {
    final out = stitchImages(
      [solidPng(3, 4, 255, 0, 0), solidPng(5, 2, 0, 0, 255)],
      vertical: false,
      reverseOrder: false,
    )!;
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 8);
    expect(decoded.height, 4);
    expect(decoded.getPixel(0, 0).r, 255); // 左：红
    expect(decoded.getPixel(7, 1).b, 255); // 右：蓝（高 2 居中 → y=1..2）
  });

  test('reverseOrder：右→左模式第一张被放到右侧', () {
    final out = stitchImages(
      [solidPng(3, 4, 255, 0, 0), solidPng(5, 2, 0, 0, 255)],
      vertical: false,
      reverseOrder: true,
    )!;
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 8);
    expect(decoded.getPixel(7, 0).r, 255); // 第一张（红）在右
    expect(decoded.getPixel(0, 1).b, 255); // 第二张（蓝）在左
  });

  test('全 JPEG 输入时输出 JPEG', () {
    final jpeg = img.encodeJpg(img.Image(width: 2, height: 2));
    final out = stitchImages([jpeg, jpeg], vertical: true, reverseOrder: false)!;
    expect(isJpegBytes(out), isTrue);
  });

  test('混入 PNG 时输出 PNG（无损）', () {
    final jpeg = img.encodeJpg(img.Image(width: 2, height: 2));
    final out = stitchImages(
      [jpeg, solidPng(2, 2, 0, 0, 0)],
      vertical: true,
      reverseOrder: false,
    )!;
    expect(isJpegBytes(out), isFalse);
    expect(out[0], 0x89);
    expect(out[1], 0x50);
  });

  test('解码失败或空输入返回 null', () {
    expect(
      stitchImages([Uint8List.fromList([1, 2, 3])],
          vertical: true, reverseOrder: false),
      isNull,
    );
    expect(stitchImages(const [], vertical: true, reverseOrder: false), isNull);
  });
}
