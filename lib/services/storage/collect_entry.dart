import 'package:hive_ce/hive.dart';
import 'package:wyw/services/storage/collect_type.dart';

part 'collect_entry.g.dart';

/// 收藏条目（= 插件浏览足迹 + 收藏状态）
///
/// 持久化：Hive box `collectibles`（见 [CollectRepository]）。
///
/// 模型边界：
///   - 不假设 url 存在——插件完全自由定义 [kv] schema
///   - 应用层只管存读 + 通知插件"用户点了 id"
///   - 回放路径由插件在自己的 `openBrowseEntry(id)` 实现里决定
///
/// 字段说明：
///   - id：插件保证唯一（任意形式：URL hash、复合字符串等）
///   - title / cover：用于卡片显示
///   - kv：完全自由 K/V，可包含 detailUrl / playUrl / 自定义状态等
///   - visitTime：最近一次被插件收录（`PluginBrowse.open`）的时间
///   - collectType：收藏状态，**用户所有、插件不可写**，默认 [CollectType.none]
///   - collectedAt：最近一次收藏动作时间（"最近变更"排序用）
///
/// ⚠ `typeId` 必须全局唯一：已占用 7（DownloadEpisode）、8（DownloadRecord）、
/// 10（HistoryEntry）、11（HistoryType，手写在 `history_type.g.dart`）。
/// 唯一性由 `test/hive_type_id_test.dart` 守护（重复注册会在启动时抛
/// `HiveError: There is already a TypeAdapter for typeId N`）。
@HiveType(typeId: 12)
class CollectEntry {
  @HiveField(0)
  String pluginName;
  @HiveField(1)
  String id;
  @HiveField(2)
  String title;
  @HiveField(3, defaultValue: '')
  String cover;
  @HiveField(4)
  DateTime visitTime;
  @HiveField(5, defaultValue: {})
  Map<String, dynamic> kv;

  /// 收藏状态数值，见 [CollectType]；默认 0（未收藏）。
  @HiveField(6, defaultValue: 0)
  int collectType;

  /// 收藏动作时间；未收藏时为 null。
  @HiveField(7)
  DateTime? collectedAt;

  CollectEntry({
    required this.pluginName,
    required this.id,
    required this.title,
    required this.cover,
    required this.visitTime,
    required this.kv,
    this.collectType = 0,
    this.collectedAt,
  });

  /// 数据键：`pluginName::id`（对外语义；Hive 内部另有定长哈希键）。
  String get key => '$pluginName::$id';

  /// 当前收藏状态的强类型视图。
  CollectType get type => CollectType.fromValue(collectType);

  /// 合并写入：只更新插件可写的展示字段与访问时间，
  /// **绝不覆盖用户所有的收藏状态**（[collectType] / [collectedAt]）。
  CollectEntry mergeFromPlugin({
    required String title,
    required String cover,
    required Map<String, dynamic> kv,
    required DateTime visitTime,
  }) {
    return CollectEntry(
      pluginName: pluginName,
      id: id,
      title: title,
      cover: cover,
      visitTime: visitTime,
      kv: kv,
      collectType: collectType,
      collectedAt: collectedAt,
    );
  }

  /// 设置收藏状态：切换到已收藏时刷新 [collectedAt]，切回未收藏时清空。
  CollectEntry withCollectType(CollectType type, {DateTime? now}) {
    return CollectEntry(
      pluginName: pluginName,
      id: id,
      title: title,
      cover: cover,
      visitTime: visitTime,
      kv: kv,
      collectType: type.value,
      collectedAt: type.isCollected ? (now ?? DateTime.now()) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'pluginName': pluginName,
        'id': id,
        'title': title,
        'cover': cover,
        'visitTime': visitTime.toIso8601String(),
        'kv': kv,
        'collectType': collectType,
        'collectedAt': collectedAt?.toIso8601String(),
      };

  /// 从 JSON 还原（兼容旧 `plugin_history.json`：缺收藏字段即未收藏）。
  factory CollectEntry.fromJson(Map<String, dynamic> m) => CollectEntry(
        pluginName: m['pluginName'] as String,
        id: m['id'] as String,
        title: m['title'] as String,
        cover: (m['cover'] as String?) ?? '',
        visitTime: DateTime.parse(m['visitTime'] as String),
        kv: (m['kv'] as Map?)?.cast<String, dynamic>() ?? const {},
        collectType: (m['collectType'] as num?)?.toInt() ?? 0,
        collectedAt: m['collectedAt'] == null
            ? null
            : DateTime.tryParse(m['collectedAt'] as String),
      );
}
