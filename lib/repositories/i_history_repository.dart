import 'package:wyw/services/storage/history_entry.dart';
import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/history_type.dart';

/// v2 历史记录数据访问接口
///
/// 设计：sourceId 作为唯一标识（资源链接天然唯一），不再带 pluginName。
abstract class IHistoryRepository {
  Future<HistoryEntry> open({
    required HistoryType type,
    required String sourceId,
    required String title,
    String? cover,
  });

  Future<void> setProgress({
    required HistoryType type,
    required String sourceId,
    String title = '',
    String cover = '',
    required Map<String, dynamic> progress,
  });

  Future<void> flush({
    required HistoryType type,
    required String sourceId,
    required String title,
    required String cover,
  });

  HistoryEntry? find({
    required HistoryType type,
    required String sourceId,
  });

  HistoryProgress parseProgress(HistoryEntry e);

  List<HistoryEntry> getAll();

  /// 写入落盘后的变更通知（setProgress / flush / remove / restore / clearAll）。
  ///
  /// 后端是共享 Hive box，因此指向同一 box 的多个仓库实例会一起收到通知；
  /// UI 层订阅它即可在播放/阅读页写进度后自动重拉，无需在返回时手动刷新。
  Stream<void> get changes;

  Future<void> remove({
    required HistoryType type,
    required String sourceId,
  });

  /// 撤销删除：把条目原样放回（保留原 lastWatchTime 与进度）。
  Future<void> restore(HistoryEntry entry);

  Future<void> clearAll();

  bool getPrivateMode();
}
