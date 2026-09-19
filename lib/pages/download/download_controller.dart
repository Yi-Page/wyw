// ignore_for_file: library_private_types_in_public_api

import 'dart:async';

import 'package:mobx/mobx.dart';
import 'package:path/path.dart' as path;
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/repositories/download_repository.dart';
import 'package:wyw/services/download/background_download_service.dart';
import 'package:wyw/services/download/download_manager.dart';
import 'package:wyw/services/download/playback_proxy_service.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/utils/file_system.dart';
import 'package:wyw/utils/http_headers.dart';
import 'package:wyw/utils/format.dart';

part 'download_controller.g.dart';

class DownloadController = _DownloadController with _$DownloadController;

abstract class _DownloadController with Store {
  _DownloadController(
    this._repository,
    this._downloadManager,
  );

  final IDownloadRepository _repository;
  final IDownloadManager _downloadManager;
  final _backgroundService = BackgroundDownloadService();

  @observable
  ObservableList<DownloadRecord> records = ObservableList<DownloadRecord>();
  final ObservableList<String> recordKeys = ObservableList<String>();
  final ObservableMap<String, DownloadRecord> recordByKey =
      ObservableMap<String, DownloadRecord>();

  bool _isBackgroundServiceInitialized = false;

  Future<void> init() async {
    _replaceRecords(_repository.getAllRecords());

    // Reset any incomplete states to 'paused' on startup
    // This includes 'pending' because the in-memory queue is lost on restart
    var resetIncompleteRecords = false;
    for (final record in records) {
      bool changed = false;
      for (final entry in record.episodes.entries) {
        if (entry.value.status == DownloadStatus.downloading ||
            entry.value.status == DownloadStatus.pending) {
          entry.value.status = DownloadStatus.paused;
          changed = true;
        }
      }
      if (changed) {
        resetIncompleteRecords = true;
        await _repository.putRecord(record);
      }
    }
    if (resetIncompleteRecords) {
      _replaceRecords(_repository.getAllRecords());
    }

    _downloadManager.onProgress = _onDownloadProgress;
    await _initBackgroundService();
  }

  Future<void> _initBackgroundService() async {
    if (!_backgroundService.isSupported) return;
    if (_isBackgroundServiceInitialized) return;

    await _backgroundService.init();
    _backgroundService.onPauseAll = pauseAllDownloads;
    _backgroundService.addTaskDataCallback(_onTaskData);
    _isBackgroundServiceInitialized = true;
  }

  void _onTaskData(Object data) {
    if (data is Map) {
      final action = data['action'];
      if (action == 'button_pressed') {
        _backgroundService.handleNotificationAction(data['id'] as String);
      } else if (action == 'navigate_to_download') {
        _backgroundService.handleNavigateToDownload();
      }
    }
  }

  final Map<String, double> _speeds = {};
  final _backgroundNotificationUpdater = _LatestAsyncRunner();
  DateTime _lastUiUpdateTime = DateTime.now();
  static const _uiUpdateInterval = Duration(milliseconds: 500);

  void _onDownloadProgress(String recordKey, int episodeNumber,
      DownloadEpisode episode, double speed) {
    final record = _repository.getRecord(recordKey);
    if (record == null || !record.episodes.containsKey(episodeNumber)) {
      return;
    }
    _repository.updateEpisode(recordKey, episodeNumber, episode);

    final key = '${recordKey}_$episodeNumber';

    final isFinalState = episode.status == DownloadStatus.completed ||
        episode.status == DownloadStatus.failed ||
        episode.status == DownloadStatus.paused;
    if (isFinalState) {
      _speeds.remove(key);
    } else {
      _speeds[key] = speed;
    }

    final now = DateTime.now();
    if (isFinalState ||
        now.difference(_lastUiUpdateTime) >= _uiUpdateInterval) {
      _lastUiUpdateTime = now;
      _refreshRecord(recordKey);
      _queueBackgroundNotificationUpdate();
    }
  }

