import 'dart:async' show Future;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'base_image_provider.dart';
import 'image_downloader.dart';

/// 漫画阅读页使用的图片 Provider。
///
/// 复刻自 venera 的 `ComicReaderImageProvider`：
/// - 支持 `file://` 本地文件直接读取
/// - 网络图片通过 [ImageDownloader] 读取（带进度上报与缓存）
class ComicReaderImageProvider
    extends BaseImageProvider<ComicReaderImageProvider> {
  const ComicReaderImageProvider(
    this.imageKey,
    this.sourceKey,
    this.cid,
    this.eid,
    this.page, {
    this.enableResize = false,
  });

  final String imageKey;

  final String? sourceKey;

  final String cid;

  final String eid;

  final int page;

  @override
  final bool enableResize;

  @override
  Future<Uint8List> load(chunkEvents, checkStop) async {
    Uint8List? imageBytes;
    if (imageKey.startsWith('file://')) {
      final file = File(imageKey.substring(7));
      if (await file.exists()) {
        imageBytes = await file.readAsBytes();
      } else {
        throw 'Error: File not found.';
      }
    } else {
      await for (final event in ImageDownloader.loadComicImage(
        imageKey,
        sourceKey: sourceKey,
        cid: cid,
        eid: eid,
      )) {
        checkStop();
        chunkEvents.add(ImageChunkEvent(
          cumulativeBytesLoaded: event.currentBytes,
          expectedTotalBytes: event.totalBytes,
        ));
        if (event.imageBytes != null) {
          imageBytes = event.imageBytes;
          break;
        }
      }
    }
    if (imageBytes == null) {
      throw 'Error: Empty response body.';
    }
    return imageBytes;
  }

  @override
  Future<ComicReaderImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  String get key => '$imageKey@$sourceKey@$cid@$eid@$enableResize';
}
