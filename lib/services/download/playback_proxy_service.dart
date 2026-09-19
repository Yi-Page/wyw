// ignore_for_file: prefer_interpolation_to_compose_strings

// 本地播放代理：实现「播放即下载」。
//
// 播放器请求走本代理（http://127.0.0.1:port/...），代理从源站拉取媒体数据，
// 同时把字节落盘到 DownloadManager 同一套下载目录与文件命名
// （seg_00000.ts / key_0.key / video.mp4），因此 DownloadManager 扫描
// 「已存在分片」时会自动跳过代理已落盘的分片 —— 每分片只会从源站拉取一次，
// 播放与下载共用同一条网络流，不产生双倍流量。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wyw/request/clients/download_http_client.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/utils/m3u8_ad_filter.dart';
import 'package:wyw/utils/m3u8_parser.dart';
import 'package:wyw/utils/segment_file_coordinator.dart';

/// 代理模式进度回调：recordKey / episodeNumber / 已落盘分片数 / 总分片数
typedef ProxyProgressCallback = void Function(String recordKey,
    int episodeNumber, int downloadedSegments, int totalSegments);

/// 单个「播放即下载」会话的上下文。
class PlaybackProxySession {
  final String recordKey;
  final int episodeNumber;
  final String m3u8Url; // 解析后的最终媒体列表（直链 m3u8）
  final String episodeDir; // 落盘目录（与 DownloadManager 一致）
  final Map<String, String> httpHeaders;
  final bool adBlockerEnabled;

  int totalSegments = 0;
  int downloadedSegments = 0;

  PlaybackProxySession({
    required this.recordKey,
    required this.episodeNumber,
    required this.m3u8Url,
    required this.episodeDir,
    required this.httpHeaders,
    required this.adBlockerEnabled,
  });
}

/// 本地 HTTP 代理服务（单例）。
class PlaybackProxyService {
  PlaybackProxyService._();

  static final PlaybackProxyService instance = PlaybackProxyService._();

  HttpServer? _server;
  int _port = 0;

  final _sessions = <String, PlaybackProxySession>{};
  final _inFlightSegments = <String, Future<List<int>>>{};
  final _inFlightKeys = <String, Future<List<int>>>{};

  ProxyProgressCallback? onProgress;

  bool get isRunning => _server != null;

  int get port => _port;