  void _queueBackgroundNotificationUpdate() {
    _backgroundNotificationUpdater.schedule(() async {
      try {
        await _updateBackgroundNotification();
      } catch (e) {
        WywLogger().w(
          '${LogTag.download} 更新后台下载通知失败',
          error: e,
        );
      }
    });
  }

  Future<void> _updateBackgroundNotification() async {
    if (!_backgroundService.isRunning) return;

    final stats = _getDownloadStats();
    if (!stats.hasWork) {
      await _backgroundService.stopService();
      return;
    }

    var totalSpeed = 0.0;
    for (final key in stats.activeKeys) {
      totalSpeed += _speeds[key] ?? 0;
    }

    await _backgroundService.updateProgress(
      activeCount: stats.activeCount,
      totalCount: stats.totalCount,
      overallProgress: stats.overallProgress,
      speedText: formatSpeed(totalSpeed),
    );
  }

  Future<void> _startBackgroundServiceIfNeeded() async {
    if (!_backgroundService.isSupported || _backgroundService.isRunning) return;

    final started = await _backgroundService.startService();
    if (started) {
      WywLogger().i('${LogTag.download} 后台下载服务已启动');
    }
  }

  _DownloadStats _getDownloadStats() {
    var activeCount = 0;
    var pendingCount = 0;
    var totalCount = 0;
    var totalProgress = 0.0;
    final activeKeys = <String>{};

    for (final record in _repository.getAllRecords()) {
      for (final entry in record.episodes.entries) {
        final episode = entry.value;
        if (episode.status == DownloadStatus.downloading) {
          activeCount++;
          totalCount++;
          totalProgress += episode.progressPercent;
          activeKeys.add('${record.key}_${entry.key}');
        } else if (episode.status == DownloadStatus.resolving ||
            episode.status == DownloadStatus.pending) {
          pendingCount++;
          totalCount++;
        }
      }
    }

    return _DownloadStats(
      activeCount: activeCount,
      pendingCount: pendingCount,
      totalCount: totalCount,
      overallProgress: totalCount > 0 ? totalProgress / totalCount : 0.0,
      activeKeys: activeKeys,
    );
  }

  double getSpeed(int mediaId, String pluginName, int episodeNumber) {
    final key = '${pluginName}_${mediaId}_$episodeNumber';
    return _speeds[key] ?? 0.0;
  }

  @action
  void refreshRecords() {
    _replaceRecords(_repository.getAllRecords());
  }

  void _replaceRecords(List<DownloadRecord> nextRecords) {
    runInAction(() {
      records
        ..clear()
        ..addAll(nextRecords.map(_cloneRecord));

      recordKeys
        ..clear()
        ..addAll(nextRecords.map((record) => record.key));

      recordByKey
        ..clear()
        ..addEntries(nextRecords.map(
          (record) => MapEntry(record.key, _cloneRecord(record)),
        ));
    });
  }

  void _refreshRecord(String recordKey) {
    final record = _repository.getRecord(recordKey);
    runInAction(() {
      if (record == null || record.episodes.isEmpty) {
        recordByKey.remove(recordKey);
        recordKeys.remove(recordKey);
        records.removeWhere((item) => item.key == recordKey);
        return;
      }

      final snapshot = _cloneRecord(record);
      recordByKey[recordKey] = snapshot;
      final keyIndex = recordKeys.indexOf(recordKey);
      if (keyIndex == -1) {
        recordKeys.add(recordKey);
      }

      final recordIndex = records.indexWhere((item) => item.key == recordKey);
      if (recordIndex == -1) {
        records.add(_cloneRecord(record));
      } else {
        records[recordIndex] = _cloneRecord(record);
      }
    });
  }

  DownloadRecord? getRecordSnapshot(String recordKey) => recordByKey[recordKey];

