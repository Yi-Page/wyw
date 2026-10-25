import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:wyw/hive_registrar.g.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/services/storage/collect_entry.dart';
import 'package:wyw/services/storage/history_entry.dart';
import 'package:wyw/services/storage/history_type.dart';

/// Hive `typeId` 唯一性 guard。
///
/// 重复的 typeId 在**编译期与单测里都看不出来**，只有真机启动调用
/// `Hive.registerAdapters()` 时才抛
/// `HiveError: There is already a TypeAdapter for typeId N`（存储初始化直接失败，
/// 应用落到 StorageErrorPage）。这条用例把冲突拦在提交前。
///
/// 新增 @HiveType 时：挑一个没被占用的 id，并把期望集合一起更新。
void main() {
  test('所有 Hive 适配器的 typeId 互不重复', () {
    final adapters = <TypeAdapter<dynamic>>[
      CollectEntryAdapter(),
      HistoryEntryAdapter(),
      DownloadEpisodeAdapter(),
      DownloadRecordAdapter(),
      HistoryTypeAdapter(),
    ];

    final ids = adapters.map((a) => a.typeId).toList();
    expect(
      ids.toSet().length,
      ids.length,
      reason: 'typeId 冲突：$ids',
    );
  });

  test('已占用的 typeId 集合与预期一致（改 id 时必须同步更新这里）', () {
    expect(
      <int>{
        CollectEntryAdapter().typeId,
        HistoryEntryAdapter().typeId,
        DownloadEpisodeAdapter().typeId,
        DownloadRecordAdapter().typeId,
        HistoryTypeAdapter().typeId,
      },
      <int>{7, 8, 10, 11, 12},
    );
  });

  test('按 GStorage.init 的顺序真实注册不抛异常（启动崩溃的复现用例）', () {
    // GStorage.init() 的两步：registerAdapters() 之后单独注册 HistoryTypeAdapter。
    // 历史 bug：CollectEntry 用了 HistoryType 已占用的 typeId 11，
    // 第二步直接抛 HiveError，存储初始化失败 → StorageErrorPage。
    Hive.registerAdapters();
    Hive.registerAdapter(HistoryTypeAdapter());
  });
}
