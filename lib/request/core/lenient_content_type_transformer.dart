import 'dart:async';

import 'package:dio/dio.dart';

/// 容忍非法的响应 `Content-Type`，避免 JSON 自动解码被静默跳过。
///
/// 部分站点会返回带多余分号的 `Content-Type`，例如
/// `application/json; charset=utf-8;`。此时 `http_parser` 的
/// `MediaType.parse` 抛 `FormatException`，`Transformer.isJsonMimeType` 捕获后
/// 返回 false，于是 [SyncTransformer] 不再调用 jsonDecode：
/// `ResponseType.json` 请求的 `response.data` 会静默退化成 String，
/// 同时打印一条 "Failed to parse the media type" 告警。
///
/// 这里只在存在空参数段时改写 `Content-Type`，其余行为与
/// [BackgroundTransformer] 完全一致；`ResponseType.plain` / `bytes` / `stream`
/// 的返回类型不受影响。
class LenientContentTypeTransformer extends BackgroundTransformer {
  /// 去掉 `Content-Type` 中的空参数段（即多余的分号）。
  ///
  /// 返回 null 表示无需改写，避免误伤本来就合法的取值，例如
  /// 参数内含分号的 `multipart/form-data; boundary="a;b"`。
  static String? sanitize(String value) {
    final segments = value.split(';');
    if (segments.length == 1 ||
        segments.skip(1).every((segment) => segment.trim().isNotEmpty)) {
      return null;
    }
    final cleaned = segments
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .join('; ');
    return cleaned.isEmpty ? null : cleaned;
  }

  @override
  Future<dynamic> transformResponse(
    RequestOptions options,
    ResponseBody responseBody,
  ) {
    final values = responseBody.headers[Headers.contentTypeHeader];
    final raw = (values == null || values.isEmpty) ? null : values.first;
    final sanitized = raw == null ? null : sanitize(raw);
    if (sanitized == null) {
      return super.transformResponse(options, responseBody);
    }
    // 原地改写 headers：保留 ResponseBody 的私有 _onClose，避免影响连接释放。
    responseBody.headers[Headers.contentTypeHeader] = [sanitized];
    return super.transformResponse(options, responseBody);
  }
}