  DownloadRecord _cloneRecord(DownloadRecord record) {
    return DownloadRecord(
      record.mediaId,
      record.mediaName,
      record.mediaCover,
      record.pluginName,
      record.episodes.map(
        (episodeNumber, episode) => MapEntry(
          episodeNumber,
          _cloneEpisode(episode),
        ),
      ),
      record.createdAt,
      videoId: record.videoId,
      sourceKey: record.sourceKey,
    );
  }

  DownloadEpisode _cloneEpisode(DownloadEpisode episode) {
    return DownloadEpisode(
      episode.episodeNumber,
      episode.episodeName,
      episode.road,
      episode.status,
      episode.progressPercent,
      episode.totalSegments,
      episode.downloadedSegments,
      episode.localM3u8Path,
      episode.downloadDirectory,
      episode.networkM3u8Url,
      episode.completedAt,
      episode.errorMessage,
      episode.totalBytes,
      danmakuData: episode.danmakuData,
      danDanBangumiID: episode.danDanBangumiID,
      sourceIndex: episode.sourceIndex,
      sourceName: episode.sourceName,
    );
  }

  DownloadRecord? getRecord(int mediaId, String pluginName) {
    return _repository.getRecordByMediaId(mediaId, pluginName);
  }

  DownloadEpisode? getEpisode(
      int mediaId, String pluginName, int episodeNumber) {
    return _repository.getEpisode(mediaId, pluginName, episodeNumber);
  }

  /// 按本地文件路径反查下载剧集；用于本地播放时取稳定的历史记录 key
  /// （networkM3u8Url），避免本地路径变化后历史无法反查到完成下载。
  DownloadEpisode? findEpisodeByLocalPath(String localPath) {
    if (localPath.isEmpty) return null;
    for (final record in _repository.getAllRecords()) {
      for (final episode in record.episodes.values) {
        if (episode.localM3u8Path.isNotEmpty &&
            path.equals(episode.localM3u8Path, localPath)) {
          return episode;
        }
      }
    }
    return null;
  }

  String? getLocalVideoPath(
      int mediaId, String pluginName, int episodeNumber) {
    final episode =
        _repository.getEpisode(mediaId, pluginName, episodeNumber);
    return _downloadManager.getLocalVideoPath(episode);
  }

  /// 按结构化身份（sourceKey+videoId+sourceIndex+episodeIndex）查下载剧集。
  DownloadEpisode? findEpisodeByIdentity({
    required String sourceKey,
    required String videoId,
    required int sourceIndex,
    required int episodeIndex,
  }) {
    if (videoId.isEmpty) return null;
    final plugin = sourceKey.isEmpty ? 'wyw' : sourceKey;
    final mediaId = videoId.hashCode;
    final record = _repository.getRecordByMediaId(mediaId, plugin);
    if (record == null) return null;
    return record.episodes[structuredEpisodeNumber(sourceIndex, episodeIndex)];
  }

  /// 按结构化身份查已完成下载的本地文件路径。
  String? findLocalVideoPathByIdentity({
    required String sourceKey,
    required String videoId,
    required int sourceIndex,
    required int episodeIndex,
  }) {
    final episode = findEpisodeByIdentity(
      sourceKey: sourceKey,
      videoId: videoId,
      sourceIndex: sourceIndex,
      episodeIndex: episodeIndex,
    );
    return _downloadManager.getLocalVideoPath(episode);
  }

  /// 按结构化身份判断是否存在进行中的下载任务（pending/resolving/downloading）。
  bool hasActiveDownloadByIdentity({
    required String sourceKey,
    required String videoId,
    required int sourceIndex,
    required int episodeIndex,
  }) {
    final episode = findEpisodeByIdentity(
      sourceKey: sourceKey,
      videoId: videoId,
      sourceIndex: sourceIndex,
      episodeIndex: episodeIndex,
    );
    if (episode == null) return false;
    return episode.status == DownloadStatus.resolving ||
        episode.status == DownloadStatus.downloading ||
        episode.status == DownloadStatus.pending;
  }

