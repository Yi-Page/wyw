import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/collect_entry.dart';
import 'package:wyw/services/storage/collect_type.dart';
import 'package:wyw/services/storage/storage.dart';

/// 收藏仓库（= 插件浏览足迹 + 收藏状态），Hive 后端
///
/// 与 `HistoryRepository`（应用自带进度历史，Hive `histories`）**完全独立**：
///   - 写入方：JS 插件（`PluginBrowse.open` → JS 桥）+ 用户在收藏页管理
///   - schema：`kv` 完全自由（plugin 自定义）
///   - 持久化：Hive box `collectibles`（单条 put/delete；旧版本为 JSON 文件，
///     首次启动做一次性导入，老文件保留作备份）
///
/// 内部约定：
///   - `upsert` 是**合并**语义：只更新插件可写的展示字段与 `visitTime`，
///     绝不覆盖用户所有的 `collectType` / `collectedAt`。
///   - 删除就是删除整条浏览历史（收藏状态随条目一起消失）；插件再次
///     `upsert` 会以「未收藏」重建一条。
///   - UI 层订阅 [changes] 自动重拉。
class CollectRepository {
  CollectRepository({
    Box<CollectEntry>? box,
    bool Function()? privateModeReader,
    int Function()? uncollectedLimitReader,
  })  : _box = box,
        _privateModeReader = privateModeReader ?? (() => false),
        _uncollectedLimitReader = uncollectedLimitReader;

  Box<CollectEntry>? _box;
  bool Function() _privateModeReader;
  final int Function()? _uncollectedLimitReader;

  /// 旧 JSON 后端的一次性迁移标记（幂等）。
  static const String migratedFlag = 'collect_migrated_hive';

  Box<CollectEntry> get _entries {
    // 懒回退：即使 init() 尚未调用（例如插件在启动早期就调用 PluginBrowse），
    // 也能拿到 box（GStorage.init() 在 runApp 之前完成）。
    return _box ??= GStorage.collectibles;
  }

  /// 绑定存储（应用启动时调用；测试可直接经构造参数注入 box）。
  void init() {
    _box ??= GStorage.collectibles;
    _privateModeReader = (() => false);
  }

  bool getPrivateMode() => _privateModeReader();

  /// box 级变更流：任何一次写入（upsert / 状态变更 / 删除 / 清理）都会触发。
  Stream<void> get changes => _entries.watch().map<void>((_) {});

  // ===== 键 =====

  /// Hive 的 String key 上限是 255 字符，而 `pluginName::id` 可能很长
  /// （插件常用 URL hash）。统一映射为 sha256 十六进制（64 字符，稳定且
  /// 不会超长）；完整 `pluginName` / `id` 仍存在条目字段里。
  String _keyFor(String pluginName, String id) =>
      sha256.convert(utf8.encode('$pluginName::$id')).toString();

  /// 按业务键读取条目：先查哈希 key，再全表扫描兜底（哈希冲突几乎不可能）。
  CollectEntry? _getByKey(String pluginName, String id) {
    final box = _entries;
    final hashed = box.get(_keyFor(pluginName, id));
    if (hashed != null &&
        hashed.pluginName == pluginName &&
        hashed.id == id) {
      return hashed;
    }
    for (final entry in box.values) {
      if (entry.pluginName == pluginName && entry.id == id) return entry;
    }
    return null;
  }

  // ===== 写操作 =====

  /// 合并 upsert（插件调用 `PluginBrowse.open` 时写入）。
  ///
  /// 只更新 `title` / `cover` / `kv` / `visitTime`：
  ///   - 条目已存在 → 保留 `collectType` / `collectedAt`（用户的收藏状态）
  ///   - 条目不存在 → 以 [CollectType.none]（未收藏）创建
  Future<void> upsert({
    required String pluginName,
    required String id,
    required String title,
    String? cover,
    Map<String, dynamic>? kv,
  }) async {
    if (id.isEmpty) {
      throw ArgumentError('id must not be empty');
    }
    if (pluginName.isEmpty) {
      throw ArgumentError('pluginName must not be empty');
    }
    if (getPrivateMode()) return;
    final existing = _getByKey(pluginName, id);
    final merged = existing == null
        ? CollectEntry(
            pluginName: pluginName,
            id: id,
            title: title.isEmpty ? id : title,
            cover: cover ?? '',
            visitTime: DateTime.now(),
            kv: kv ?? const {},
          )
        : existing.mergeFromPlugin(
            title: title.isEmpty ? id : title,
            cover: cover ?? '',
            kv: kv ?? const {},
            visitTime: DateTime.now(),
          );
    await _entries.put(_keyFor(pluginName, id), merged);
    await enforceUncollectedLimit();
  }

  /// 设置收藏状态（用户在收藏页/卡片菜单里操作）。
  ///
  /// 条目不存在时不做任何事（收藏只作用于已有的浏览足迹）。
  Future<void> setCollectType({
    required String pluginName,
    required String id,
    required CollectType type,
  }) async {
    if (getPrivateMode()) return;
    final existing = _getByKey(pluginName, id);
    if (existing == null) return;
    await _entries.put(
      _keyFor(pluginName, id),
      existing.withCollectType(type),
    );
    await enforceUncollectedLimit();
  }

  /// 单条删除（= 删除整条浏览历史，收藏状态随之消失）。
  Future<void> remove({
    required String pluginName,
    required String id,
  }) async {
    if (getPrivateMode()) return;
    await _entries.delete(_keyFor(pluginName, id));
    // 兼容早期以业务键直接写入的数据
    for (final key in _entries.keys.toList()) {
      final entry = _entries.get(key);
      if (entry != null &&
          entry.pluginName == pluginName &&
          entry.id == id &&
          key != _keyFor(pluginName, id)) {
        await _entries.delete(key);
      }
    }
  }

