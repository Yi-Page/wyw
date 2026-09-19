import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 应用图片缓存管理器。
///
/// 负责漫画/封面等图片的内存 + 磁盘缓存：按 Content-Type 推断扩展名，
/// 并按 Cache-Control 计算有效时长。已移除早期遗留的代理与镜像改写逻辑。
class AppImageCacheManager extends CacheManager with ImageCacheManager {
  static final AppImageCacheManager instance = AppImageCacheManager._();

  AppImageCacheManager._()
      : super(
          Config(
            DefaultCacheManager.key,
            fileService: AppImageFileService(),
          ),
        );
}

class AppImageFileService extends FileService {
  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    try {
      final request = await client.getUrl(Uri.parse(url));
      headers?.forEach(request.headers.set);
      final response = await request.close();
      return _AppImageFileServiceResponse(response, client);
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }
}

class _AppImageFileServiceResponse implements FileServiceResponse {
  _AppImageFileServiceResponse(this._response, this._client);

  final HttpClientResponse _response;
  final HttpClient _client;
  final DateTime _receivedTime = DateTime.now();

  @override
  Stream<List<int>> get content async* {
    try {
      await for (final chunk in _response) {
        yield chunk;
      }
    } finally {
      _client.close();
    }
  }

  @override
  int? get contentLength =>
      _response.contentLength >= 0 ? _response.contentLength : null;

  @override
  String? get eTag => _response.headers.value(HttpHeaders.etagHeader);

  @override
  String get fileExtension {
    return switch (_response.headers.contentType?.mimeType.toLowerCase()) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      'image/bmp' => '.bmp',
      'image/x-icon' || 'image/vnd.microsoft.icon' => '.ico',
      'image/avif' => '.avif',
      'image/svg+xml' => '.svg',
      _ => '',
    };
  }

  @override
  int get statusCode => _response.statusCode;

  @override
  DateTime get validTill {
    var ageDuration = const Duration(days: 7);
    final controlHeader =
        _response.headers.value(HttpHeaders.cacheControlHeader);
    if (controlHeader == null) {
      return _receivedTime.add(ageDuration);
    }

    final controlSettings = controlHeader.split(',');
    for (final setting in controlSettings) {
      final sanitizedSetting = setting.trim().toLowerCase();
      if (sanitizedSetting == 'no-cache') {
        ageDuration = Duration.zero;
      }
      if (sanitizedSetting.startsWith('max-age=')) {
        final validSeconds =
            int.tryParse(sanitizedSetting.split('=').last) ?? 0;
        if (validSeconds > 0) {
          ageDuration = Duration(seconds: validSeconds);
        }
      }
    }

    return _receivedTime.add(ageDuration);
  }
}
