import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/utils/crypto.dart';
import 'package:wyw/utils/dandan_credentials.dart';

/// 独立实现的官方签名算法，只用来算期望值。
///
/// 刻意不走被测的 `generateDandanSignature`：用被测实现推导期望值等于同义
/// 反复，改坏算法时测试照样通过。这里是照官方文档描述直译的版本。
String referenceSignature(
  String appId,
  String appSecret,
  int timestamp,
  String path,
) {
  final payload = appId + timestamp.toString() + path + appSecret;
  return base64.encode(sha256.convert(utf8.encode(payload)).bytes);
}

void main() {
  // 测试环境通常不带 --dart-define，此时两个值都是空串；带凭证跑（release
  // 构建链路）也必须成立，所以对照实现直接复用同一份注入值。
  final appId = dandanCredentials['id'] ?? '';
  final appSecret = dandanCredentials['value'] ?? '';

  group('签名算法管道', () {
    test('SHA-256 + base64 与公开测试向量一致', () {
      // NIST 向量：sha256("abc") = ba7816bf8f01cfea414140de5dae2223b0
      //                          0361a396177a9cb410ff61f20015ad
      const digestBase64 = 'ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=';
      final pipeline =
          base64.encode(sha256.convert(utf8.encode('abc')).bytes);
      expect(pipeline, digestBase64);
    });

    test('输出是 32 字节摘要的标准 base64（44 字符，含 1 个填充符）', () {
      final signature = generateDandanSignature('/api/v2/search/anime', 0);
      expect(signature.length, 44);
      expect(signature.endsWith('='), isTrue);
      expect(base64.decode(signature).length, 32);
    });
  });

  group('generateDandanSignature 与独立实现一致', () {
    test('纯 ASCII 路径', () {
      const path = '/api/v2/search/anime';
      const timestamp = 1700000000;
      expect(
        generateDandanSignature(path, timestamp),
        referenceSignature(appId, appSecret, timestamp, path),
      );
    });

    test('含数字的路径（弹幕库/作品编号）', () {
      const path = '/api/v2/comment/1234567';
      const timestamp = 1723456789;
      expect(
        generateDandanSignature(path, timestamp),
        referenceSignature(appId, appSecret, timestamp, path),
      );
    });

    test('含数字的路径（作品详情）', () {
      const path = '/api/v2/bangumi/18319';
      const timestamp = 1;
      expect(
        generateDandanSignature(path, timestamp),
        referenceSignature(appId, appSecret, timestamp, path),
      );
    });

    test('时间戳确定性：同一输入重复调用结果完全相同', () {
      const path = '/api/v2/search/episodes';
      const timestamp = 1700000000;
      final first = generateDandanSignature(path, timestamp);
      final second = generateDandanSignature(path, timestamp);
      expect(first, second);
      expect(first, referenceSignature(appId, appSecret, timestamp, path));
    });

    test('路径或时间戳变化都必须改变签名', () {
      final baseline = generateDandanSignature('/api/v2/comment/100', 1700000000);
      expect(
        generateDandanSignature('/api/v2/comment/101', 1700000000),
        isNot(baseline),
      );
      expect(
        generateDandanSignature('/api/v2/comment/100', 1700000001),
        isNot(baseline),
      );
    });

    test('签名只覆盖路径：查询串不参与计算', () {
      // 客户端的契约是「先剥掉查询串再签名」，这里锁住这个前提：
      // 若哪天把整条 URL 传进来，签名会与官方算法不一致（403）。
      const url = '/api/v2/search/anime?keyword=abc&v2=true';
      final path = Uri.parse(url).path;
      expect(path, '/api/v2/search/anime');
      expect(
        generateDandanSignature(path, 1700000000),
        generateDandanSignature('/api/v2/search/anime', 1700000000),
      );
      expect(
        generateDandanSignature(path, 1700000000),
        isNot(generateDandanSignature(url, 1700000000)),
      );
    });

    test('时间戳按秒级取用（毫秒除以 1000）', () {
      final milliseconds = DateTime.now().millisecondsSinceEpoch;
      final seconds = milliseconds ~/ 1000;
      expect(seconds.toString().length, 10);
      expect(
        DateTime.fromMillisecondsSinceEpoch(seconds * 1000).year,
        greaterThanOrEqualTo(2024),
      );
    });
  });
}