  /// 恢复（撤销删除）：把条目原样放回（保留原 visitTime 与收藏状态）。
  ///
  /// **同 key 冲突处理**：撤销窗口是"收藏页整页生命周期"，期间插件可能已经
  /// 重新 `upsert` 过同一条目（详情页的「相关推荐」可以跳到另一个 `getDetail`）。
  /// 此时直接覆盖会让访问时间倒退、并抹掉期间设置的收藏状态，因此改为：
  ///   - 同 key 不存在 → 原样放回（保留快照的 visitTime / 收藏状态）
  ///   - 同 key 已存在 → 保留**较新的插件字段**，仅当现存条目是「未收藏」而快照
  ///     是「已收藏」时补回收藏状态（收藏时间沿用快照）
  Future<void> restore(CollectEntry entry) async {
    final existing = _getByKey(entry.pluginName, entry.id);
    if (existing == null) {
      await _entries.put(_keyFor(entry.pluginName, entry.id), entry);
      return;
    }
    final merged = (!existing.type.isCollected && entry.type.isCollected)
        ? existing.withCollectType(entry.type, now: entry.collectedAt)
        : existing;
    await _entries.put(_keyFor(entry.pluginName, entry.id), merged);
  }

  /// 清空全部。
  Future<void> clearAll() async {
    await _entries.clear();
  }

  /// 清空「未收藏」条目（保留已收藏）。
  Future<void> clearUncollected() async {
    final uncollected = _entries.values
        .where((e) => !e.type.isCollected)
        .toList();
    if (uncollected.isEmpty) return;
    await _entries.deleteAll(
      [for (final e in uncollected) _keyFor(e.pluginName, e.id)],
    );
  }

  /// 未收藏条目的保留上限：0（或未设置）= 无上限。
  int get uncollectedLimit =>
      _uncollectedLimitReader?.call() ??
      GStorage.getSetting(SettingsKeys.uncollectedLimit);

  /// 按设置清理「未收藏」条目（超出上限时按 `visitTime` 最旧优先清除）。
  ///
  /// **已收藏条目永不参与自动清理。**
  Future<int> enforceUncollectedLimit() async {
    final limit = uncollectedLimit;
    if (limit <= 0) return 0;
    final uncollected = _entries.values
        .where((e) => !e.type.isCollected)
        .toList()
      ..sort((a, b) => b.visitTime.compareTo(a.visitTime));
    if (uncollected.length <= limit) return 0;
    final doomed = uncollected.sublist(limit);
    await _entries.deleteAll(
      [for (final e in doomed) _keyFor(e.pluginName, e.id)],
    );
    return doomed.length;
  }

  // ===== 读操作 =====

  /// 同步查单条（box 常驻内存，无 IO）。
  CollectEntry? findSync({required String pluginName, required String id}) =>
      _getByKey(pluginName, id);

  /// 异步查单条（与 [findSync] 等价，保留旧调用方签名）。
  Future<CollectEntry?> find({
    required String pluginName,
    required String id,
  }) async =>
      _getByKey(pluginName, id);

  /// 查询某插件的全部记录（按 visitTime 倒序）。
  Future<List<CollectEntry>> getAllByPlugin(String pluginName) async {
    final list =
        _entries.values.where((e) => e.pluginName == pluginName).toList();
    list.sort((a, b) => b.visitTime.compareTo(a.visitTime));
    return list;
  }

  /// 全部记录（按 visitTime 倒序）。
  Future<List<CollectEntry>> getAll() async {
    final list = _entries.values.toList();
    list.sort((a, b) => b.visitTime.compareTo(a.visitTime));
    return list;
  }

  // ===== 迁移（旧 JSON → Hive，一次性）=====

  /// 若尚未迁移过，把旧 `plugin_history.json` 导入 Hive（幂等）。
  Future<void> migrateFromJsonIfNeeded() async {
    if (GStorage.getSettingByName(migratedFlag) == true) return;
    try {
      final file = File(GStorage.pluginHistoryFile);
      final imported = await importFromJsonFile(file);
      if (imported > 0) {
        WywLogger().i(
          '${LogTag.history} 收藏条目已从旧 JSON 导入 Hive count=$imported',
        );
      }
    } catch (e, s) {
      WywLogger().e(
        '${LogTag.history} 收藏条目迁移失败（保留旧文件，下次重试）',
        error: e,
        stackTrace: s,
      );
      return; // 不写标记：下次启动重试
    }
    await GStorage.putSettingByName(migratedFlag, true);
  }

  /// 从旧 JSON 文件导入条目（可单测）。
  ///
  /// - 本地已存在的条目**跳过**（本地是插件在迁移前刚写入的更新数据），
  ///   因此已有收藏状态与更"新"的展示字段都不会被旧 JSON 覆盖
  /// - 文件不存在 / 为空 → 返回 0
  Future<int> importFromJsonFile(File file) async {
    if (!await file.exists()) return 0;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return 0;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    var imported = 0;
    for (final m in list) {
      try {
        final parsed = CollectEntry.fromJson(m);
        if (_getByKey(parsed.pluginName, parsed.id) != null) continue;
        await _entries.put(_keyFor(parsed.pluginName, parsed.id), parsed);
        imported++;
      } catch (e) {
        // 单条失败不阻塞整体（与历史迁移一致的容错级别）
        WywLogger().d(
          '${LogTag.history} 旧 JSON 收藏条目导入失败（跳过）id=${m['id']}',
          error: e,
        );
      }
    }
    return imported;
  }
}
