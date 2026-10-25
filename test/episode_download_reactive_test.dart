import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/pages/download/download_controller.dart';
import 'package:wyw/pages/video/episode_selection_panel.dart';
import 'package:wyw/repositories/download_repository.dart';
import 'package:wyw/services/download/download_manager.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/services/storage/video_play_model.dart';

/// 「缓存信息必须是**动态**的」回归。
///
/// 依赖链藏得很深：面板不直接读 `DownloadController.records`，而是经
/// `episodeDownloadsFor(code)` → `findRecordByCode` **迭代**那个
/// `ObservableList`（迭代会 `reportObserved()`）。因此：
///   - 取任务的调用**必须**发生在 `Observer` 的 builder 内（订阅才成立）；
///   - 若在 `Observer` 之外算一份快照再传进去（sheet 的 builder 只跑一次，
///     很容易写成这样），面板就会永远停在打开那一刻的状态。
///
/// 后半段那条"反面样本"用例就是这个陷阱的复现：它**必须**保持静态。
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late DownloadController controller;

  const code = 'jm:1';

  VideoPlaySource road() => VideoPlaySource(
        name: '线路A',
        episodes: [
          VideoPlayEpisode(
            name: '第1集',
            path: const PlayResourcePath(
              url: 'https://n/1.m3u8',
              type: PlayPathType.direct,
            ),
          ),
        ],
      );

  Future<void> pumpPanel(
    WidgetTester tester, {
    required Map<String, DownloadEpisode> Function() downloadsOf,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 640,
          child: Observer(
            builder: (context) => EpisodeSelectionPanel(
              title: '测试剧',
              roads: [road()],
              selectedRoad: 0,
              selectedEpisode: 0,
              onEpisodeSelected: (_, __) {},
              downloads: downloadsOf(),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// 造一个「解析中」任务（会落盘 + 刷新 records）。
  Future<void> prepare(WidgetTester tester) async {
    await tester.runAsync(() async {
      await controller.prepareStructuredEpisode(
        code: code,
        sourceKey: 'jm',
        videoId: '1',
        title: '测试剧',
        cover: '',
        sourceIndex: 0,
        episodeIndex: 0,
        episodeName: '第1集',
        sourceName: '线路A',
      );
    });
    await tester.pumpAndSettle();
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wyw_download_reactive');
    Hive.init(tempDir.path);
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    // 设置箱用内存箱：widget 测试的假时钟里真实文件 I/O 的回调不会自己跑完。
    await Hive.openBox<dynamic>('setting', bytes: Uint8List(0));
    await GStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    // Hive box 在用例之间是共享的：先清空，避免上一条用例的下载记录污染面板。
    await GStorage.downloads.clear();
    controller = DownloadController(DownloadRepository(), DownloadManager());
    // 面板的依赖就是这个 records 列表：必须先装载（应用里由 InitPage 调用）。
    await controller.init();
  });

  testWidgets('在 Observer 内取任务 → 下载状态变化即时反映到面板', (tester) async {
    await pumpPanel(
      tester,
      downloadsOf: () => controller.episodeDownloadsFor(code: code),
    );
    expect(find.byIcon(Icons.download_outlined), findsOneWidget); // 未缓存

    await prepare(tester);
    expect(find.byIcon(Icons.downloading_rounded), findsOneWidget);
    expect(find.textContaining('正在解析'), findsOneWidget);

    // 解析失败是走 _refreshRecord（index 写入）那条路，最能暴露订阅缺失
    await tester.runAsync(() async {
      await controller.failPreparedEpisode(
        code: code,
        sourceIndex: 0,
        episodeIndex: 0,
        message: '解析播放地址失败',
      );
    });
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.textContaining('缓存失败'), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsNothing);
  });

  testWidgets('反面样本：任务取在 Observer 外（快照）会静默变静态', (tester) async {
    final snapshot = controller.episodeDownloadsFor(code: code);
    await pumpPanel(tester, downloadsOf: () => snapshot);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);

    await prepare(tester);

    // 快照没变 → 面板仍显示未缓存。这正是"sheet 的 builder 只跑一次"
    // 时踩到的坑，所以取任务必须放在 Observer 内。
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    expect(find.byIcon(Icons.downloading_rounded), findsNothing);
  });
}