  List<DownloadEpisode> getCompletedEpisodes(int mediaId, String pluginName) {
    return _repository.getCompletedEpisodes(mediaId, pluginName);
  }

  /// 估算某个下载任务的落盘目录（与 DownloadManager 目录结构一致）：
  /// `<downloadBase>/<mediaId>_<pluginName>/<episodeNumber>`
  Future<String> resolveEpisodeDir({
    required int mediaId,
    required String pluginName,
    required int episodeNumber,
  }) async {
    var base = GStorage.getSetting(SettingsKeys.downloadDirectory).trim();
    if (base.isEmpty) {
      base = await getDefaultDownloadDirectory();
    }
    return path.join(base, '${mediaId}_$pluginName', '$episodeNumber');
  }

  /// 启动「播放即下载」：注册代理会话并返回代理 URL（供播放器切换）。
  ///
  /// [m3u8Url] 为已解析出的直链（.m3u8 或 .mp4）。
  /// 返回 null 表示任务不是媒体直链（无法走代理）。
  Future<String?> startProxyDownload({
    required int mediaId,
    required String pluginName,
    required int episodeNumber,
    required String episodeDir,
    required String m3u8Url,
    Map<String, String>? httpHeaders,
  }) async {
    if (m3u8Url.isEmpty) return null;
    final recordKey = '${pluginName}_$mediaId';
    final session = PlaybackProxySession(
      recordKey: recordKey,
      episodeNumber: episodeNumber,
      m3u8Url: m3u8Url,
      episodeDir: episodeDir,
      httpHeaders: httpHeaders ??
          <String, String>{'user-agent': getRandomUA(), 'referer': ''},
      adBlockerEnabled: _repository.getForceAdBlocker(),
    );
    await PlaybackProxyService.instance.start();
    PlaybackProxyService.instance.onProgress = (rk, ep, downloaded, total) {
      _updateProxyProgress(rk, ep, downloaded, total);
    };
    return PlaybackProxyService.instance.registerSession(session);
  }

  /// 结构化合流：按当前集身份查进行中任务，存在则启动代理合流。
  Future<String?> maybeStartProxyForPlaybackByIdentity({
    required String sourceKey,
    required String videoId,
    required int sourceIndex,
    required int episodeIndex,
    required String resolvedUrl,
  }) async {
    if (resolvedUrl.isEmpty) return null;
    final episode = findEpisodeByIdentity(
      sourceKey: sourceKey,
      videoId: videoId,
      sourceIndex: sourceIndex,
      episodeIndex: episodeIndex,
    );
    if (episode == null) return null;
    if (episode.status == DownloadStatus.completed ||
        episode.status == DownloadStatus.failed ||
        episode.status == DownloadStatus.paused) {
      return null;
    }
    final plugin = sourceKey.isEmpty ? 'wyw' : sourceKey;
    final record = _repository.getRecordByMediaId(videoId.hashCode, plugin);
    if (record == null) return null;
    final episodeDir = episode.downloadDirectory.trim().isNotEmpty
        ? episode.downloadDirectory
        : await resolveEpisodeDir(
            mediaId: record.mediaId,
            pluginName: record.pluginName,
            episodeNumber: episode.episodeNumber,
          );
    return startProxyDownload(
      mediaId: record.mediaId,
      pluginName: record.pluginName,
      episodeNumber: episode.episodeNumber,
      episodeDir: episodeDir,
      m3u8Url: resolvedUrl,
    );
  }

  void _updateProxyProgress(
      String recordKey, int episodeNumber, int downloaded, int total) {
    final record = _repository.getRecord(recordKey);
    if (record == null) return;
    final episode = record.episodes[episodeNumber];
    if (episode == null) return;
    if (episode.status == DownloadStatus.completed) return;
    episode.downloadedSegments = downloaded;
    episode.totalSegments =
        total > episode.totalSegments ? total : episode.totalSegments;
    episode.progressPercent = total > 0 ? downloaded / total : 0.0;
    _refreshRecord(recordKey);
  }

