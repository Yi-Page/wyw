import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:wyw/repositories/i_history_repository.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/history_entry.dart';
import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/history_type.dart';
import 'package:wyw/services/storage/history_storage_coordinator.dart';
import 'package:wyw/services/storage/storage.dart';

class HistoryRepository implements IHistoryRepository {
  HistoryRepository({
    required Box<HistoryEntry> box,
    bool Function()? privateModeReader,
  })  : _box = box,
        _privateModeReader = privateModeReader ?? (() => false);

  final Box<HistoryEntry> _box;
  final bool Function() _privateModeReader;
  final HistoryStorageCoordinator _coordinator = HistoryStorageCoordinator();

  /// Hive 的 String key 上限是 255 字符，而 sourceId 可能是很长的代理 URL
  /// （如 http://127.0.0.1:port/m3u8?src=...&dir=...&hdrs=...&rk=...），
  /// 直接当作 box key 会抛 HiveError。这里统一映射为 sha256 十六进制
  /// （64 字符，稳定且不会超长）；完整 sourceId 仍存在条目字段里。
  String _keyFor(String sourceId) =>
      sha256.convert(utf8.encode(sourceId)).toString();

  /// 按 sourceId 读取条目：先查哈希 key，再兼容旧版本以完整 sourceId
  /// 为 key 的数据，最后全表扫描兜底（哈希冲突几乎不可能）。
  HistoryEntry? _getBySourceId(String sourceId) {
    final hashed = _box.get(_keyFor(sourceId));
    if (hashed != null && hashed.sourceId == sourceId) return hashed;
    final legacy = _box.get(sourceId);
    if (legacy != null && legacy.sourceId == sourceId) return legacy;
    for (final entry in _box.values) {
      if (entry.sourceId == sourceId) return entry;
    }
    return null;
  }

  /// 写入统一走哈希 key；旧格式遗留数据会在下一次写入时自然迁移。
  Future<void> _putEntry(HistoryEntry entry) async {
    await _coordinator.run(() async {
      await _box.put(_keyFor(entry.sourceId), entry);
    });
  }

  final Map<String, Timer> _pendingWrites = {};
  final Map<String, Map<String, dynamic>> _pendingProgress = {};
  final Map<String, HistoryType> _pendingTypes = {};
  static const Duration _throttleWindow = Duration(milliseconds: 200);

  @override
  Future<HistoryEntry> open({
    required HistoryType type,
    required String sourceId,
    required String title,
    String? cover,
  }) async {
    if (sourceId.isEmpty) {
      throw ArgumentError('sourceId must not be empty');
    }
    final effectiveTitle = title.isEmpty ? sourceId : title;
    final effectiveCover = cover ?? '';
    final existing = _getBySourceId(sourceId);
    final now = DateTime.now();
    final entry = HistoryEntry(
      sourceId: sourceId,
      type: type,
      title: effectiveTitle,
      cover: effectiveCover,
      lastWatchTime: existing?.lastWatchTime ?? now,
      progress: existing?.progress ?? const {},
    );
    if (!getPrivateMode()) {
      await _putEntry(entry);
    }
    return entry;
  }

  @override
  HistoryEntry? find({required HistoryType type, required String sourceId}) {
    return _getBySourceId(sourceId);
  }

  @override
  HistoryProgress parseProgress(HistoryEntry e) => e.parseProgress();

  @override
  List<HistoryEntry> getAll() {
    final list = _box.values.toList();
    list.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
    return list;
  }

  /// box 级变更流：任何一次落盘（含 200ms 节流后的 setProgress、flush、
  /// 删除/清空）都会触发。挂在 box 上而不是本实例上，是因为
  /// core_module / init_page / production_script_engine 各自 new 了一个
  /// [HistoryRepository]，但都指向同一个 `GStorage.histories` box ——
  /// 订阅方只需要拿到其中任意一个实例，就能收到所有写入方的通知。
  @override
  Stream<void> get changes => _box.watch().map<void>((_) {});

  @override
  Future<void> remove(
      {required HistoryType type, required String sourceId}) async {
    await _coordinator.run(() async {
      await _box.delete(_keyFor(sourceId));
      await _box.delete(sourceId); // 兼容旧格式 key
    });
  }

  @override
  Future<void> restore(HistoryEntry entry) async {
    await _putEntry(entry);
  }

  @override
  Future<void> clearAll() async {
    await _coordinator.run(() async {
      await _box.clear();
    });
  }

  @override
  bool getPrivateMode() => _privateModeReader();

