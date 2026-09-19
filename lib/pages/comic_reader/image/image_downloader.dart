import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:wyw/request/core/dio_factory.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/network/image_cache_manager.dart';

import 'image_utils.dart';

/// 图片下载进度事件。
class ImageDownloadProgress {
  final int currentBytes;

  final int? totalBytes;

  final Uint8List? imageBytes;

  const ImageDownloadProgress({
    required this.currentBytes,
    required this.totalBytes,
    this.imageBytes,
  });
}

/// 图片加载被取消（阅读器退出 / 切章时批量取消）。
///
/// [ImageDownloader.cancelAllLoadingImages] 会把它作为错误事件注入所有
/// 未完成的加载流；[BaseImageProvider] 据此识别「取消」并终止重试循环，
/// 避免退出后仍重新发起下载。
class ImageLoadingCancelledException implements Exception {
  const ImageLoadingCancelledException();

  @override
  String toString() => 'Image loading cancelled';
}

/// 漫画图片下载器。
///
/// 复刻自 venera 的 `ImageDownloader`：
/// - 同一图片去重：多个 `ImageProvider` 共享一个下载流
/// - 内存缓存 + 磁盘缓存（[AppImageCacheManager]）+ dio 网络下载
/// - 下载过程通过流上报进度，供 `ImageProvider` 生成 `ImageChunkEvent`
class ImageDownloader {
  ImageDownloader._();

  static final Map<String, Uint8List> _memoryCache = {};

  static final _loadingImages =
      <String, _StreamWrapper<ImageDownloadProgress>>{};

  /// 获取图片加载配置的回调（由宿主在启动时注册）。
  ///
  /// 根据 [sourceKey] 找到对应插件，调用其 `getImageLoadingConfig(url, comicId, epId)`
  /// （对应 venera 的 `comic.onImageLoad`）。返回的 Map 可能包含：
  ///   - `url` — 覆盖请求地址
  ///   - `method` — 覆盖请求方法（大写）
  ///   - `data` — 请求体
  ///   - `headers` — 自定义请求头（鉴权 / referer 等）
  ///   - `modifyImage` — JS 脚本字符串，下载后做切片打乱还原
  static Future<Map<String, dynamic>> Function(
    String sourceKey,
    String imageKey,
    String cid,
    String eid,
  )? fetchImageLoadingConfig;

  /// 取消所有正在加载的图片。
  static void cancelAllLoadingImages() {
    for (var wrapper in _loadingImages.values) {
      wrapper.cancel();
    }
    _loadingImages.clear();
  }

  /// 加载一张漫画图片（网络或缓存）。
  static Stream<ImageDownloadProgress> loadComicImage(
    String imageKey, {
    String? sourceKey,
    String? cid,
    String? eid,
    Map<String, String>? headers,
  }) {
    final cacheKey = '$imageKey@$sourceKey@$cid@$eid';
    if (_loadingImages.containsKey(cacheKey)) {
      return _loadingImages[cacheKey]!.stream;
    }
    final cancelToken = CancelToken();
    final stream = _StreamWrapper<ImageDownloadProgress>(
      _loadComicImage(imageKey, sourceKey, cid, eid, headers, cancelToken),
      cancelToken,
      (wrapper) {
        _loadingImages.remove(cacheKey);
      },
    );
    _loadingImages[cacheKey] = stream;
    return stream.stream;
  }