  /// 停止代理播放并移除会话。
  void stopProxyPlayback(String recordKey) {
    PlaybackProxyService.instance.removeSession(recordKey);
  }

  /// 预创建结构化下载任务（status=resolving）。
  ///
  /// 让「解析中」阶段在下载页立即可见（解析也是下载生命周期的一部分）。
  /// 解析由调用方经统一解析服务完成，随后调用 [downloadStructuredEpisode]
  /// 入队（resolving → downloading），失败调用 [failPreparedEpisode]。
  /// 幂等：已完成任务保持不变，其余（重）置为 resolving。
  Future<void> prepareStructuredEpisode({
    required String sourceKey,
    required String videoId,
    required String title,
    required String cover,
    required int sourceIndex,
    required int episodeIndex,
    required String episodeName,
    required String sourceName,
  }) async {
    if (videoId.isEmpty) return;
    final plugin = sourceKey.isEmpty ? 'wyw' : sourceKey;
    final mediaId = videoId.hashCode;
    final recordKey = '${plugin}_$mediaId';
    final episodeNumber = structuredEpisodeNumber(sourceIndex, episodeIndex);

    final record = _repository.getRecord(recordKey) ??
        DownloadRecord(
          mediaId,
          title,
          cover,
          plugin,
          {},
          DateTime.now(),
          videoId: videoId,
          sourceKey: sourceKey,
        );

    final existing = record.episodes[episodeNumber];
    if (existing != null) {
      if (existing.status == DownloadStatus.completed) {
        WywLogger().i(
            '${LogTag.download} 该集已完成下载，无需预创建 recordKey=$recordKey episodeNumber=$episodeNumber');
        return;
      }
      existing.episodeName = episodeName;
      existing.sourceIndex = sourceIndex;
      existing.sourceName = sourceName;
      existing.status = DownloadStatus.resolving;
      existing.errorMessage = '';
      existing.progressPercent = 0.0;
      existing.downloadedSegments = 0;
      await _repository.updateEpisode(recordKey, episodeNumber, existing);
    } else {
      final episode = DownloadEpisode(
        episodeNumber,
        episodeName,
        sourceIndex, // road（线路，沿用旧字段语义）
        DownloadStatus.resolving,
        0.0,
        0,
        0,
        '',
        '',
        '',
        null,
        '',
        0,
        sourceIndex: sourceIndex,
        sourceName: sourceName,
      );
      record.episodes[episodeNumber] = episode;
      await _repository.putRecord(record);
    }
    refreshRecords();
    WywLogger().i(
        '${LogTag.download} 创建解析中任务 recordKey=$recordKey episodeNumber=$episodeNumber');
  }

  /// 解析失败：将预创建的任务标记为失败（下载页可见原因）。
  Future<void> failPreparedEpisode({
    required String sourceKey,
    required String videoId,
    required int sourceIndex,
    required int episodeIndex,
    required String message,
  }) async {
    final plugin = sourceKey.isEmpty ? 'wyw' : sourceKey;
    final record = _repository.getRecordByMediaId(videoId.hashCode, plugin);
    if (record == null) return;
    final episodeNumber = structuredEpisodeNumber(sourceIndex, episodeIndex);
    final episode = record.episodes[episodeNumber];
    if (episode == null || episode.status == DownloadStatus.completed) return;
    episode.status = DownloadStatus.failed;
    episode.errorMessage = message;
    await _repository.updateEpisode(record.key, episodeNumber, episode);
    _refreshRecord(record.key);
    WywLogger().w(
        '${LogTag.download} 下载前解析失败 episodeNumber=$episodeNumber recordKey=${record.key} reason=$message');
  }

