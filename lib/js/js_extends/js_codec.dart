import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asn1/asn1_parser.dart';
import 'package:pointycastle/asn1/primitives/asn1_integer.dart';
import 'package:pointycastle/asn1/primitives/asn1_sequence.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/block/modes/cfb.dart';
import 'package:pointycastle/block/modes/ecb.dart';
import 'package:pointycastle/block/modes/ofb.dart';
import 'package:uuid/uuid.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

/// JS 端可调用的编解码 / 加密 / 工具方法集合。
///
/// 对应 sendMessage({method: 'convert' | 'random' | 'uuid'}) 的处理。
/// 设计为纯数据处理工具（无状态），可被任意上下文实例化。
class JsCodec {
  /// 编码 / 加密主入口。
  ///
  /// 支持的 [data["type"]]：utf8 / gbk / base64 / md5 / sha1 / sha256 / sha512 /
  /// hmac / aes-ecb / aes-cbc / aes-cfb / aes-ofb / rsa。
  Object? convert(Map<String, dynamic> data) {
    final type = data['type'];
    final value = data['value'];
    final isEncode = data['isEncode'] as bool;
    try {
      switch (type) {
        case 'utf8':
          return isEncode ? utf8.encode(value) : utf8.decode(value);
        case 'gbk':
          final codec = const GbkCodec();
          return isEncode
              ? Uint8List.fromList(codec.encode(value))
              : codec.decode(value);
        case 'base64':
          return isEncode ? base64Encode(value) : base64Decode(value);
        case 'md5':
          return Uint8List.fromList(md5.convert(value).bytes);
        case 'sha1':
          return Uint8List.fromList(sha1.convert(value).bytes);
        case 'sha256':
          return Uint8List.fromList(sha256.convert(value).bytes);
        case 'sha512':
          return Uint8List.fromList(sha512.convert(value).bytes);
        case 'hmac':
          return _hmac(data, value);
        case 'aes-ecb':
          return _aesEcb(data, value, isEncode);
        case 'aes-cbc':
          return _aesCbc(data, value, isEncode);
        case 'aes-cfb':
          return _aesCfb(data, value, isEncode);
        case 'aes-ofb':
          return _aesOfb(data, value, isEncode);
        case 'rsa':
          return _rsa(data, isEncode);
        default:
          return value;
      }
    } catch (e, s) {
      WywLogger().e(
        '${LogTag.js} 编解码失败 type=$type',
        error: e,
        stackTrace: s,
      );
      return null;
    }
  }

  /// 随机数生成。
  num random(num min, num max, String type) {
    if (type == 'double') {
      return min + (max - min) * math.Random().nextDouble();
    }
    return (min + (max - min) * math.Random().nextDouble()).toInt();
  }

  /// UUID v1。
  String uuidV1() => const Uuid().v1();

  // ===== 私有：HMAC =====

  /// HMAC：`isString == true` 返回字符串，否则返回字节。
  Object? _hmac(Map<String, dynamic> data, dynamic value) {
    final key = data['key'];
    final hash = data['hash'];
    final hmac = Hmac(
      switch (hash) {
        'md5' => md5,
        'sha1' => sha1,
        'sha256' => sha256,
        'sha512' => sha512,
        _ => throw 'Unsupported hash: $hash',
      },
      key,
    );
    if (data['isString'] == true) {
      return hmac.convert(value).toString();
    }
    return Uint8List.fromList(hmac.convert(value).bytes);
  }

  // ===== 私有：AES 系列 =====

  Uint8List _aesEcb(Map<String, dynamic> data, dynamic value, bool isEncode) {
    final cipher = ECBBlockCipher(AESEngine());
    cipher.init(isEncode, KeyParameter(data['key']));
    return _processInBlocksMode(cipher, value as Uint8List);
  }

  Uint8List _aesCbc(Map<String, dynamic> data, dynamic value, bool isEncode) {
    final cipher = CBCBlockCipher(AESEngine());
    cipher.init(
      isEncode,
      ParametersWithIV(KeyParameter(data['key']), data['iv']),
    );
    return _processInBlocksMode(cipher, value as Uint8List);
  }

  Uint8List _aesCfb(Map<String, dynamic> data, dynamic value, bool isEncode) {
    final cipher = CFBBlockCipher(AESEngine(), data['blockSize']);
    cipher.init(
      isEncode,
      ParametersWithIV(KeyParameter(data['key']), data['iv']),
    );
    return _processInBlocksMode(cipher, value as Uint8List);
  }

  Uint8List _aesOfb(Map<String, dynamic> data, dynamic value, bool isEncode) {
    final cipher = OFBBlockCipher(AESEngine(), data['blockSize']);
    cipher.init(isEncode, KeyParameter(data['key']));
    return _processInBlocksMode(cipher, value as Uint8List);
  }

  /// 块密码按 inputBlockSize 分块处理（AES-ECB/CBC/CFB/OFB 共用）。
  Uint8List _processInBlocksMode(BlockCipher cipher, Uint8List input) {
    var offset = 0;
    final result = Uint8List(input.length);
    while (offset < input.length) {
      offset += cipher.processBlock(input, offset, result, offset);
    }
    return result;
  }

  // ===== 私有：RSA =====

  Uint8List? _rsa(Map<String, dynamic> data, bool isEncode) {
    if (!isEncode) {
      final key = data['key'];
      final cipher = PKCS1Encoding(RSAEngine());
      cipher.init(
        false,
        PrivateKeyParameter<RSAPrivateKey>(_parsePrivateKey(key)),
      );
      return _processInBlocks(cipher, data['value'] as Uint8List);
    }
    return null;
  }

  RSAPrivateKey _parsePrivateKey(String privateKeyString) {
    final privateKeyDER = base64Decode(privateKeyString);
    var asn1Parser = ASN1Parser(privateKeyDER);
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    final privateKey = topLevelSeq.elements![2];

    asn1Parser = ASN1Parser(privateKey.valueBytes!);
    final pkSeq = asn1Parser.nextObject() as ASN1Sequence;

    final modulus = pkSeq.elements![1] as ASN1Integer;
    final privateExponent = pkSeq.elements![3] as ASN1Integer;
    final p = pkSeq.elements![4] as ASN1Integer;
    final q = pkSeq.elements![5] as ASN1Integer;

    return RSAPrivateKey(
      modulus.integer!,
      privateExponent.integer!,
      p.integer!,
      q.integer!,
    );
  }

  /// 非对称块密码分块处理（RSA 用）。
  Uint8List _processInBlocks(AsymmetricBlockCipher engine, Uint8List input) {
    final numBlocks = input.length ~/ engine.inputBlockSize +
        ((input.length % engine.inputBlockSize != 0) ? 1 : 0);
    final output = Uint8List(numBlocks * engine.outputBlockSize);

    var inputOffset = 0;
    var outputOffset = 0;
    while (inputOffset < input.length) {
      final chunkSize = (inputOffset + engine.inputBlockSize <= input.length)
          ? engine.inputBlockSize
          : input.length - inputOffset;

      outputOffset += engine.processBlock(
        input,
        inputOffset,
        chunkSize,
        output,
        outputOffset,
      );

      inputOffset += chunkSize;
    }

    return (output.length == outputOffset)
        ? output
        : output.sublist(0, outputOffset);
  }
}
