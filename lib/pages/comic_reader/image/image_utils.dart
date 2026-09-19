import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:image/image.dart' as img;

/// 像素图（RGBA，每像素一个 `Uint32`）。
///
/// 复刻自 venera 的 `lib/utils/image.dart` 中的 `Image`：
/// 供阅读器执行插件 `getImageLoadingConfig` 返回的 `modifyImage` 脚本时，
/// 在 JS 侧通过 `new Image(key)` 句柄 + `sendMessage({method:'image'})` 桥
/// 做切片打乱还原（`copyRange` / `fillImageAt` / `fillImageRangeAt` 等）。
///
/// 数据布局与 Flutter `ui.ImageByteFormat.rawStraightRgba` 一致：
/// 内存字节序 R,G,B,A，按 little-endian 读成 `Uint32` 后
/// 最低字节是 R，其次 G、B，最高字节是 A（`0xAABBGGRR`）。
class PxImage {
  final Uint32List _data;

  final int width;

  final int height;

  /// 只读像素数据（RGBA，每像素一个 `Uint32`），供测试/调试使用。
  Uint32List get data => _data;

  PxImage(this._data, this.width, this.height) {
    if (_data.length != width * height) {
      throw ArgumentError(
        'Invalid argument: data length must be equal to width * height.',
      );
    }
  }

  PxImage.empty(this.width, this.height) : _data = Uint32List(width * height);

  /// 用 Flutter codec 把图片字节解码为 [PxImage]。
  ///
  /// 依赖 dart:ui，**必须在主 isolate 调用**（解码完成后像素数据可传进 Isolate）。
  static Future<PxImage> decodeImage(Uint8List data) async {
    final codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final info = await frame.image
        .toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (info == null) {
      throw Exception('Failed to decode image');
    }
    final image = PxImage(
      Uint32List.view(info.buffer, info.offsetInBytes, info.lengthInBytes ~/ 4),
      frame.image.width,
      frame.image.height,
    );
    frame.image.dispose();
    return image;
  }

  PxImage copyRange(int x, int y, int width, int height) {
    if (width + x > this.width) {
      throw ArgumentError(
        'Invalid argument: x + width must be less than or equal to the image width.',
      );
    }
    if (height + y > this.height) {
      throw ArgumentError(
        'Invalid argument: y + height must be less than or equal to the image height.',
      );
    }
    final data = Uint32List(width * height);
    for (var j = 0; j < height; j++) {
      for (var i = 0; i < width; i++) {
        data[j * width + i] = _data[(j + y) * this.width + i + x];
      }
    }
    return PxImage(data, width, height);
  }

  void fillImageAt(int x, int y, PxImage image) {
    for (var j = 0; j < image.height && (j + y) < height; j++) {
      for (var i = 0; i < image.width && (i + x) < width; i++) {
        _data[(j + y) * width + i + x] = image._data[j * image.width + i];
      }
    }
  }

  void fillImageRangeAt(
    int x,
    int y,
    PxImage image,
    int srcX,
    int srcY,
    int width,
    int height,
  ) {
    for (var j = 0; j < height; j++) {
      for (var i = 0; i < width; i++) {
        _data[(j + y) * this.width + i + x] =
            image._data[(j + srcY) * image.width + i + srcX];
      }
    }
  }

  PxImage copyAndRotate90() {
    final data = Uint32List(width * height);
    for (var j = 0; j < height; j++) {
      for (var i = 0; i < width; i++) {
        data[i * height + height - j - 1] = _data[j * width + i];
      }
    }
    return PxImage(data, height, width);
  }

  /// 编码为 PNG 字节。
  ///
  /// 用纯 Dart 的 `package:image`（比 venera 的 lodepng 更适合在 Isolate 中执行）。
  Uint8List encodePng() {
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: _data.buffer,
      order: img.ChannelOrder.rgba,
      numChannels: 4,
    );
    return Uint8List.fromList(img.encodePng(image));
  }
}

