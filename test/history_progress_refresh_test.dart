import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:wyw/pages/history/history_controller.dart';
import 'package:wyw/repositories/history_repository.dart';
import 'package:wyw/services/storage/history_entry.dart';
import 'package:wyw/services/storage/history_type.dart';

/// 回归：从历史页进入播放/观看后，进度写盘要能实时反映到历史列表。
///
/// 曾经的行为是 [HistoryController.init] 只在页面 initState 里拉一次快照，
/// 而播放页写进度只落 Hive、不通知任何订阅方 —— 于是从播放页返回时
/// 列表仍是旧进度，必须离开页面重进才刷新。
void main() {
  late Directory dir;
  late Box<HistoryEntry> box;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('wyw_history_refresh');
    Hive.init(dir.path);
    // 与 lib/services/storage/storage.dart 的注册保持一致。
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(HistoryEntryAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(HistoryTypeAdapter());
    }
    box = await Hive.openBox<HistoryEntry>('histories_refresh_test');
  });

  tearDownAll(() async {
    await box.close();
    await Hive.close();
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  });

  setUp(() => box.clear());

  /// setProgress 有 200ms 落盘节流，留足窗口让 box 变更事件送达。
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 350));

  test('播放页写进度后，控制器无需重进页面即可拿到新进度', () async {
    final repo = HistoryRepository(box: box);
    final controller = HistoryController(repo);
    controller.init();
    expect(controller.histories, isEmpty);

    await repo.setProgress(
      type: HistoryType.video,
      sourceId: 'https://example.com/video-1',
      title: '测试视频',
      progress: const {
        'videoUrl': 'https://example.com/video-1',
        'positionMs': 1000,
        'durationMs': 10000,
      },
    );
    await settle();
    expect(controller.histories, hasLength(1));
    expect(controller.histories.single.progress['positionMs'], 1000);

    // 继续播放 → 同一 sourceId 覆盖写，列表应更新而不是新增一条。
    await repo.setProgress(
      type: HistoryType.video,
      sourceId: 'https://example.com/video-1',
      title: '测试视频',
      progress: const {
        'videoUrl': 'https://example.com/video-1',
        'positionMs': 6000,
        'durationMs': 10000,
      },
    );
    await settle();
    expect(controller.histories, hasLength(1));
    expect(controller.histories.single.progress['positionMs'], 6000);

    controller.dispose();
  });

  test('其他仓库实例写入（init_page / JS 引擎）同样能刷新控制器', () async {
    // 订阅方只持有 core_module 的单例；init_page 与 production_script_engine
    // 各自 new 了一个 HistoryRepository，但都指向同一个 box。
    final singletonRepo = HistoryRepository(box: box);
    final controller = HistoryController(singletonRepo);
    controller.init();

    final otherWriter = HistoryRepository(box: box);
    await otherWriter.setProgress(
      type: HistoryType.comic,
      sourceId: 'pluginA:comic-9',
      title: '测试漫画',
      progress: const {'lastChapterIndex': 3, 'lastPage': 12},
    );
    await settle();

    expect(controller.histories, hasLength(1));
    expect(controller.histories.single.sourceId, 'pluginA:comic-9');
    expect(controller.histories.single.progress['lastChapterIndex'], 3);

    controller.dispose();
  });

  test('删除与清空同样实时反映到控制器', () async {
    final repo = HistoryRepository(box: box);
    final controller = HistoryController(repo);
    controller.init();

    await repo.setProgress(
      type: HistoryType.video,
      sourceId: 'v2',
      title: '待删除',
      progress: const {'positionMs': 5, 'durationMs': 10},
    );
    await settle();
    expect(controller.histories, hasLength(1));

    await repo.remove(type: HistoryType.video, sourceId: 'v2');
    await settle();
    expect(controller.histories, isEmpty);

    await repo.setProgress(
      type: HistoryType.video,
      sourceId: 'v3',
      title: '待清空',
      progress: const {'positionMs': 5, 'durationMs': 10},
    );
    await settle();
    expect(controller.histories, hasLength(1));

    await repo.clearAll();
    await settle();
    expect(controller.histories, isEmpty);

    controller.dispose();
  });
}