  /// 下载结构化选集里的一集（幂等：同身份已存在则更新；已完成则跳过）。
  ///
  /// 下载不负责解析：[resolvedUrl] 必须是调用方经解析服务得到的**最终媒体
  /// 直链**（m3u8/mp4）。任务创建即进入 downloading，无 resolving 中间态。
  ///
  /// [sourceKey] 插件 key（空→'wyw'）；[videoId] 结构化视频 id；
  /// [sourceIndex]/[episodeIndex] 线路/集数（均 0-based）。
  /// 返回 true 表示任务已成功入队（或该集已完成）。
  Future<bool> downloadStructuredEpisode({
    required String sourceKey,
    required String videoId,
    required String title,
    required String cover,
    required int sourceIndex,
    required int episodeIndex,
    required String episodeName,
    required String sourceName,
    required String resolvedUrl,
  }) async {
    if (videoId.isEmpty || resolvedUrl.isEmpty) return false;
    final plugin = sourceKey.isEmpty ? 'wyw' : sourceKey;
    final mediaId = videoId.hashCode;
    final recordKey = '${plugin}_$mediaId';
    final episodeNumber = structuredEpisodeNumber(sourceIndex, episodeIndex);

    final record = _repository.getRecord(recordKey) ??
        DownloadRecord(
          mediaId,
          title,
          cover,
          plugin,
          {},
          DateTime.now(),
          videoId: videoId,
          sourceKey: sourceKey,
        );

    final existing = record.episodes[episodeNumber];
    if (existing != null) {
      // 已存在：已完成则跳过；否则更新名称/直链并重跑下载
      if (existing.status == DownloadStatus.completed) {
        WywLogger().i(
            '${LogTag.download} 该集已完成下载，跳过 recordKey=$recordKey episodeNumber=$episodeNumber');
        return true;
      }
      existing.episodeName = episodeName;
      existing.networkM3u8Url = resolvedUrl;
      existing.sourceIndex = sourceIndex;
      existing.sourceName = sourceName;
      existing.status = DownloadStatus.downloading;
      existing.errorMessage = '';
      await _repository.updateEpisode(recordKey, episodeNumber, existing);
    } else {
      final episode = DownloadEpisode(
        episodeNumber,
        episodeName,
        sourceIndex, // road（线路，沿用旧字段语义）
        DownloadStatus.downloading,
        0.0,
        0,
        0,
        '',
        '',
        resolvedUrl,
        null,
        '',
        0,
        sourceIndex: sourceIndex,
        sourceName: sourceName,
      );
      record.episodes[episodeNumber] = episode;
      await _repository.putRecord(record);
    }
    refreshRecords();

    await _startBackgroundServiceIfNeeded();

    final httpHeaders = <String, String>{
      'user-agent': getRandomUA(),
      'referer': '',
    };
    final bool adBlockerEnabled = _repository.getForceAdBlocker();

    await _downloadManager.enqueue(DownloadRequest(
      recordKey: recordKey,
      mediaId: mediaId,
      pluginName: plugin,
      episodeNumber: episodeNumber,
      m3u8Url: resolvedUrl,
      httpHeaders: httpHeaders,
      adBlockerEnabled: adBlockerEnabled,
      episode: record.episodes[episodeNumber]!,
    ));
    return true;
  }

  Future<void> pauseDownload(
      int mediaId, String pluginName, int episodeNumber) async {
    final recordKey = '${pluginName}_$mediaId';
    _downloadManager.pause(recordKey, episodeNumber);

    final record = _repository.getRecord(recordKey);
    if (record != null) {
      final episode = record.episodes[episodeNumber];
      if (episode != null) {
        episode.status = DownloadStatus.paused;
        await _repository.updateEpisode(recordKey, episodeNumber, episode);
        _refreshRecord(recordKey);
        _queueBackgroundNotificationUpdate();
      }
    }
  }

