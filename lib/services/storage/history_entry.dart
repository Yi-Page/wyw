import 'package:hive_ce/hive.dart';
import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/history_type.dart';

part 'history_entry.g.dart';

/// 应用自带资源进度记录（视频/小说/漫画等）
///
/// 字段最小化：
///   - 资源链接（sourceId）作为唯一标识
///   - 类型 + 标题 + 封面用于展示
///   - 上次观看时间用于排序
///   - 进度由各类型对应强类型进度类承载
///
/// 不含 pluginName —— 写入上下文由 Hive box 隔离，key 用 sourceId 即可。
@HiveType(typeId: 10)
class HistoryEntry {
  @HiveField(0)
  String sourceId;
  @HiveField(1)
  HistoryType type;
  @HiveField(2)
  String title;
  @HiveField(3, defaultValue: '')
  String cover;
  @HiveField(4)
  DateTime lastWatchTime;
  @HiveField(5)
  Map<String, dynamic> progress;

  HistoryEntry({
    required this.sourceId,
    required this.type,
    required this.title,
    required this.cover,
    required this.lastWatchTime,
    required this.progress,
  });

  String get key => sourceId;

  HistoryProgress parseProgress() => switch (type) {
        HistoryType.video => VideoPlaybackProgress.fromMap(progress),
        HistoryType.novel => ReadProgress.fromMap(progress),
        HistoryType.comic => ComicProgress.fromMap(progress),
        HistoryType.custom => CustomProgress(progress),
      };
}
