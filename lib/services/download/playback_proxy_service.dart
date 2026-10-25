// ignore_for_file: prefer_interpolation_to_compose_strings

// 本地播放代理：实现「播放即下载」。
//
// 播放器请求走本代理（http://127.0.0.1:port/...），代理从源站拉取媒体数据，
// 同时把字节落盘到 DownloadManager 同一套下载目录与文件命名
// （seg_00000.ts / key_0.key），因此 DownloadManager 扫描「已存在分片」时会自动
// 跳过代理已落盘的分片 —— 每分片只会从源站拉取一次，播放与下载共用同一条网络流，
// 不产生双倍流量。
//
// **只支持 HLS 源**。合流要的是「播放进度即下载进度」，而进度能在两端共享，靠的是
// 分片序列（两端同一套 `seg_00000.ts` 命名 + SegmentWriteCoordinator 的路径互斥，
// 谁先拉谁落盘、另一个复用）。整段媒体（mp4 直链）没有分片，这条共享量根本不存在，
// 所以**不提供**它的合流通道：调用方先用
// [PlaybackProxyService.probeMediaKind] 判型，不是 HLS 就**不要**注册会话，改为
// 直链直接播放（见 `video_controller` 里的合流降级）。
//
// 判型只看**内容**不看 URL 后缀（有源把 `.mp4` 当目录名，见
// [classifyProxyMediaBytes]）；播放器一旦拿到与内容不匹配的地址就**直接打不开**，
// 所以判型必须在注册会话之前完成，而不是等 `/m3u8` 拉下来才发现不对。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wyw/request/clients/download_http_client.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/utils/http_headers.dart';
import 'package:wyw/utils/m3u8_parser.dart';
import 'package:wyw/utils/segment_file_coordinator.dart';

/// 代理模式进度回调：recordKey / episodeNumber / 已落盘分片数 / 总分片数
typedef ProxyProgressCallback = void Function(String recordKey,
    int episodeNumber, int downloadedSegments, int totalSegments);

/// 源的媒体类型判定结果（合流源**必须**是 HLS 播放列表）。
enum ProxyMediaKind {
  /// 判不出结论（探测失败、响应过短）。**不等于**"可以合流"——调用方按
  /// "不能合流"处理，因为挂上代理后拿到打不开的地址比直接播更糟。
  unknown,

  /// HLS 播放列表：唯一支持合流的源类型。
  hlsPlaylist,

  /// 整段媒体文件（mp4 直链等）：没有分片，不支持合流。
  singleFile,
}

/// 用响应首段字节判断这是 HLS 播放列表还是整段媒体文件。
///
/// **只看内容、不看 URL 后缀**：同一批源里 `…/1080P_4000K_x.mp4/index-v1-a1.m3u8`
/// 路径里带 `.mp4` 但其实是 TS 的 HLS（`.mp4` 只是它上一级目录名），反过来也有
/// 直链完全不带后缀。判定口径与下载端一致（下载端用 `_fetchM3u8` 撞
/// `_NotM3u8Exception` 再回退直链下载）：首段能认出 `#EXTM3U` 才算 HLS。
///
/// 首段不足 7 字节（`#EXTM3U` 的长度）返回 [ProxyMediaKind.unknown]：
/// 这时候往哪边猜都可能错，交给调用方决定怎么提示。
ProxyMediaKind classifyProxyMediaBytes(List<int> head) {
  if (head.length < 7) return ProxyMediaKind.unknown;
  // 播放列表是文本；首段可能切在多字节字符中间，用 allowMalformed 容错
  // （这里只拿它比 ASCII 前缀 `#EXTM3U`，容错不影响结论）。
  final text = utf8.decode(head, allowMalformed: true);
  return text.replaceFirst('\uFEFF', '').trimLeft().startsWith('#EXTM3U')
      ? ProxyMediaKind.hlsPlaylist
      : ProxyMediaKind.singleFile;
}

