import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:wyw/request/core/dio_factory.dart';
import 'package:wyw/request/core/network_error_mapper.dart';
import 'package:wyw/utils/crypto.dart';
import 'package:wyw/utils/dandan_credentials.dart';
import 'package:wyw/utils/http_headers.dart';

/// 未注入弹弹play 凭证（`--dart-define=DANDANAPI_APPID/DANDANAPI_KEY`）时抛出。
///
/// 单独定义异常而不是复用 [NetworkException]：凭证缺失不是网络故障，
/// 调用方应据此静默降级（不重试、不提示用户），本地开发构建必然走到这里。
class DandanNotConfiguredException implements Exception {
  const DandanNotConfiguredException();

  @override
  String toString() =>
      'DandanNotConfiguredException: 未配置弹弹play 凭证（DANDANAPI_APPID / DANDANAPI_KEY）';
}

/// 弹弹play 开放 API 的 HTTP 客户端。
///
/// 统一处理三件事：凭证与签名请求头、相对路径拼接域名、错误映射。
/// 只暴露 GET：本阶段只读弹幕数据，不发评论。
class DanmakuClient {
  DanmakuClient._();

  static final DanmakuClient instance = DanmakuClient._();

  /// 弹弹play 开放 API 域名；签名只覆盖路径，域名不参与计算。
  static const String baseUrl = 'https://api.dandanplay.net';

  /// [path] 必须是 `/api/v2/...` 形式的纯路径（不带域名和查询串）：
  /// 签名算法覆盖的就是它，查询参数交给 [queryParameters] 单独传。
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    if (!isDandanConfigured) {
      throw const DandanNotConfiguredException();
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final requestHeaders = <String, dynamic>{
      'user-agent': getRandomUA(),
      // 接口要求 X-Auth（实测缺失会 403），值固定为 1。
      'X-Auth': 1,
      'X-AppId': dandanCredentials['id'],
      'X-Timestamp': timestamp,
      'X-Signature': generateDandanSignature(path, timestamp),
    };

    try {
      final response = await DioFactory.apiDio.get<dynamic>(
        '$baseUrl$path',
        queryParameters: queryParameters,
        options: Options(headers: requestHeaders),
        cancelToken: cancelToken,
      );
      return _asJsonMap(response.data);
    } on DioException catch (e) {
      // 403/404 等一律交给统一映射，避免各调用点自己判断状态码。
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  /// 响应体容错：`ResponseType.json` 正常给 Map，但站点返回非标准
  /// `Content-Type` 时 dio 会退化成 String，这里兜一层手动解码。
  Map<String, dynamic> _asJsonMap(Object? data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } on FormatException catch (e, s) {
        throw NetworkErrorMapper.parse(e, s);
      }
    }
    final error = StateError('弹弹play 响应不是 JSON 对象: ${data.runtimeType}');
    throw NetworkErrorMapper.parse(error, StackTrace.current);
  }
}
