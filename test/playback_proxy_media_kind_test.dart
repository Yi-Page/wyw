import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/services/download/playback_proxy_service.dart';

/// 合流源判型 + HLS 代理转发的行为回归。
///
/// 背景（真机问题：mp4 的合流播放没法正常用）：
/// 合流要的是「播放进度即下载进度」，而进度能在两端共享靠的是**分片序列**
/// （两端同一套 `seg_00000.ts` 命名 + SegmentWriteCoordinator 的路径互斥）。
/// 整段媒体（mp4 直链）没有分片，这条共享量根本不存在，所以合流**不提供** mp4
/// 通道：播放页先用 [PlaybackProxyService.probeMediaKind] 判型，不是 HLS 就
/// 底部提示 + 降级为直链直接播放。
///
/// 判型必须只看**内容**不看 URL 后缀：有源把 `.mp4` 当目录名
/// （`…/1080P_4000K_x.mp4/index-v1-a1.m3u8` 其实是 TS 的 HLS），按后缀判必错。
class _OriginServer {
  _OriginServer(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;

  int get port => _server.port;

  /// 前 N 个请求直接回 500：用来制造"判型失败"的现场。
  int failNextRequests = 0;

  /// 让带 `Range: bytes=0-1023` 的**判型**请求拿到 200 + 空正文：造出
  /// "探不出来但也没报错"的现场（与 [failNextRequests] 是两条不同路径）。
  bool blankProbeResponse = false;

  static final List<int> mp4Bytes =
      List<int>.generate(4096, (i) => (i * 7 + 3) % 256);

  static final Map<String, List<int>> segments = {
    '/seg/0.ts': List<int>.generate(16, (i) => 0x10 + i),
    '/seg/1.ts': List<int>.generate(16, (i) => 0x80 + i),
  };

  static const String playlist = '#EXTM3U\n'
      '#EXT-X-VERSION:3\n'
      '#EXT-X-TARGETDURATION:4\n'
      '#EXT-X-MEDIA-SEQUENCE:0\n'
      '#EXTINF:4.000,\n'
      '/seg/0.ts\n'
      '#EXTINF:4.000,\n'
      '/seg/1.ts\n'
      '#EXT-X-ENDLIST\n';

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    if (failNextRequests > 0) {
      failNextRequests--;
      response.statusCode = HttpStatus.internalServerError;
      await response.close();
      return;
    }
    if (blankProbeResponse &&
        request.headers.value('range') == 'bytes=0-1023') {
      await response.close();
      return;
    }
    final path = request.uri.path;
    if (path == '/media.m3u8') {
      response.headers.contentType =
          ContentType('application', 'vnd.apple.mpegurl');
      response.write(playlist);
      await response.close();
      return;
    }
    if (path == '/video.mp4') {
      response.add(mp4Bytes);
      await response.close();
      return;
    }
    final segment = segments[path];
    if (segment == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    response.add(segment);
    await response.close();
  }

  Future<void> close() => _server.close(force: true);
}

class _ProxyResponse {
  _ProxyResponse(this.status, this.body);

  final int status;
  final List<int> body;
}

Future<_ProxyResponse> _get(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    return _ProxyResponse(response.statusCode, bytes);
  } finally {
    client.close(force: true);
  }
}