  static Stream<ImageDownloadProgress> _loadComicImage(
    String imageKey,
    String? sourceKey,
    String? cid,
    String? eid,
    Map<String, String>? headers,
    CancelToken cancelToken,
  ) async* {
    final cacheKey = '$imageKey@$sourceKey@$cid@$eid';

    // 1. 内存缓存
    final memory = _memoryCache[cacheKey];
    if (memory != null) {
      yield ImageDownloadProgress(
        currentBytes: memory.length,
        totalBytes: memory.length,
        imageBytes: memory,
      );
      return;
    }

    // 2. 磁盘缓存
    try {
      final info =
          await AppImageCacheManager.instance.getFileFromCache(cacheKey);
      if (info != null && await info.file.exists()) {
        final data = await info.file.readAsBytes();
        _memoryCache[cacheKey] = data;
        yield ImageDownloadProgress(
          currentBytes: data.length,
          totalBytes: data.length,
          imageBytes: data,
        );
        return;
      }
    } catch (e) {
      WywLogger().w('${LogTag.reader} 读取磁盘缓存失败 cacheKey=$cacheKey', error: e);
    }

    // 3. 获取图片加载配置（插件可覆盖 url/method/data/headers/modifyImage）
    var configs = <String, dynamic>{};
    if (sourceKey != null && fetchImageLoadingConfig != null) {
      try {
        configs = await fetchImageLoadingConfig!(
          sourceKey,
          imageKey,
          cid ?? '',
          eid ?? '',
        );
      } catch (e) {
        WywLogger().w(
          '${LogTag.reader} 获取图片配置失败 sourceKey=$sourceKey imageKey=$imageKey',
          error: e,
        );
      }
    }
    if (cancelToken.isCancelled) {
      // 已取消（阅读器退出/切章），不再发起网络请求。
      throw const ImageLoadingCancelledException();
    }

    // 4. 网络下载。
    // 失败时重新获取配置后重试（最多 5 次，近似 venera 的 onLoadFailed）。
    var retryLimit = 5;
    while (true) {
      try {
        final requestUrl = configs['url']?.toString() ?? imageKey;
        final requestHeaders =
            (configs['headers'] as Map?)?.cast<String, dynamic>() ?? headers;
        var response = await DioFactory.apiDio.request<ResponseBody>(
          requestUrl,
          data: configs['data'],
          cancelToken: cancelToken,
          options: Options(
            method: (configs['method']?.toString() ?? 'GET').toUpperCase(),
            responseType: ResponseType.stream,
            headers: requestHeaders,
          ),
        );
        final stream =
            response.data?.stream ?? (throw 'Error: Empty response body.');
        int? expectedBytes = response.data!.contentLength;
        if (expectedBytes == -1) {
          expectedBytes = null;
        }
        final buffer = <int>[];
        await for (final data in stream) {
          buffer.addAll(data);
          yield ImageDownloadProgress(
            currentBytes: buffer.length,
            totalBytes: expectedBytes,
          );
        }

        final bytes = Uint8List.fromList(buffer);
        if (bytes.isEmpty) {
          throw 'Error: Empty response body.';
        }

        // modifyImage 脚本还原（切片打乱还原，如禁漫天堂）
        Uint8List imageData = bytes;
        final modifyScript = configs['modifyImage'];
        if (modifyScript is String && modifyScript.trim().isNotEmpty) {
          imageData = await modifyImageWithScript(bytes, modifyScript);
        }

        _memoryCache[cacheKey] = imageData;
        try {
          await AppImageCacheManager.instance.putFile(cacheKey, imageData);
        } catch (e) {
          WywLogger()
              .w('${LogTag.reader} 写入磁盘缓存失败 cacheKey=$cacheKey', error: e);
        }
        yield ImageDownloadProgress(
          currentBytes: imageData.length,
          totalBytes: imageData.length,
          imageBytes: imageData,
        );
        return;
      } catch (e) {
        // 取消后不再重试：立即终止（否则会重新获取配置并再次发起下载）。
        if (cancelToken.isCancelled) {
          rethrow;
        }
        if (retryLimit < 0 ||
            fetchImageLoadingConfig == null ||
            sourceKey == null) {
          rethrow;
        }
        // 重新获取配置后重试
        Map<String, dynamic>? newConfig;
        try {
          newConfig = await fetchImageLoadingConfig!(
            sourceKey,
            imageKey,
            cid ?? '',
            eid ?? '',
          );
        } catch (e) {
          WywLogger().d(
              '${LogTag.reader} 重试前重新获取图片配置失败（已忽略） sourceKey=$sourceKey imageKey=$imageKey',
              error: e);
          newConfig = null;
        }
        if (newConfig == null || newConfig.isEmpty) rethrow;
        configs = newConfig;
        retryLimit--;
      }
    }
  }
}

/// 支持多监听者的流包装器，用于同一图片的并发请求去重。
class _StreamWrapper<T> {
  final Stream<T> _stream;

  final CancelToken cancelToken;

  final List<StreamController<T>> controllers = [];

  final void Function(_StreamWrapper<T> wrapper) onClosed;

  bool isClosed = false;

  _StreamWrapper(this._stream, this.cancelToken, this.onClosed) {
    _listen();
  }

  void _listen() async {
    try {
      await for (var data in _stream) {
        if (isClosed) {
          break;
        }
        for (var controller in controllers) {
          if (!controller.isClosed) {
            controller.add(data);
          }
        }
      }
    } catch (e, s) {
      for (var controller in controllers) {
        if (!controller.isClosed) {
          controller.addError(e, s);
        }
      }
    } finally {
      for (var controller in controllers) {
        if (!controller.isClosed) {
          controller.close();
        }
      }
    }
    controllers.clear();
    isClosed = true;
    onClosed(this);
  }

  Stream<T> get stream {
    if (isClosed) {
      throw Exception('Stream is closed');
    }
    var controller = StreamController<T>();
    controllers.add(controller);
    controller.onCancel = () {
      controllers.remove(controller);
    };
    return controller.stream;
  }

  void cancel() {
    // 立即中止底层 HTTP 请求（dio 在下一个检查点抛出取消异常），
    // 避免取消后 socket 仍在后台继续拉取数据。
    if (!cancelToken.isCancelled) {
      cancelToken.cancel();
    }
    for (var controller in controllers) {
      if (!controller.isClosed) {
        // 以错误事件通知监听者「加载已取消」；只 close 的话，上层
        // （BaseImageProvider 的重试循环）会把它误判为加载失败而
        // 重新发起下载，导致退出阅读器后图片仍在加载。
        controller.addError(const ImageLoadingCancelledException());
        controller.close();
      }
    }
    controllers.clear();
    isClosed = true;
  }
}
