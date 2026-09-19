import 'dart:async' show Future, StreamController, scheduleMicrotask;
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

import 'image_downloader.dart' show ImageLoadingCancelledException;

/// 自定义图片 Provider 基类。
///
/// 复刻自 venera 的 `BaseImageProvider`：
/// - 通过 [load] 异步读取图片字节，并把下载进度转为 [ImageChunkEvent]
/// - 内置指数退避重试（握手错误/短数据等场景）
/// - 支持超大图降采样（[enableResize] 时按 `maxImagePixel` 限制像素总量）
abstract class BaseImageProvider<T extends BaseImageProvider<T>>
    extends ImageProvider<T> {
  const BaseImageProvider();

  static const int maxImagePixel = 2560 * 1440;

  static ui.TargetImageSize _getTargetSize(int width, int height) {
    // 忽略非法尺寸
    if (width <= 0 || height <= 0) {
      return ui.TargetImageSize(width: width, height: height);
    }
    // 忽略过宽或过高的图片（漫画分镜长图等）
    final imageRatio = width / height;
    if (imageRatio > 2 || imageRatio < 0.5) {
      return ui.TargetImageSize(width: width, height: height);
    }
    // 图片过大时等比缩小
    if (width * height > maxImagePixel) {
      final ratio = sqrt(maxImagePixel / (width * height));
      return ui.TargetImageSize(
        width: (width * ratio).round(),
        height: (height * ratio).round(),
      );
    }
    return ui.TargetImageSize(width: width, height: height);
  }

  @override
  ImageStreamCompleter loadImage(T key, ImageDecoderCallback decode) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _loadBufferAsync(key, chunkEvents, decode),
      chunkEvents: chunkEvents.stream,
      scale: 1.0,
      informationCollector: () sync* {
        yield DiagnosticsProperty<ImageProvider>(
          'Image provider: $this \n Image key: $key',
          this,
          style: DiagnosticsTreeStyle.errorProperty,
        );
      },
    );
  }

  Future<ui.Codec> _loadBufferAsync(
    T key,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode,
  ) async {
    try {
      int retryTime = 1;

      bool stop = false;

      chunkEvents.onCancel = () {
        stop = true;
      };

      Uint8List? data;

      while (data == null && !stop) {
        try {
          data = await load(chunkEvents, () {
            if (stop) {
              throw const _ImageLoadingStopException();
            }
          });
        } on _ImageLoadingStopException {
          rethrow;
        } catch (e) {
          // 取消加载（阅读器退出/切章）不重试，直接终止，
          // 否则会重新发起下载，导致退出后图片仍在加载。
          if (e is ImageLoadingCancelledException) {
            rethrow;
          }
          if (e.toString().contains('Invalid Status Code: 404')) {
            rethrow;
          }
          if (e.toString().contains('Invalid Status Code: 403')) {
            rethrow;
          }
          if (e.toString().contains('handshake')) {
            if (retryTime < 5) {
              retryTime = 5;
            }
          }
          retryTime <<= 1;
          if (retryTime > (1 << 3) || stop) {
            rethrow;
          }
          await Future.delayed(Duration(seconds: retryTime));
        }
      }

      if (stop) {
        throw const _ImageLoadingStopException();
      }

      if (data!.isEmpty) {
        throw Exception('Empty image data');
      }

      try {
        final buffer = await ui.ImmutableBuffer.fromUint8List(data);
        return await decode(
          buffer,
          getTargetSize: enableResize ? _getTargetSize : null,
        );
      } catch (e) {
        if (data.length < 2 * 1024) {
          // 数据太短，很可能是文本而非图片
          try {
            final text =
                const Utf8Codec(allowMalformed: false).decoder.convert(data);
            throw Exception('Expected image data, but got text: $text');
          } catch (e) {
            // 忽略
          }
        }
        rethrow;
      }
    } on _ImageLoadingStopException {
      rethrow;
    } on ImageLoadingCancelledException {
      // 已取消的加载：不 evict 缓存、不上报错误日志。
      rethrow;
    } catch (e, s) {
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      WywLogger()
          .e('${LogTag.reader} 图片加载失败 key=$key', error: e, stackTrace: s);
      rethrow;
    } finally {
      chunkEvents.close();
    }
  }

  /// 读取图片字节；通过 [chunkEvents] 上报进度，[checkStop] 检测取消。
  Future<Uint8List> load(
    StreamController<ImageChunkEvent> chunkEvents,
    void Function() checkStop,
  );

  String get key;

  @override
  bool operator ==(Object other) {
    return other is BaseImageProvider<T> && key == other.key;
  }

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() {
    return '$runtimeType($key)';
  }

  bool get enableResize => false;
}

class _ImageLoadingStopException implements Exception {
  const _ImageLoadingStopException();
}
