import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:wyw/modules/danmaku/danmaku_episode_response.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/storage.dart';

/// 弹幕库**详情缓存**：按库 id 存 `DanmakuBangumiDetail` 的 JSON。
///
/// ## 为什么它存在，而不是把分集也写进进度记录
///
/// 进度记录每 5–15 秒就被整体重写一次（每次进度回调都会 `toMap()` 全量序列化，
/// 已经包含 `sources` 里每一集的直链/进度）。分集列表可达上千集（实测柯南主系列
/// 1372 集），把它塞进那个对象等于每次写都重新序列化一份大对象——纯浪费。
///
/// 所以职责拆开：
///   - **进度记录**（`VideoPlaybackProgress.danmaku`）只存**小快照 + 引用**：
///     库 id / 标题 / 封面 / 简介 / 评分 / 集数。它是"用户选了哪个库"的**事实源**；
///   - **本缓存**存重数据（分集列表、多语言标题、标签）。它是**可重建的派生数据**
///     ——内容全部来自 `/bangumi/{id}`，丢了只要重新拉一次。
///
/// 这样进场时：读进度记录拿引用 → 从缓存取分集 → **默认就能展示选集列表**，
/// 既不用网络、也不增加每次进度写入的成本。
class DanmakuLibraryCacheRepository {
  DanmakuLibraryCacheRepository({Box<String>? box}) : _boxOverride = box;

  /// 全局实例（懒取箱：构造时**不碰** `GStorage`，这样在没 `GStorage.init()`
  /// 的环境——比如 widget 测试——里拿实例本身也不会炸，只是读不到缓存）。
  static final DanmakuLibraryCacheRepository instance =
      DanmakuLibraryCacheRepository();

  /// 条目上限。缓存条目对应"用户选过弹幕库的作品"，正常远小于这个数；
  /// 设上限只是防止长期使用后无限增长（超出后按写入时间淘汰最旧的）。
  static const int maxEntries = 20;

  final Box<String>? _boxOverride;

  Box<String> get _box => _boxOverride ?? GStorage.danmakuLibraryCache;

  /// 读某个库的详情缓存；没有或已损坏返回 null（损坏的条目顺手清掉）。
  ///
  /// 整体包了 try/catch：箱子没初始化（测试环境）或磁盘数据坏掉时应当退化成
  /// "没有缓存"，而不是把弹幕面板整个炸掉。
  DanmakuBangumiDetail? read(String libraryId) {
    final key = _normalize(libraryId);
    if (key.isEmpty) return null;
    try {
      final raw = _box.get(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final detail = decoded['detail'];
      if (detail is! Map) return null;
      final parsed = DanmakuBangumiDetail.fromJson(
        Map<String, dynamic>.from(detail),
      );
      return parsed.animeId > 0 ? parsed : null;
    } catch (error) {
      WywLogger().w('${LogTag.danmaku} 弹幕库缓存读取失败，按无缓存处理 key=$key',
          error: error);
      _deleteQuietly(key);
      return null;
    }
  }

  /// 写入（点选某个库、或点「刷新」时调用；不跟进度走）。
  Future<void> save(String libraryId, DanmakuBangumiDetail detail) async {
    final key = _normalize(libraryId);
    if (key.isEmpty || detail.animeId <= 0) return;
    try {
      await _box.put(
        key,
        jsonEncode({
          'fetchedAtMs': DateTime.now().millisecondsSinceEpoch,
          'detail': detail.toMap(),
        }),
      );
      await _trimIfNeeded();
    } catch (error) {
      WywLogger().w('${LogTag.danmaku} 弹幕库缓存写入失败 key=$key', error: error);
    }
  }

  Future<void> remove(String libraryId) async {
    final key = _normalize(libraryId);
    if (key.isEmpty) return;
    await _deleteQuietly(key);
  }

  /// 缓存键：统一用去掉首尾空白的库 id（`refreshableId`：优先字符串 `bangumiId`）。
  String _normalize(String libraryId) => libraryId.trim();

  /// 超出上限时按 `fetchedAtMs` 淘汰最旧的若干条。
  Future<void> _trimIfNeeded() async {
    if (_box.length <= maxEntries) return;
    final entries = <MapEntry<String, int>>[];
    for (final key in _box.keys) {
      final raw = _box.get('$key');
      entries.add(MapEntry('$key', _fetchedAt(raw)));
    }
    entries.sort((a, b) => a.value.compareTo(b.value));
    final overflow = entries.length - maxEntries;
    for (var i = 0; i < overflow; i++) {
      await _deleteQuietly(entries[i].key);
    }
  }

  int _fetchedAt(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final value = decoded['fetchedAtMs'];
        if (value is int) return value;
        if (value is num) return value.toInt();
      }
    } catch (_) {
      // 解析失败按"最旧"处理，让它先被淘汰。
    }
    return 0;
  }

  Future<void> _deleteQuietly(String key) async {
    try {
      await _box.delete(key);
    } catch (error) {
      WywLogger().w('${LogTag.danmaku} 弹幕库缓存删除失败 key=$key', error: error);
    }
  }
}