  Future<void> pauseAllDownloads() async {
    WywLogger().i('${LogTag.download} 暂停所有下载任务');

    for (final record in records) {
      for (final entry in record.episodes.entries) {
        final episode = entry.value;
        if (episode.status == DownloadStatus.downloading ||
            episode.status == DownloadStatus.pending) {
          final recordKey = '${record.pluginName}_${record.mediaId}';
          _downloadManager.pause(recordKey, entry.key);
          episode.status = DownloadStatus.paused;
          await _repository.updateEpisode(recordKey, entry.key, episode);
        }
      }
    }

    refreshRecords();

    await _backgroundService.stopService();
  }

  Future<void> retryDownload({
    required int mediaId,
    required String pluginName,
    required int episodeNumber,
  }) async {
    final recordKey = '${pluginName}_$mediaId';
    final record = _repository.getRecord(recordKey);
    if (record == null) return;
    final episode = record.episodes[episodeNumber];
    if (episode == null) return;

    if (episode.networkM3u8Url.isNotEmpty) {
      episode.status = DownloadStatus.downloading;
      episode.errorMessage = '';
      episode.progressPercent = 0.0;
      episode.downloadedSegments = 0;
      await _repository.updateEpisode(recordKey, episodeNumber, episode);
      _refreshRecord(recordKey);

      await _startBackgroundServiceIfNeeded();

      final httpHeaders = <String, String>{
        'user-agent': getRandomUA(),
        'referer': '',
      };
      bool adBlockerEnabled = _repository.getForceAdBlocker();

      await _downloadManager.enqueue(DownloadRequest(
        recordKey: recordKey,
        mediaId: mediaId,
        pluginName: pluginName,
        episodeNumber: episodeNumber,
        m3u8Url: episode.networkM3u8Url,
        httpHeaders: httpHeaders,
        adBlockerEnabled: adBlockerEnabled,
        episode: episode,
      ));
    } else {
      // 旧格式任务缺少直链（现流程创建任务即持有成品直链），无法续跑
      episode.status = DownloadStatus.failed;
      episode.errorMessage = '缺少下载地址，请重新添加下载';
      await _repository.updateEpisode(recordKey, episodeNumber, episode);
      _refreshRecord(recordKey);
      WywLogger().w(
          '${LogTag.download} 重试失败：任务缺少直链 recordKey=$recordKey episodeNumber=$episodeNumber');
    }
  }

  Future<void> cancelDownload(
      int mediaId, String pluginName, int episodeNumber) async {
    final recordKey = '${pluginName}_$mediaId';
    final episode =
        _repository.getEpisode(mediaId, pluginName, episodeNumber);
    _downloadManager.cancel(recordKey, episodeNumber);
    await _downloadManager.deleteEpisodeFiles(
      mediaId,
      pluginName,
      episodeNumber,
      episode: episode,
    );
    await _repository.deleteEpisode(recordKey, episodeNumber);
    _refreshRecord(recordKey);
    _queueBackgroundNotificationUpdate();
  }

  Future<void> deleteRecord(int mediaId, String pluginName) async {
    final recordKey = '${pluginName}_$mediaId';
    final record = _repository.getRecord(recordKey);
    if (record != null) {
      for (final ep in record.episodes.keys) {
        _downloadManager.cancel(recordKey, ep);
        _speeds.remove('${recordKey}_$ep');
      }
    }
    await _downloadManager.deleteRecordFiles(
      mediaId,
      pluginName,
      record: record,
    );
    await _repository.deleteRecord(recordKey);
    _refreshRecord(recordKey);
    _queueBackgroundNotificationUpdate();
  }

  Future<void> deleteEpisode(
      int mediaId, String pluginName, int episodeNumber) async {
    final recordKey = '${pluginName}_$mediaId';
    _downloadManager.cancel(recordKey, episodeNumber);
    _speeds.remove('${recordKey}_$episodeNumber');
    final episode =
        _repository.getEpisode(mediaId, pluginName, episodeNumber);
    await _downloadManager.deleteEpisodeFiles(
      mediaId,
      pluginName,
      episodeNumber,
      episode: episode,
    );
    await _repository.deleteEpisode(recordKey, episodeNumber);
    _refreshRecord(recordKey);
    _queueBackgroundNotificationUpdate();
  }