  @override
  Future<void> setProgress({
    required HistoryType type,
    required String sourceId,
    String title = '',
    String cover = '',
    required Map<String, dynamic> progress,
  }) async {
    if (sourceId.isEmpty) {
      throw ArgumentError('sourceId must not be empty');
    }
    if (title.isEmpty) {
      title = sourceId;
    }
    if (getPrivateMode()) return;
    _pendingTypes[sourceId] = type;
    _pendingProgress[sourceId] = {...?_pendingProgress[sourceId], ...progress};
    _pendingWrites[sourceId]?.cancel();
    _pendingWrites[sourceId] = Timer(_throttleWindow, () {
      _flushInternal(sourceId, title, cover);
    });
  }

  Future<void> _flushInternal(
      String sourceId, String title, String cover) async {
    final progress = _pendingProgress.remove(sourceId);
    final type = _pendingTypes.remove(sourceId) ?? HistoryType.video;
    _pendingWrites.remove(sourceId);
    if (progress == null) return;
    final existing = _getBySourceId(sourceId);
    if (existing == null) {
      // entry 还没创建（registerSource 只设内存状态，没 open）→ 创建一个
      final created = HistoryEntry(
        sourceId: sourceId,
        type: type,
        title: title,
        cover: cover,
        lastWatchTime: DateTime.now(),
        progress: progress,
      );
      await _putEntry(created);
      return;
    }
    final updated = HistoryEntry(
      sourceId: existing.sourceId,
      type: existing.type,
      title: existing.title,
      cover: existing.cover,
      lastWatchTime: DateTime.now(),
      progress: progress,
    );
    await _putEntry(updated);
  }

  @override
  Future<void> flush({
    required HistoryType type,
    required String sourceId,
    required String title,
    required String cover,
  }) async {
    _pendingWrites[sourceId]?.cancel();
    await _flushInternal(sourceId, title, cover);
  }

  /// v2 → v3 就地迁移：把旧格式视频条目重写为 [VideoPlaybackProgress] 格式。
  ///
  /// 幂等：只有 progress 中不含 v3 特征键（`sources`/`videoId`）的
  /// video 条目才被重写。key 不变（无 sourceKey 时 videoId=videoUrl，
  /// sourceId 语义保持兼容）。
  Future<void> migrateV3() async {
    if (GStorage.getSettingByName('history_migrated_v3') == true) return;
    var touched = 0;
    for (final entry in _box.values) {
      if (entry.type != HistoryType.video) continue;
      final p = entry.progress;
      if (p.containsKey('sources') || p.containsKey('videoId')) continue;
      try {
        final wrapped = VideoPlaybackProgress.fromMap(p).toMap();
        final updated = HistoryEntry(
          sourceId: entry.sourceId,
          type: entry.type,
          title: entry.title,
          cover: entry.cover,
          lastWatchTime: entry.lastWatchTime,
          progress: wrapped,
        );
        await _putEntry(updated);
        touched++;
      } catch (e) {
        // 静默可接受：v3 迁移单条失败不阻塞整体，d 级留痕便于排查
        WywLogger().d(
            '${LogTag.history} migrateV3 单条记录迁移失败（跳过）sourceId=${entry.sourceId}',
            error: e);
      }
    }
    await GStorage.putSettingByName('history_migrated_v3', true);
    if (touched > 0) {
      WywLogger().i('${LogTag.history} migrateV3 迁移重写 $touched 条视频记录');
    }
  }

  /// 从旧 box（key 为 String，value 为 Map）一次性迁移到 v2
  ///
  /// 旧 schema（lib/modules/video/history_module.dart）：
  ///   videoName, videoSurfaceImg, progresses{videoUrl,_progressInMilli,updatedAtMs},
  ///   lastWatchTime(ms), entryKind, adapterName
  Future<void> migrateFromLegacy(Box<Map> legacyBox) async {
    if (legacyBox.isEmpty) return;
    for (final raw in legacyBox.values) {
      try {
        final progresses = (raw['progresses'] as Map?) ?? const {};
        final videoUrl = progresses['videoUrl'] as String? ?? '';
        if (videoUrl.isEmpty) continue;
        final positionMs =
            (progresses['_progressInMilli'] as num?)?.toInt() ?? 0;
        final entry = HistoryEntry(
          sourceId: videoUrl,
          type: HistoryType.video,
          title: (raw['videoName'] as String?) ?? videoUrl,
          cover: (raw['videoSurfaceImg'] as String?) ?? '',
          lastWatchTime: DateTime.fromMillisecondsSinceEpoch(
            (raw['lastWatchTime'] as num?)?.toInt() ?? 0,
          ),
          progress: {
            'videoUrl': videoUrl,
            'positionMs': positionMs,
            'durationMs': 0,
          },
        );
        await _putEntry(entry);
      } catch (e) {
        // 静默可接受：旧库迁移单条失败不阻塞整体，d 级留痕便于排查
        WywLogger().d(
            '${LogTag.history} 旧库迁移单条记录失败（跳过）videoName=${raw['videoName']}',
            error: e);
      }
    }
  }
}
