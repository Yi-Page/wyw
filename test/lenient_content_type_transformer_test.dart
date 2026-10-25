import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/request/core/lenient_content_type_transformer.dart';

/// 非法响应 `Content-Type` 容错的防回归 guard。
///
/// 背景：部分站点返回 `application/json; charset=utf-8;`（末尾多一个分号），
/// `MediaType.parse` 抛 `FormatException` → `Transformer.isJsonMimeType`
/// 返回 false → `ResponseType.json` 的 `response.data` 静默退化成 String。
ResponseBody _jsonBody(String body, String contentType) {
  return ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: [contentType],
    },
  );
}

void main() {
  group('LenientContentTypeTransformer.sanitize', () {
    test('去掉末尾多余的分号', () {
      expect(
        LenientContentTypeTransformer.sanitize(
          'application/json; charset=utf-8;',
        ),
        'application/json; charset=utf-8',
      );
    });

    test('去掉中间/重复的空参数段', () {
      expect(
        LenientContentTypeTransformer.sanitize(
          'application/json;; charset=utf-8',
        ),
        'application/json; charset=utf-8',
      );
    });

    test('本来就合法的值不改写', () {
      expect(
        LenientContentTypeTransformer.sanitize(
          'application/json; charset=utf-8',
        ),
        isNull,
      );
      expect(
        LenientContentTypeTransformer.sanitize('application/json'),
        isNull,
      );
      // 参数值内部合法含分号，不能误伤。
      expect(
        LenientContentTypeTransformer.sanitize(
          'multipart/form-data; boundary="a;b"',
        ),
        isNull,
      );
    });
  });

  group('LenientContentTypeTransformer.transformResponse', () {
    final transformer = LenientContentTypeTransformer();

    test('非法 Content-Type 仍能自动 jsonDecode', () async {
      final data = await transformer.transformResponse(
        RequestOptions(path: '/', responseType: ResponseType.json),
        _jsonBody('{"a":1}', 'application/json; charset=utf-8;'),
      );
      expect(data, isA<Map<String, dynamic>>());
      expect((data as Map<String, dynamic>)['a'], 1);
    });

    test('合法 Content-Type 行为不变', () async {
      final data = await transformer.transformResponse(
        RequestOptions(path: '/', responseType: ResponseType.json),
        _jsonBody('{"a":1}', 'application/json; charset=utf-8'),
      );
      expect((data as Map<String, dynamic>)['a'], 1);
    });

    test('ResponseType.plain 仍原样返回字符串（JS 桥依赖该行为）', () async {
      final data = await transformer.transformResponse(
        RequestOptions(path: '/', responseType: ResponseType.plain),
        _jsonBody('{"a":1}', 'application/json; charset=utf-8;'),
      );
      expect(data, '{"a":1}');
    });
  });
}