  /// 启动代理服务器（幂等）。
  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _port = server.port;
    unawaited(_serve(server));
    WywLogger().i('${LogTag.download} 播放代理已启动 127.0.0.1:$_port');
  }

  /// 注册一个会话并返回其代理 m3u8 URL（给播放器使用）。
  String registerSession(PlaybackProxySession session) {
    _sessions[session.recordKey] = session;
    return proxyM3u8Url(session);
  }

  /// 按 recordKey 获取会话。
  PlaybackProxySession? sessionOf(String recordKey) => _sessions[recordKey];

  /// 移除会话（停止代理播放）。
  void removeSession(String recordKey) {
    _sessions.remove(recordKey);
  }

  String _baseUrl() => 'http://127.0.0.1:' + _port.toString();

  /// 代理 m3u8 地址：播放器加载该地址，会获得分片 URI 全部重写为代理地址的
  /// 播放列表；随后播放器请求每个分片时，代理从源站拉取并落盘。
  String proxyM3u8Url(PlaybackProxySession session) {
    final src = Uri.encodeComponent(session.m3u8Url);
    final dir = Uri.encodeComponent(session.episodeDir);
    final hdrs = Uri.encodeComponent(jsonEncode(session.httpHeaders));
    return _baseUrl() +
        '/m3u8?src=' +
        src +
        '&dir=' +
        dir +
        '&hdrs=' +
        hdrs +
        '&rk=' +
        session.recordKey;
  }

  /// mp4 直链代理地址。
  String proxyMp4Url(String src, String episodeDir,
      Map<String, String> httpHeaders, String recordKey) {
    final encSrc = Uri.encodeComponent(src);
    final dir = Uri.encodeComponent(episodeDir);
    final hdrs = Uri.encodeComponent(jsonEncode(httpHeaders));
    return _baseUrl() +
        '/mp4?src=' +
        encSrc +
        '&dir=' +
        dir +
        '&hdrs=' +
        hdrs +
        '&rk=' +
        recordKey;
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request).catchError((Object e, StackTrace st) {
        WywLogger().e('${LogTag.download} 代理请求处理失败 path=${request.uri.path}',
            error: e, stackTrace: st);
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write('proxy error');
          request.response.close();
        } catch (_) {
          // 静默可接受：错误兜底响应写回失败属常态（客户端可能已断开连接）
        }
      }));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final uri = request.uri;
    final path = uri.path;
    final response = request.response;

    if (path == '/m3u8') {
      await _handleM3u8(request, response);
    } else if (path == '/seg') {
      await _handleSegment(request, response);
    } else if (path == '/key') {
      await _handleKey(request, response);
    } else if (path == '/mp4') {
      await _handleMp4(request, response);
    } else {
      response.statusCode = HttpStatus.notFound;
      await response.close();
    }
  }

  // ---------- m3u8：拉取、解析、重写为代理分片地址 ----------

  Future<void> _handleM3u8(HttpRequest request, HttpResponse response) async {
    final src = request.uri.queryParameters['src'] ?? '';
    final dir = request.uri.queryParameters['dir'] ?? '';
    final hdrsJson = request.uri.queryParameters['hdrs'] ?? '{}';
    final recordKey = request.uri.queryParameters['rk'] ?? '';

    if (src.isEmpty || dir.isEmpty) {
      response.statusCode = HttpStatus.badRequest;
      await response.close();
      return;
    }

    Map<String, dynamic> headers = {};
    try {
      headers = jsonDecode(hdrsJson) as Map<String, dynamic>;
    } catch (e) {
      WywLogger().d(
          '${LogTag.download} hdrs JSON 解析失败，使用空 headers rk=$recordKey',
          error: e);
    }

    try {
      // 拉取 m3u8 内容（与 DownloadManager._fetchM3u8 相同逻辑）
      String content = await DownloadHttpClient.instance.getPlain(
        src,
        headers: headers,
        receiveTimeout: const Duration(seconds: 15),
      );
      final trimmed = content.trimLeft();
      if (!trimmed.startsWith('#EXTM3U')) {
        response.statusCode = HttpStatus.badGateway;
        response.write('not m3u8');
        await response.close();
        return;
      }

      // master -> 最佳 variant
      String mediaContent = content;
      String mediaBase = src;
      final type = M3u8Parser.detectType(mediaContent);
      if (type == M3u8Type.master) {
        final master = M3u8Parser.parseMasterPlaylist(mediaContent, src);
        final best = master.bestVariant;
        mediaBase = best.uri;
        mediaContent = await DownloadHttpClient.instance.getPlain(mediaBase,
            headers: headers, receiveTimeout: const Duration(seconds: 15));
      }

      final playlist = M3u8Parser.parseMediaPlaylist(mediaContent, mediaBase);

      // 展开嵌套 m3u8 片段（递归 + discontinuityGroup 重映射，逻辑与
      // DownloadManager 完全一致，保证代理与下载两端的索引/分片集合对齐）
      final resolvedSegments = await M3u8Parser.resolveNestedSegments(
        playlist.segments,
        (url) => DownloadHttpClient.instance.getPlain(
          url,
          headers: headers,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      // 记录总分片数供进度显示
      final session = _sessions[recordKey];
      final bool adFilterEnabled = session?.adBlockerEnabled ?? false;

      // 与 DownloadManager 一致：开启去广告时按 discontinuityGroup 过滤。
      // 若不过滤，代理按「原 m3u8 索引」落盘 seg_<idx>.ts，而下载端按
      // 「过滤后索引」落盘同名文件，两端错位会造成已播放分片在最终下载里
      // 缺失/错位、重复下载。
      List<M3u8Segment> segments = resolvedSegments;
      if (adFilterEnabled) {
        segments = M3u8AdFilter.filterAds(segments);
      }
      if (session != null) {
        session.totalSegments = segments.length;
      }
      final double targetDuration = adFilterEnabled
          ? M3u8AdFilter.calculateTargetDuration(segments)
          : playlist.targetDuration;

      // 重写为代理地址
      final sb = StringBuffer();
      sb.writeln('#EXTM3U');
      sb.writeln('#EXT-X-VERSION:3');
      sb.writeln('#EXT-X-TARGETDURATION:' + targetDuration.ceil().toString());
      sb.writeln('#EXT-X-MEDIA-SEQUENCE:0');

      M3u8Key? lastKey;
      int keyIndex = -1;
      final keyIndexMap = <String, int>{};
      for (int i = 0; i < segments.length; i++) {
        final seg = segments[i];
        if (seg.key != lastKey) {
          if (seg.key != null) {
            if (!keyIndexMap.containsKey(seg.key!.uri)) {
              keyIndexMap[seg.key!.uri] = ++keyIndex;
            }
            final kidx = keyIndexMap[seg.key!.uri]!;
            final ksrc = Uri.encodeComponent(seg.key!.uri);
            final ivPart = (seg.key!.iv != null && seg.key!.iv!.isNotEmpty)
                ? ',IV=' + seg.key!.iv!
                : '';
            sb.writeln('#EXT-X-KEY:METHOD=' +
                seg.key!.method +
                ',URI="' +
                _baseUrl() +
                '/key?src=' +
                ksrc +
                '&dir=' +
                dir +
                '&idx=' +
                kidx.toString() +
                '&rk=' +
                recordKey +
                '"' +
                ivPart);
          } else {
            sb.writeln('#EXT-X-KEY:METHOD=NONE');
          }
          lastKey = seg.key;
        }
        sb.writeln('#EXTINF:' + seg.duration.toStringAsFixed(3) + ',');
        final ssrc = Uri.encodeComponent(seg.uri);
        sb.writeln(_baseUrl() +
            '/seg?src=' +
            ssrc +
            '&dir=' +
            dir +
            '&idx=' +
            i.toString() +
            '&rk=' +
            recordKey);
      }
      sb.writeln('#EXT-X-ENDLIST');

      response.headers.contentType =
          ContentType('application', 'vnd.apple.mpegurl');
      response.write(sb.toString());
      await response.close();

      WywLogger().i(
          '${LogTag.download} m3u8 重写完成 rk=$recordKey 共${segments.length}个分片');
    } catch (e, s) {
      WywLogger().e('${LogTag.download} m3u8 拉取或重写失败 src=$src rk=$recordKey',
          error: e, stackTrace: s);
      response.statusCode = HttpStatus.badGateway;
      await response.close();
    }
  }

  // ---------- 分片：落盘 + 返回 ----------

  Future<void> _handleSegment(
      HttpRequest request, HttpResponse response) async {
    final src = request.uri.queryParameters['src'] ?? '';
    final dir = request.uri.queryParameters['dir'] ?? '';
    final idxStr = request.uri.queryParameters['idx'] ?? '0';
    final recordKey = request.uri.queryParameters['rk'] ?? '';
    final idx = int.tryParse(idxStr) ?? 0;

    final segPath =
        p.join(dir, 'seg_' + idx.toString().padLeft(5, '0') + '.ts');

    // 源站分片往往要求 UA/Referer，必须带上会话头（与 DownloadManager
    // 下载时相同的头），否则源站 403 会导致「已播放的分片下载不下来」。
    final session = _sessions[recordKey];
    final segHeaders = session?.httpHeaders ?? const <String, String>{};

    // 已落盘：直接返回本地文件
    final segFile = File(segPath);
    if (await segFile.exists() && await segFile.length() > 0) {
      final bytes = await segFile.readAsBytes();
      response.headers.contentType = ContentType('video', 'MP2T');
      response.add(bytes);
      await response.close();
      _markSegmentDownloaded(recordKey);
      return;
    }

    // 未落盘：并发去重后从源站拉取并落盘
    final future = _inFlightSegments[segPath] ??=
        _downloadAndSave(src, segPath, recordKey, headers: segHeaders);
    try {
      final bytes = await future;
      response.headers.contentType = ContentType('video', 'MP2T');
      response.add(bytes);
    } catch (e, s) {
      response.statusCode = HttpStatus.badGateway;
      response.write('segment download failed');
      WywLogger().e('${LogTag.download} 分片下载失败 src=$src idx=$idx',
          error: e, stackTrace: s);
    } finally {
      _inFlightSegments.remove(segPath);
      await response.close();
    }
  }

  Future<void> _handleKey(HttpRequest request, HttpResponse response) async {
    final src = request.uri.queryParameters['src'] ?? '';
    final dir = request.uri.queryParameters['dir'] ?? '';
    final recordKey = request.uri.queryParameters['rk'] ?? '';
    final idx = request.uri.queryParameters['idx'] ?? '0';

    final keyPath = p.join(dir, 'key_' + idx + '.key');
    final keyFile = File(keyPath);

    final session = _sessions[recordKey];
    final keyHeaders = session?.httpHeaders ?? const <String, String>{};

    if (await keyFile.exists() && await keyFile.length() > 0) {
      final bytes = await keyFile.readAsBytes();
      response.headers.contentType = ContentType('application', 'octet-stream');
      response.add(bytes);
      await response.close();
      return;
    }

    final future = _inFlightKeys[keyPath] ??=
        _downloadAndSave(src, keyPath, recordKey, headers: keyHeaders);
    try {
      final bytes = await future;
      response.headers.contentType = ContentType('application', 'octet-stream');
      response.add(bytes);
    } catch (e) {
      response.statusCode = HttpStatus.badGateway;
      response.write('key download failed');
    } finally {
      _inFlightKeys.remove(keyPath);
      await response.close();
    }
  }

  Future<List<int>> _downloadAndSave(
      String src, String savePath, String recordKey,
      {Map<String, String> headers = const <String, String>{}}) {
    // 播放代理与 DownloadManager 会并发下载同一个分片/密钥：走协调器
    // 互斥下载（同源地址同一时刻只拉一次）+ 唯一临时文件 + 带重试的
    // 发布，避免 Windows 下 rename 撞上正在被读取的目标文件（errno 32）。
    return SegmentWriteCoordinator.instance.runExclusive(savePath, () async {
      final tmpPath = SegmentWriteCoordinator.instance.uniqueTempPath(savePath);
      try {
        await DownloadHttpClient.instance.download(
          src,
          tmpPath,
          headers: headers,
        );
        await SegmentWriteCoordinator.instance
            .publish(tmpPath: tmpPath, savePath: savePath);
      } catch (e) {
        try {
          final tmp = File(tmpPath);
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {
          // 静默可接受：临时文件清理属 best-effort，失败不影响主流程
        }
        SegmentWriteCoordinator.instance.releaseTempPath(tmpPath);
        rethrow;
      }
      final bytes = await File(savePath).readAsBytes();
      _markSegmentDownloaded(recordKey);
      return bytes;
    });
  }

  void _markSegmentDownloaded(String recordKey) {
    final session = _sessions[recordKey];
    if (session == null) return;
    // 统计目录中已落盘分片数
    _countDownloadedSegments(session);
  }

  Future<void> _countDownloadedSegments(PlaybackProxySession session) async {
    final dir = Directory(session.episodeDir);
    var count = 0;
    if (await dir.exists()) {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isNotEmpty
            ? Uri.decodeComponent(entity.uri.pathSegments.last)
            : entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('seg_') && name.endsWith('.ts')) {
          try {
            if (await entity.length() > 0) count++;
          } catch (_) {
            // 静默可接受：分片可能正被并发写入/删除，stat 失败仅影响进度计数
          }
        }
      }
    }
    session.downloadedSegments = count;
    onProgress?.call(
        session.recordKey, session.episodeNumber, count, session.totalSegments);
  }

  // ---------- mp4 直链：Range 转发 + 追加落盘 ----------

  Future<void> _handleMp4(HttpRequest request, HttpResponse response) async {
    final src = request.uri.queryParameters['src'] ?? '';
    final dir = request.uri.queryParameters['dir'] ?? '';
    final hdrsJson = request.uri.queryParameters['hdrs'] ?? '{}';
    final recordKey = request.uri.queryParameters['rk'] ?? '';
    if (src.isEmpty || dir.isEmpty) {
      response.statusCode = HttpStatus.badRequest;
      await response.close();
      return;
    }

    Map<String, dynamic> headers = {};
    try {
      headers = jsonDecode(hdrsJson) as Map<String, dynamic>;
    } catch (e) {
      WywLogger().d(
          '${LogTag.download} hdrs JSON 解析失败，使用空 headers rk=$recordKey',
          error: e);
    }

    final mp4Path = p.join(dir, 'video.mp4');
    final file = File(mp4Path);
    await file.create(recursive: true);

    final rangeHeader = request.headers.value('range');
    final bool isRangeRequest =
        rangeHeader != null && rangeHeader.startsWith('bytes=');

    // 播放器请求的字节起点（缺省从头开始）。
    int requestedStart = 0;
    if (isRangeRequest) {
      requestedStart =
          int.tryParse(rangeHeader.substring(6).split('-').first) ?? 0;
    }

    // 本地已落盘长度。mp4 代理始终以「追加到 EOF」方式落盘：
    //  - 已落盘的 [0, fileLen) 内容是连续、有效的；
    //  - 源站续传永远从 EOF 开始，保证磁盘文件连续、无空洞/错位。
    int fileLen = 0;
    if (await file.exists()) {
      try {
        fileLen = await file.length();
      } catch (e) {
        WywLogger().d('${LogTag.download} 读取 video.mp4 已落盘长度失败，按 0 续传 src=$src',
            error: e);
      }
    }

    try {
      final stream = await DownloadHttpClient.instance.getStream(
        src,
        headers: {
          ...headers,
          'Range': 'bytes=' + fileLen.toString() + '-',
        },
      );
      final totalStr = stream.data?.headers['content-range']?.toString() ?? '';
      // content-range: bytes 0-999/1000
      final slashIdx = totalStr.lastIndexOf('/');
      final totalBytes = slashIdx > 0
          ? int.tryParse(totalStr.substring(slashIdx + 1).trim()) ?? 0
          : 0;

      // 服务器忽略 Range（返回 200 全文）时，若本地已有字节，直接失败，
      // 避免把整段内容重复追加进 video.mp4 破坏已落盘的播放进度。
      if (fileLen > 0 &&
          totalStr.isEmpty &&
          (stream.statusCode ?? 0) != HttpStatus.partialContent) {
        response.statusCode = HttpStatus.badGateway;
        response.write('server ignored range request');
        WywLogger().e('${LogTag.download} 源站忽略 Range，拒绝追加重复字节 '
            'src=$src fileLen=$fileLen');
        await response.close();
        return;
      }

      response.statusCode =
          isRangeRequest ? HttpStatus.partialContent : HttpStatus.ok;
      response.headers.set('Content-Type', 'video/mp4');
      response.headers.set('Accept-Ranges', 'bytes');
      if (isRangeRequest) {
        response.headers.set(
            'Content-Range',
            'bytes ' +
                requestedStart.toString() +
                '-' +
                (totalBytes > 0 ? (totalBytes - 1).toString() : '') +
                '/' +
                totalBytes.toString());
      }

      // 播放器请求起点早于 EOF（回退/跳转到已下载区间）：
      // 先从本地文件回读 [requestedStart, fileLen)，再继续向源站续传，
      // 保证响应内容与请求的 Range 完全一致。
      if (requestedStart < fileLen) {
        final raf = await file.open(mode: FileMode.read);
        try {
          await raf.setPosition(requestedStart);
          while (true) {
            final chunk = await raf.read(64 * 1024);
            if (chunk.isEmpty) break;
            response.add(chunk);
          }
        } finally {
          await raf.close();
        }
      }

      final raf = await file.open(mode: FileMode.append);
      try {
        // 当前写指针始终从 EOF 增长；
        // 当 requestedStart > fileLen（向前跳转到未下载区间）时，
        // [fileLen, requestedStart) 的字节只落盘不转发（预填空洞），
        // 之后的内容从 requestedStart 起完整转发给播放器。
        int pos = fileLen;
        await for (final chunk in stream.data!.stream) {
          await raf.writeFrom(chunk);
          final chunkStart = pos;
          pos += chunk.length;
          if (chunkStart + chunk.length <= requestedStart) continue;
          final skip = requestedStart - chunkStart;
          if (skip > 0) {
            response.add(chunk.sublist(skip));
          } else {
            response.add(chunk);
          }
        }
        await response.close();
      } finally {
        await raf.close();
      }
      _markSegmentDownloaded(recordKey);
    } catch (e, s) {
      WywLogger()
          .e('${LogTag.download} mp4 代理转发失败 src=$src', error: e, stackTrace: s);
      response.statusCode = HttpStatus.badGateway;
      await response.close();
    }
  }

  /// 停止代理并清理会话。
  Future<void> stop() async {
    _sessions.clear();
    _inFlightSegments.clear();
    _inFlightKeys.clear();
    final server = _server;
    _server = null;
    _port = 0;
    if (server != null) {
      await server.close(force: true);
    }
  }
}
