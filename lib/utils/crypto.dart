import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:wyw/utils/dandan_credentials.dart';

/// 生成弹弹play 开放 API 的 `X-Signature`。
///
/// 官方算法：`base64(sha256(AppId + Timestamp + Path + AppSecret))`，
/// 其中 `Path` 是不含域名与查询串的路径（例如 `/api/v2/comment/12345`），
/// `Timestamp` 为秒级 Unix 时间戳，`AppSecret` 直接拼在末尾。
///
/// 这里刻意做成不接触 Dio / 时间源的纯函数：调用方自己取时间戳，
/// 单测也能直接按官方算法描述独立对照，无需 mock 网络。
///
/// 凭证缺失时按空串参与计算（请求方在发请求前已拦截），不抛异常——
/// 保证这个函数在任何环境下都可调用可测。
String generateDandanSignature(String path, int timestamp) {
  final appId = dandanCredentials['id'] ?? '';
  final appSecret = dandanCredentials['value'] ?? '';
  final payload = '$appId$timestamp$path$appSecret';
  final digest = sha256.convert(utf8.encode(payload));
  return base64Encode(digest.bytes);
}