/// 轻量 JS 引擎：只处理 `sendMessage({method:'image', ...})` 像素操作。
///
/// 与 venera `lib/utils/image.dart` 的 `JsEngine` 一致，用于在独立 Isolate
/// 中执行插件 `modifyImage` 脚本。不加载业务消息（http/log 等），
/// 但 `assets/js/init.js` 中的 `Image` 类依赖 `sendMessage` 桥。
class _ImageJsEngine {
  final FlutterQjs _engine = FlutterQjs();

  final Map<int, PxImage> images = {};

  int _key = 0;

  _ImageJsEngine() {
    _engine.dispatch();
    final setGlobalFunc = _engine
        .evaluate('(key, value) => { this[key] = value; }') as JSInvokable;
    setGlobalFunc(['sendMessage', _messageReceiver]);
    setGlobalFunc.free();
  }

  dynamic runCode(String js, [String? name]) {
    return _engine.evaluate(js, name: name);
  }

  int setImage(PxImage image) {
    final key = _key++;
    images[key] = image;
    return key;
  }

  Object? _messageReceiver(dynamic message) {
    if (message is! Map) return null;
    if (message['method'] != 'image') return null;
    switch (message['function']) {
      case 'copyRange':
        final image = images[message['key']];
        if (image == null) return null;
        return setImage(image.copyRange(
          message['x'] as int,
          message['y'] as int,
          message['width'] as int,
          message['height'] as int,
        ));
      case 'copyAndRotate90':
        final image = images[message['key']];
        if (image == null) return null;
        return setImage(image.copyAndRotate90());
      case 'fillImageAt':
        final image = images[message['key']];
        final image2 = images[message['image']];
        if (image == null || image2 == null) return null;
        image.fillImageAt(message['x'] as int, message['y'] as int, image2);
        return null;
      case 'fillImageRangeAt':
        final image = images[message['key']];
        final image2 = images[message['image']];
        if (image == null || image2 == null) return null;
        image.fillImageRangeAt(
          message['x'] as int,
          message['y'] as int,
          image2,
          message['srcX'] as int,
          message['srcY'] as int,
          message['width'] as int,
          message['height'] as int,
        );
        return null;
      case 'getWidth':
        return images[message['key']]?.width;
      case 'getHeight':
        return images[message['key']]?.height;
      case 'emptyImage':
        return setImage(
          PxImage.empty(message['width'] as int, message['height'] as int),
        );
    }
    return null;
  }
}

var _tasksCount = 0;

/// 执行插件 `modifyImage` 脚本，把打乱的切片图还原为原图。
///
/// 流程（与 venera `modifyImageWithScript` 一致）：
///   1. 主 isolate 用 Flutter codec 解码（dart:ui 只能在主 isolate 用）
///   2. 新起一个 isolate，加载 init.js + 插件脚本，JS 侧通过
///      `new Image(key)` + `modifyImage(image)` 做像素级还原
///   3. 结果编码为 PNG 返回
///
/// 并发限制：同时最多 3 个还原任务。
Future<Uint8List> modifyImageWithScript(Uint8List data, String script) async {
  while (_tasksCount > 3) {
    await Future.delayed(const Duration(milliseconds: 200));
  }
  _tasksCount++;
  try {
    final image = await PxImage.decodeImage(data);
    final initJs = await rootBundle.loadString('assets/js/init.js');
    // 只捕获可跨 isolate 传递的类型（Uint32List / int / String）
    final pixels = image._data;
    final width = image.width;
    final height = image.height;
    return await Isolate.run(() {
      final jsEngine = _ImageJsEngine();
      jsEngine.runCode(initJs, '<init>');
      jsEngine.runCode(script);
      final key = jsEngine.setImage(PxImage(pixels, width, height));
      final res = jsEngine.runCode('''
        let func = () => {
          let image = new Image($key);
          let result = modifyImage(image);
          return result.key;
        }
        func();
      ''');
      final newImage = jsEngine.images[res];
      final pngData = newImage!.encodePng();
      return Uint8List.fromList(pngData);
    });
  } finally {
    _tasksCount--;
  }
}
