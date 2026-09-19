/// 插件浏览历史条目
///
/// 持久化：JSON 文件（见 [PluginHistoryRepository]）。
///
/// 模型边界：
///   - 不假设 url 存在——插件完全自由定义 [kv] schema
///   - 应用层只管存读 + 通知插件"用户点了 id"
///   - 回放路径由插件在自己的 `openBrowseEntry(id)` 实现里决定
///
/// 字段说明：
///   - id：插件保证唯一（任意形式：URL hash、复合字符串等）
///   - title / cover：用于历史卡片显示
///   - kv：完全自由 K/V，可包含 detailUrl / playUrl / 自定义状态等
class PluginHistoryEntry {
  final String pluginName;
  final String id;
  final String title;
  final String cover;
  final DateTime visitTime;
  final Map<String, dynamic> kv;

  PluginHistoryEntry({
    required this.pluginName,
    required this.id,
    required this.title,
    required this.cover,
    required this.visitTime,
    required this.kv,
  });

  String get key => '$pluginName::$id';

  Map<String, dynamic> toJson() => {
        'pluginName': pluginName,
        'id': id,
        'title': title,
        'cover': cover,
        'visitTime': visitTime.toIso8601String(),
        'kv': kv,
      };

  factory PluginHistoryEntry.fromJson(Map<String, dynamic> m) =>
      PluginHistoryEntry(
        pluginName: m['pluginName'] as String,
        id: m['id'] as String,
        title: m['title'] as String,
        cover: (m['cover'] as String?) ?? '',
        visitTime: DateTime.parse(m['visitTime'] as String),
        kv: (m['kv'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}