/// 单个「播放即下载」会话的上下文（一个会话就是一份 HLS 源）。
class PlaybackProxySession {
  final String recordKey;
  final int episodeNumber;

  /// HLS 播放列表地址（**调用方必须先用 [PlaybackProxyService.probeMediaKind]
  /// 确认过它是播放列表**，这里不再复查：整段媒体没有合流通道）。
  final String m3u8Url;

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
  ///
  /// **前置条件**：调用方已用 [probeMediaKind] 确认过这是 HLS 播放列表。
  /// 整段媒体（mp4 直链）没有合流通道，拿它的地址注册只会让播放器打不开。
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

  /// 拉取源站时用的默认请求头（随机 UA + 空 referer）。
  ///
  /// 判型与代理会话必须用**同一套**头：有 CDN 把签名绑在 UA 上，两处各随机一次
  /// 就可能出现"判型能看到、真拉却 403"的错判。
  static Map<String, String> defaultSourceHeaders() =>
      <String, String>{'user-agent': getRandomUA(), 'referer': ''};

  /// 判断这个源能不能作为合流源（**只有 HLS 播放列表可以**）。
  ///
  /// 只拉首段（最多 1KB，实际读到 64 字节就够）判型，原因见 [classifyProxyMediaBytes]。
  /// 任何异常都返回 [ProxyMediaKind.unknown]，绝不抛出：判型失败不该让播放跟着失败，
  /// 调用方按 unknown 走"降级为直链播放"，用户照样能看。
  ///
  /// 用 `Range` 只取开头是必须的：源站若忽略了 Range，这里读满 64 字节就
  /// `break` 主动断开，不会为了判型把一个几百 MB 的 mp4 拉完。
  Future<ProxyMediaKind> probeMediaKind(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final resp = await DownloadHttpClient.instance.getStream(
        url,
        headers: {
          ...(headers ?? defaultSourceHeaders()),
          'Range': 'bytes=0-1023',
        },
        receiveTimeout: const Duration(seconds: 10),
      );
      final bytes = <int>[];
      await for (final chunk in resp.data!.stream) {
        bytes.addAll(chunk);
        if (bytes.length >= 64) break;
      }
      return classifyProxyMediaBytes(bytes);
    } catch (e, s) {
      WywLogger().d('${LogTag.download} 合流源判型失败（按未知处理）url=$url',
          error: e, stackTrace: s);
      return ProxyMediaKind.unknown;
    }
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

    final session = _sessions[recordKey];

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
        // 判型说是播放列表、真拉下来却不是（源在探测之后换了内容，比如跟踪 URL
        // 或签名跳转）。合流只支持 HLS，这里已经没有可用的降级通道——整段媒体
        // 没有分片这条两端共享的进度量，所以明确失败并记日志，
        // 而不是把整段 mp4 当播放列表喂给播放器。
        WywLogger().e('${LogTag.download} 合流源不是 m3u8（判型与实际不符）'
            ' src=$src rk=$recordKey');
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

      // 广告过滤统一交给播放引擎（ffmpeg 的 hls_ad_filter）：代理只做地址重写，
      // 分片集合与顺序一律保持原样，且必须把 #EXT-X-DISCONTINUITY 写回去
      // （那是引擎侧过滤的启用条件）。代理按 idx=i 落盘 seg_<i>.ts，
      // 下载端也按同一份列表的位置落盘同名文件，两端索引空间保持一致。
      final List<M3u8Segment> segments = resolvedSegments;
      // 记录总分片数供进度显示（session 在方法开头取出，判型与进度共用同一份）
      session?.totalSegments = segments.length;
      final double targetDuration = playlist.targetDuration;

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
        // 分界线必须写回去：mpv/ffmpeg 侧的广告过滤（hls_ad_filter）靠这个标签
        // 才启用，抹掉它等于把播放器那道兜底一起关掉。
        if (i > 0 &&
            seg.discontinuityGroup != segments[i - 1].discontinuityGroup) {
          sb.writeln('#EXT-X-DISCONTINUITY');
        }
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
