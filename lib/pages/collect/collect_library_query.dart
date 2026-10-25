import 'package:wyw/services/storage/collect_entry.dart';
import 'package:wyw/services/storage/collect_type.dart';

/// 收藏页可用的排序方式。
///
/// 评分 / 开播时间排序不做：wyw 的条目里没有对应字段
/// （插件可写进 `kv`，宿主暂不读取）。
enum CollectSort {
  recentVisit('最近访问'),
  recentlyChanged('最近变更'),
  title('名称');

  const CollectSort(this.label);

  final String label;

  /// 该排序是否按日期分组。
  ///
  /// 名称排序没有日期语义，分组标题会与字母序冲突 → 不分组（平铺列表）。
  bool get groupsByDate => this != CollectSort.title;

  /// 分组用的日期键：**与排序主键一致**，因此同一日期分组在列表里必然连续。
  ///
  /// - 最近访问 → 条目的访问时间
  /// - 最近变更 → 收藏动作时间（未收藏条目回退到访问时间）
  /// - 名称 → 无日期语义（调用方不应分组；返回访问时间仅为兜底）
  DateTime groupTimeOf(CollectEntry entry) => switch (this) {
        CollectSort.recentVisit => entry.visitTime,
        CollectSort.recentlyChanged => entry.collectedAt ?? entry.visitTime,
        CollectSort.title => entry.visitTime,
      };
}

/// 收藏页的筛选 / 计数 / 排序查询。
///
/// 一份数据（全部浏览历史条目，含未收藏），7 个 tab：
/// `[全部, 未收藏, 在看, 想看, 看过, 搁置, 抛弃]`，其中 `type == null` 表示「全部」。
///
/// 除标题搜索外还有**插件分类筛选**：`allowedPlugins` 非空时只保留来自这些插件的
/// 条目（分类 → 插件名集合由页面在构建时换算），计数与结果都跟随该筛选。
class CollectLibraryQuery {
  CollectLibraryQuery(
    Iterable<CollectEntry> items,
    String query, {
    Set<String>? allowedPlugins,
  }) : _matches = _match(items, query, allowedPlugins);

  final List<CollectEntry> _matches;

  static List<CollectEntry> _match(
    Iterable<CollectEntry> items,
    String query,
    Set<String>? allowedPlugins,
  ) {
    final terms = query.trim().toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((t) => t.isEmpty);
    return items.where((entry) {
      if (allowedPlugins != null &&
          !allowedPlugins.contains(entry.pluginName)) {
        return false;
      }
      if (terms.isEmpty) return true;
      return terms.every(entry.title.toLowerCase().contains);
    }).toList();
  }

  /// 当前搜索词下某一 tab 的条目数；`type == null` 即「全部」（含未收藏）。
  int count(CollectType? type) => type == null
      ? _matches.length
      : _matches.where((e) => e.collectType == type.value).length;

  /// 当前搜索词下的总条目数。
  int get total => _matches.length;

  /// 某一 tab 的条目列表（已排序）。
  ///
  /// 排序键的兜底链照 Kazumi：主键相等时退化为时间倒序，再相等按数据键，
  /// 保证列表顺序稳定（不会在重建之间跳动）。
  List<CollectEntry> results(CollectType? type, CollectSort sort) {
    final result = _matches
        .where((e) => type == null || e.collectType == type.value)
        .toList();
    result.sort((a, b) {
      final comparison = switch (sort) {
        CollectSort.recentVisit => b.visitTime.compareTo(a.visitTime),
        CollectSort.recentlyChanged => _changedAt(b).compareTo(_changedAt(a)),
        CollectSort.title =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      };
      if (comparison != 0) return comparison;
      final byVisit = b.visitTime.compareTo(a.visitTime);
      return byVisit != 0 ? byVisit : a.key.compareTo(b.key);
    });
    return result;
  }

  static DateTime _changedAt(CollectEntry entry) =>
      entry.collectedAt ?? entry.visitTime;
}
