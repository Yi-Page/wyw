import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/pages/download/download_controller.dart';
import 'package:wyw/repositories/download_repository.dart';
import 'package:wyw/services/download/download_manager.dart';
import 'package:wyw/services/download/playback_proxy_service.dart';
import 'package:wyw/services/storage/storage.dart';

/// 「挂代理前必须判型」的回归。
///
/// `maybeStartProxyForPlaybackByIdentity` 是挂代理的**唯一咽喉**：明确选合流走它，
/// 在线播放的"静默挂靠"也走它。整段媒体（mp4 直链）挂上代理只会让播放器拿到一个
/// 打不开的地址（代理只有 HLS 通道），所以判型必须在这里拦，而不是只拦合流那条路。
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

/// 只提供判型需要的那两个源。
class _OriginServer {
  _OriginServer(this._server) {
    _server.listen((request) async {
      final response = request.response;
      if (request.uri.path == '/media.m3u8') {
        response.write('#EXTM3U\n#EXTINF:4.000,\nseg.ts\n#EXT-X-ENDLIST\n');
      } else if (request.uri.path == '/video.mp4') {
        response.add(List<int>.generate(2048, (i) => (i * 5 + 1) % 256));
      } else {
        response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
  }

  final HttpServer _server;

  int get port => _server.port;

  Future<void> close() => _server.close(force: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late DownloadController controller;
  late _OriginServer origin;
  final proxy = PlaybackProxyService.instance;

  const code = 'jm:1';
  const sourceIndex = 0;
  const episodeIndex = 0;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wyw_proxy_gate');
    Hive.init(tempDir.path);
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await Hive.openBox<dynamic>('setting', bytes: Uint8List(0));
    await GStorage.init();
    // TestWidgetsFlutterBinding 会把 HttpClient 换成"任何请求都返回 400"的假实现
    // （防止测试偷偷联网）。这里要真的连本地源站，所以把覆盖撤掉。
    HttpOverrides.global = null;
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await GStorage.downloads.clear();
    controller = DownloadController(DownloadRepository(), DownloadManager());
    await controller.init();
    origin = _OriginServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    await proxy.start();
  });

  tearDown(() async {
    await proxy.stop();
    await origin.close();
  });

  String src(String path) => 'http://127.0.0.1:${origin.port}$path';

  /// 造一条进行中的任务（预创建 → 就地补直链/状态，不真的入队下载）。
  Future<void> seedTask(String url, {int status = DownloadStatus.downloading}) async {
    await controller.prepareStructuredEpisode(
      code: code,
      sourceKey: 'jm',
      videoId: '1',
      title: '作品',
      cover: '',
      sourceIndex: sourceIndex,
      episodeIndex: episodeIndex,
      episodeName: '第1集',
      sourceName: '线路A',
    );
    final record = controller.findRecordByCode(code)!;
    final episode = record.episodes[
        structuredEpisodeNumber(sourceIndex, episodeIndex)]!;
    episode.networkM3u8Url = url;
    episode.status = status;
    // 目录直接给死，免得去读下载目录设置。
    episode.downloadDirectory = tempDir.path;
  }

  Future<String?> attach(String url) =>
      controller.maybeStartProxyForPlaybackByIdentity(
        code: code,
        sourceIndex: sourceIndex,
        episodeIndex: episodeIndex,
        resolvedUrl: url,
      );

  test('进行中的 mp4 任务：判型拦下，不挂代理（返回 null）', () async {
    await seedTask(src('/video.mp4'));
    expect(await attach(src('/video.mp4')), isNull);
  });

  test('进行中的 HLS 任务：正常返回代理 m3u8 地址', () async {
    await seedTask(src('/media.m3u8'));
    final url = await attach(src('/media.m3u8'));
    expect(url, isNotNull);
    expect(url, contains('/m3u8?'));
  });

  test('已完成 / 已暂停的任务本来就不挂代理', () async {
    await seedTask(src('/media.m3u8'), status: DownloadStatus.completed);
    expect(await attach(src('/media.m3u8')), isNull);
    await seedTask(src('/media.m3u8'), status: DownloadStatus.paused);
    expect(await attach(src('/media.m3u8')), isNull);
  });

  test('没有任务的一集：不挂代理（也不白跑判型）', () async {
    expect(await attach(src('/media.m3u8')), isNull);
  });
}