  Future<void> priorityDownload({
    required int mediaId,
    required String pluginName,
    required int episodeNumber,
  }) async {
    final recordKey = '${pluginName}_$mediaId';
    final record = _repository.getRecord(recordKey);
    if (record == null) return;
    final episode = record.episodes[episodeNumber];
    if (episode == null) return;

    if (episode.networkM3u8Url.isNotEmpty) {
      episode.status = DownloadStatus.downloading;
      episode.errorMessage = '';
      await _repository.updateEpisode(recordKey, episodeNumber, episode);
      _refreshRecord(recordKey);

      await _startBackgroundServiceIfNeeded();

      final httpHeaders = <String, String>{
        'user-agent': getRandomUA(),
        'referer': '',
      };
      bool adBlockerEnabled = _repository.getForceAdBlocker();

      await _downloadManager.enqueuePriority(DownloadRequest(
        recordKey: recordKey,
        mediaId: mediaId,
        pluginName: pluginName,
        episodeNumber: episodeNumber,
        m3u8Url: episode.networkM3u8Url,
        httpHeaders: httpHeaders,
        adBlockerEnabled: adBlockerEnabled,
        episode: episode,
      ));
    } else {
      // 旧格式任务缺少直链（现流程创建任务即持有成品直链），无法置顶重跑
      episode.status = DownloadStatus.failed;
      episode.errorMessage = '缺少下载地址，请重新添加下载';
      await _repository.updateEpisode(recordKey, episodeNumber, episode);
      _refreshRecord(recordKey);
      WywLogger().w(
          '${LogTag.download} 置顶下载失败：任务缺少直链 recordKey=$recordKey episodeNumber=$episodeNumber');
    }
  }

  Future<void> resumeAllDownloads(int mediaId, String pluginName) async {
    final recordKey = '${pluginName}_$mediaId';
    final record = _repository.getRecord(recordKey);
    if (record == null) return;

    final incompleteEpisodes = record.episodes.entries
        .where((e) =>
            e.value.status == DownloadStatus.paused ||
            e.value.status == DownloadStatus.failed ||
            e.value.status == DownloadStatus.pending)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    for (final entry in incompleteEpisodes) {
      await retryDownload(
        mediaId: mediaId,
        pluginName: pluginName,
        episodeNumber: entry.key,
      );
    }

    if (incompleteEpisodes.isNotEmpty) {
      WywLogger().i(
        '${LogTag.download} 恢复下载任务 count=${incompleteEpisodes.length} recordKey=$recordKey',
      );
    }
  }

  int completedCount(DownloadRecord record) {
    return record.episodes.values
        .where((e) => e.status == DownloadStatus.completed)
        .length;
  }
}

class _DownloadStats {
  final int activeCount;
  final int pendingCount;
  final int totalCount;
  final double overallProgress;
  final Set<String> activeKeys;

  const _DownloadStats({
    required this.activeCount,
    required this.pendingCount,
    required this.totalCount,
    required this.overallProgress,
    required this.activeKeys,
  });

  bool get hasWork => activeCount > 0 || pendingCount > 0;
}

class _LatestAsyncRunner {
  bool _isRunning = false;
  bool _needsRun = false;

  void schedule(Future<void> Function() task) {
    if (_isRunning) {
      _needsRun = true;
      return;
    }
    unawaited(_run(task));
  }

  Future<void> _run(Future<void> Function() task) async {
    _isRunning = true;
    try {
      do {
        _needsRun = false;
        await task();
      } while (_needsRun);
    } finally {
      _isRunning = false;
    }
  }
}