void main() {
  group('classifyProxyMediaBytes（按内容判型，不看 URL 后缀）', () {
    test('播放列表首段 → hlsPlaylist', () {
      expect(classifyProxyMediaBytes(utf8.encode('#EXTM3U\n#EXTINF:4.000,')),
          ProxyMediaKind.hlsPlaylist);
    });

    test('容忍前导空白与 UTF-8 BOM', () {
      expect(classifyProxyMediaBytes(utf8.encode('\n  #EXTM3U')),
          ProxyMediaKind.hlsPlaylist);
      expect(
        classifyProxyMediaBytes(
            <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('#EXTM3U')]),
        ProxyMediaKind.hlsPlaylist,
      );
    });

    test('mp4（ftyp）等任意二进制 → singleFile', () {
      expect(
        classifyProxyMediaBytes(<int>[0, 0, 0, 0x20, ...utf8.encode('ftypisom')]),
        ProxyMediaKind.singleFile,
      );
      expect(classifyProxyMediaBytes(_OriginServer.mp4Bytes),
          ProxyMediaKind.singleFile);
    });

    test('首段不足 7 字节 → unknown（这时候不猜）', () {
      expect(classifyProxyMediaBytes(utf8.encode('#EXT')),
          ProxyMediaKind.unknown);
      expect(classifyProxyMediaBytes(const <int>[]), ProxyMediaKind.unknown);
    });
  });

  group('probeMediaKind（合流判型的唯一入口，真实 loopback HTTP）', () {
    late Directory tempDir;
    late _OriginServer origin;
    final proxy = PlaybackProxyService.instance;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wyw_proxy_test');
      origin =
          _OriginServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
      await proxy.start();
    });

    tearDown(() async {
      await proxy.stop();
      await origin.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    String src(String path) => 'http://127.0.0.1:${origin.port}$path';

    test('HLS 播放列表 → hlsPlaylist（可合流）', () async {
      expect(await proxy.probeMediaKind(src('/media.m3u8')),
          ProxyMediaKind.hlsPlaylist);
    });

    test('mp4 直链 → singleFile（不可合流，调用方据此降级直链播放）', () async {
      expect(await proxy.probeMediaKind(src('/video.mp4')),
          ProxyMediaKind.singleFile);
    });

    test('判型请求只要首段：不带 Range 支持也要在 64 字节内断开', () async {
      // 源站忽略 Range：判型不能因此把 4KB 的"文件"整份读进来（真实源可能是
      // 几百 MB）。这里断言结论正确即可，读取量由实现里的 break 保证。
      expect(await proxy.probeMediaKind(src('/video.mp4')),
          ProxyMediaKind.singleFile);
    });

    test('判型失败（探测报错）→ unknown，不抛异常', () async {
      origin.failNextRequests = 1;
      expect(await proxy.probeMediaKind(src('/video.mp4')),
          ProxyMediaKind.unknown);
    });

    test('判型失败（响应过短/空正文）→ unknown', () async {
      origin.blankProbeResponse = true;
      expect(await proxy.probeMediaKind(src('/video.mp4')),
          ProxyMediaKind.unknown);
    });
  });

  group('HLS 代理转发（只有 HLS 会注册会话）', () {
    late Directory tempDir;
    late _OriginServer origin;
    final proxy = PlaybackProxyService.instance;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wyw_proxy_test');
      origin =
          _OriginServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
      await proxy.start();
    });

    tearDown(() async {
      await proxy.stop();
      await origin.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    String src(String path) => 'http://127.0.0.1:${origin.port}$path';

    PlaybackProxySession session(String key, String path) =>
        PlaybackProxySession(
          recordKey: key,
          episodeNumber: 1,
          m3u8Url: src(path),
          episodeDir: tempDir.path,
          httpHeaders: const <String, String>{},
          adBlockerEnabled: false,
        );

    test('注册 /m3u8：分片重写到代理地址，并落盘 seg_00000.ts', () async {
      final s = session('t_hls', '/media.m3u8');
      final url = proxy.registerSession(s);

      expect(url, contains('/m3u8?'));

      final playlist = await _get(url);
      expect(playlist.status, 200);
      final text = utf8.decode(playlist.body);
      expect(text, contains('#EXTM3U'));
      expect(text, contains('#EXT-X-ENDLIST'));
      // 分片地址被改写为代理地址（不再是源站地址）。
      expect(text, contains('/seg?src='));
      expect(text, isNot(contains('${src('/seg/0.ts')}\n')));

      final segUrl =
          RegExp(r'http://\S+/seg\?\S+').firstMatch(text)!.group(0)!;
      final seg = await _get(segUrl);
      expect(seg.body, _OriginServer.segments['/seg/0.ts']);
      expect(File('${tempDir.path}/seg_00000.ts').existsSync(), isTrue);
    });

    test('源不是播放列表时明确失败（判型与实际不符），不会写出任何文件', () async {
      // 绕过判型把 mp4 当会话注册：模拟"探测之后源内容变了"。
      final s = session('t_not_hls', '/video.mp4');
      final res = await _get(proxy.proxyM3u8Url(s));

      expect(res.status, 502);
      expect(File('${tempDir.path}/video.mp4').existsSync(), isFalse);
      expect(
        Directory(tempDir.path)
            .listSync()
            .where((e) => e is File && e.path.contains('seg_')),
        isEmpty,
      );
    });
  });
}
