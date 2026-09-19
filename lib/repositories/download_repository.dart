import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

abstract class IDownloadRepository {
  /// Emits when a record or an episode status is persisted. Progress ticks stay
  /// in memory, so they do not emit.
  Stream<void> get changes;

  List<DownloadRecord> getAllRecords();
  DownloadRecord? getRecord(String key);
  Future<void> putRecord(DownloadRecord record);
  Future<void> deleteRecord(String key);
  Future<void> updateEpisode(
      String recordKey, int episodeNumber, DownloadEpisode episode);
  Future<void> deleteEpisode(String recordKey, int episodeNumber);
  bool getForceAdBlocker();

  /// 获取指定媒体的下载记录
  ///
  /// [mediaId] 媒体 ID
  /// [pluginName] 插件名称
  DownloadRecord? getRecordByMediaId(int mediaId, String pluginName);

  /// 获取指定集数的下载信息
  ///
  /// [mediaId] 媒体 ID
  /// [pluginName] 插件名称
  /// [episodeNumber] 集数编号
  DownloadEpisode? getEpisode(
      int mediaId, String pluginName, int episodeNumber);

  /// 获取已完成下载的集数列表
  ///
  /// [mediaId] 媒体 ID
  /// [pluginName] 插件名称
  /// 返回所有已完成下载的集数
  List<DownloadEpisode> getCompletedEpisodes(int mediaId, String pluginName);
}

class DownloadRepository implements IDownloadRepository {
  final _downloadsBox = GStorage.downloads;

  @override
  Stream<void> get changes => _downloadsBox.watch();

  @override
  List<DownloadRecord> getAllRecords() {
    final List<DownloadRecord> result = [];
    try {
      for (final key in _downloadsBox.keys) {
        try {
          final record = _downloadsBox.get(key);
          if (record != null) {
            // Merge in-memory progress into the record
            final cachedEpisodes = _progressCache[key as String];
            if (cachedEpisodes != null) {
              for (final entry in cachedEpisodes.entries) {
                record.episodes[entry.key] = entry.value;
              }
            }
            result.add(record);
          }
        } catch (e) {
          // 单条记录读取失败，跳过该记录并记录日志
          WywLogger().w('${LogTag.download} 单条下载记录读取失败，跳过 key=$key', error: e);
        }
      }
    } catch (e) {
      WywLogger().w('${LogTag.download} 读取全部下载记录失败', error: e);
    }
    return result;
  }

  @override
  DownloadRecord? getRecord(String key) {
    try {
      final record = _downloadsBox.get(key);
      if (record != null) {
        // Merge in-memory progress into the record
        final cachedEpisodes = _progressCache[key];
        if (cachedEpisodes != null) {
          for (final entry in cachedEpisodes.entries) {
            record.episodes[entry.key] = entry.value;
          }
        }
      }
      return record;
    } catch (e) {
      WywLogger().w('${LogTag.download} 读取下载记录失败 key=$key', error: e);
      return null;
    }
  }

  @override
  Future<void> putRecord(DownloadRecord record) async {
    try {
      await _downloadsBox.put(record.key, record);
      await _downloadsBox.flush();
    } catch (e, s) {
      WywLogger().e(
        '${LogTag.download} 写入下载记录失败 key=${record.key}',
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  @override
  Future<void> deleteRecord(String key) async {
    try {
      await _downloadsBox.delete(key);
      await _downloadsBox.flush();
      _progressCache.remove(key);
      _lastPersistedStatus.removeWhere((k, v) => k.startsWith('${key}_'));
    } catch (e, s) {
      WywLogger().e(
        '${LogTag.download} 删除下载记录失败 key=$key',
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  /// Track last persisted status to avoid unnecessary writes
  final Map<String, int> _lastPersistedStatus = {};

  /// In-memory cache for progress updates (not persisted until status changes)
  final Map<String, Map<int, DownloadEpisode>> _progressCache = {};

  @override
  Future<void> updateEpisode(
      String recordKey, int episodeNumber, DownloadEpisode episode) async {
    try {
      // Update in-memory cache
      _progressCache.putIfAbsent(recordKey, () => {});
      _progressCache[recordKey]![episodeNumber] = episode;

      // Only persist to Hive when status changes (not on every progress update)
      // This dramatically reduces disk I/O and prevents corruption on crash
      final statusKey = '${recordKey}_$episodeNumber';
      final lastStatus = _lastPersistedStatus[statusKey];
      final shouldPersist = lastStatus != episode.status;

      if (shouldPersist) {
        final record = _downloadsBox.get(recordKey);
        if (record == null) return;
        record.episodes[episodeNumber] = episode;
        await _downloadsBox.put(recordKey, record);
        await _downloadsBox.flush();
        _lastPersistedStatus[statusKey] = episode.status;
      }
    } catch (e, s) {
      WywLogger().e(
        '${LogTag.download} 更新下载分集失败 key=$recordKey ep=$episodeNumber',
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  /// Get episode with in-memory progress if available
  DownloadEpisode? getEpisodeWithProgress(String recordKey, int episodeNumber) {
    // Check in-memory cache first
    final cached = _progressCache[recordKey]?[episodeNumber];
    if (cached != null) return cached;

    // Fall back to Hive
    final record = getRecord(recordKey);
    return record?.episodes[episodeNumber];
  }

  @override
  bool getForceAdBlocker() {
    return GStorage.getSetting(SettingsKeys.forceAdBlocker);
  }

  @override
  Future<void> deleteEpisode(String recordKey, int episodeNumber) async {
    try {
      final record = _downloadsBox.get(recordKey);
      if (record == null) return;
      record.episodes.remove(episodeNumber);
      if (record.episodes.isEmpty) {
        await _downloadsBox.delete(recordKey);
        _progressCache.remove(recordKey);
        _lastPersistedStatus
            .removeWhere((k, v) => k.startsWith('${recordKey}_'));
      } else {
        await _downloadsBox.put(recordKey, record);
        _progressCache[recordKey]?.remove(episodeNumber);
        _lastPersistedStatus.remove('${recordKey}_$episodeNumber');
      }
      await _downloadsBox.flush();
    } catch (e, s) {
      WywLogger().e(
        '${LogTag.download} 删除下载分集失败 key=$recordKey ep=$episodeNumber',
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  @override
  DownloadRecord? getRecordByMediaId(int mediaId, String pluginName) {
    final key = '${pluginName}_$mediaId';
    return getRecord(key);
  }

  @override
  DownloadEpisode? getEpisode(
      int mediaId, String pluginName, int episodeNumber) {
    final record = getRecordByMediaId(mediaId, pluginName);
    return record?.episodes[episodeNumber];
  }

  @override
  List<DownloadEpisode> getCompletedEpisodes(int mediaId, String pluginName) {
    final record = getRecordByMediaId(mediaId, pluginName);
    if (record == null) return [];

    return record.episodes.values
        .where((e) => e.status == DownloadStatus.completed)
        .toList()
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
  }
}
