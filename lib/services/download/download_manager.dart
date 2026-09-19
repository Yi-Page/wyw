import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/request/clients/download_http_client.dart';
import 'package:wyw/request/core/network_exception.dart';
import 'package:wyw/utils/m3u8_parser.dart';
import 'package:wyw/utils/m3u8_ad_filter.dart';
import 'package:wyw/utils/format.dart' as fmt;
import 'package:wyw/utils/file_system.dart';
import 'package:wyw/utils/segment_file_coordinator.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/platform/secure_bookmark_service.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:path/path.dart' as path;

class _NotM3u8Exception implements Exception {
  final String message;
  _NotM3u8Exception(this.message);
  @override
  String toString() => message;
}

class _InsufficientStorageException implements Exception {
  final int availableBytes;
  final int requiredBytes;
  _InsufficientStorageException(this.availableBytes, this.requiredBytes);
  @override
  String toString() => '存储空间不足';
}

class DownloadTask {
  final String recordKey;
  final int episodeNumber;
  CancelToken cancelToken;
  bool isPaused;

  DownloadTask({
    required this.recordKey,
    required this.episodeNumber,
    CancelToken? cancelToken,
    this.isPaused = false,
  }) : cancelToken = cancelToken ?? CancelToken();
}

typedef ProgressCallback = void Function(
    String recordKey, int episodeNumber, DownloadEpisode episode, double speed);

final _m3u8SegmentFileNamePattern = RegExp(r'^seg_\d+\.ts$');

Future<int> calculateM3u8VideoBytes(String episodeDir) async {
  final dir = Directory(episodeDir);
  if (!await dir.exists()) return 0;

  var totalBytes = 0;
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.isNotEmpty
        ? Uri.decodeComponent(entity.uri.pathSegments.last)
        : entity.path.split(Platform.pathSeparator).last;
    if (!_m3u8SegmentFileNamePattern.hasMatch(name)) continue;

    try {
      totalBytes += await entity.length();
    } on FileSystemException {
      // Ignore transient filesystem failures while reporting display size.
    }
  }
  return totalBytes;
}

class DownloadRequest {
  final String recordKey;
  final int mediaId;
  final String pluginName;
  final int episodeNumber;
  final String m3u8Url;
  final Map<String, String> httpHeaders;
  final bool adBlockerEnabled;
  final DownloadEpisode episode;

  const DownloadRequest({
    required this.recordKey,
    required this.mediaId,
    required this.pluginName,
    required this.episodeNumber,
    required this.m3u8Url,
    required this.httpHeaders,
    required this.adBlockerEnabled,
    required this.episode,
  });
}

abstract class IDownloadManager {
  ProgressCallback? onProgress;

  bool isDownloading(String recordKey, int episodeNumber);
  Future<void> enqueue(DownloadRequest request);
  Future<void> enqueuePriority(DownloadRequest request);
  void pause(String recordKey, int episodeNumber);
  Future<void> resume(DownloadRequest request);
  void cancel(String recordKey, int episodeNumber);
  String? getLocalVideoPath(DownloadEpisode? episode);
  Future<void> deleteEpisodeFiles(
      int mediaId, String pluginName, int episodeNumber,
      {DownloadEpisode? episode});
  Future<void> deleteRecordFiles(int mediaId, String pluginName,
      {DownloadRecord? record});
  double getSpeed(String recordKey, int episodeNumber);
}

class _SpeedTracker {
  int _lastBytes = 0;
  DateTime _lastTime = DateTime.now();
  double currentSpeed = 0.0; // bytes/sec

  void update(int totalBytes) {
    final now = DateTime.now();
    final elapsed = now.difference(_lastTime).inMilliseconds;
    if (elapsed > 500) {
      final bytesDownloaded = totalBytes - _lastBytes;
      currentSpeed = bytesDownloaded / (elapsed / 1000);
      _lastBytes = totalBytes;
      _lastTime = now;
    }
  }

  void reset() {
    _lastBytes = 0;
    _lastTime = DateTime.now();
    currentSpeed = 0.0;
  }
}

class DownloadManager implements IDownloadManager {
  DownloadManager() {
    _loadSettings();
  }

  final DownloadHttpClient _http = DownloadHttpClient.instance;

  final Map<String, DownloadTask> _activeTasks = {};
  final List<DownloadRequest> _queue = [];
  final Map<String, _SpeedTracker> _speedTrackers = {};
  int maxParallelEpisodes = 2;
  int maxParallelSegments = 3;
  int _runningCount = 0;

  @override
  ProgressCallback? onProgress;

  static const _minRequiredSpace = 100 * 1024 * 1024; // 100MB minimum
  static const _storageChannel = MethodChannel('com.yi.wyw/storage');

  void _loadSettings() {
    maxParallelEpisodes =
        GStorage.getSetting(SettingsKeys.downloadParallelEpisodes);
    maxParallelSegments =
        GStorage.getSetting(SettingsKeys.downloadParallelSegments);
  }

  /// Returns available bytes, or -1 if unable to determine
  Future<int> _getAvailableStorage(String path) async {
    try {
      final result = await _storageChannel.invokeMethod<int>(
        'getAvailableStorage',
        {'path': path},
      );
      return result ?? -1;
    } on MissingPluginException {
      return -1;
    } catch (e) {
      WywLogger().w('${LogTag.download} 查询可用存储空间失败 path=$path', error: e);
      return -1;
    }
  }

  Future<void> _checkStorageSpace(String downloadDir,
      {int requiredBytes = 0}) async {
    final available = await _getAvailableStorage(downloadDir);
    if (available == -1) return; // Skip check if unable to determine

    final required = requiredBytes > 0 ? requiredBytes : _minRequiredSpace;
    if (available < required) {
      throw _InsufficientStorageException(available, required);
    }
  }

  String _getStorageErrorMessage(FileSystemException e) {
    // POSIX error code 28 = ENOSPC (No space left on device)
    if (e.osError?.errorCode == 28) {
      return '存储空间不足，请清理后重试';
    }
    // POSIX error code 13 = EACCES (Permission denied)
    if (e.osError?.errorCode == 13) {
      return '存储权限被拒绝';
    }
    // POSIX error code 30 = EROFS (Read-only file system)
    if (e.osError?.errorCode == 30) {
      return '存储为只读，无法写入';
    }
    return '存储错误: ${e.message}';
  }

  @override
  double getSpeed(String recordKey, int episodeNumber) {
    final key = _taskKey(recordKey, episodeNumber);
    return _speedTrackers[key]?.currentSpeed ?? 0.0;
  }

  String _taskKey(String recordKey, int episodeNumber) =>
      '${recordKey}_$episodeNumber';

  @override
  bool isDownloading(String recordKey, int episodeNumber) =>
      _activeTasks.containsKey(_taskKey(recordKey, episodeNumber));

  Future<String> get _downloadBaseDir async {
    if (supportsCustomDownloadDirectory) {
      final customDir =
          GStorage.getSetting(SettingsKeys.downloadDirectory).trim();
      if (customDir.isNotEmpty) {
        // On macOS this re-establishes sandbox access after a restart;
        // elsewhere it returns the path unchanged.
        final usable = await SecureBookmarkService.restore(customDir);
        if (usable != null) return usable;
        WywLogger().w('${LogTag.download} 自定义下载目录不可用，回退默认目录 dir=$customDir');
      }
    }
    return getDefaultDownloadDirectory();
  }

  String _getEpisodeDir(String downloadBase, int mediaId, String pluginName,
      int episodeNumber) {
    return path.join(
        downloadBase, '${mediaId}_$pluginName', '$episodeNumber');
  }

  /// Resolves the episode directory (kept from a previous attempt if any),
  /// verifies it is writable, and persists it on the episode.
  Future<String> _prepareEpisodeDir(
    DownloadEpisode episode,
    int mediaId,
    String pluginName,
    int episodeNumber,
  ) async {
    final storedDir = episode.downloadDirectory.trim();
    final episodeDir = storedDir.isNotEmpty
        ? storedDir
        : _getEpisodeDir(
            await _downloadBaseDir, mediaId, pluginName, episodeNumber);
    await ensureDirectoryWritable(episodeDir);
    episode.downloadDirectory = episodeDir;
    await _checkStorageSpace(episodeDir);
    return episodeDir;
  }

  /// Directory to remove for an episode: the recorded one, or the default
  /// location for episodes that never started downloading.
  Future<String> _episodeDirForDeletion(
    DownloadEpisode? episode,
    int mediaId,
    String pluginName,
    int episodeNumber,
  ) async {
    final storedDir = episode?.downloadDirectory.trim() ?? '';
    if (storedDir.isNotEmpty) return storedDir;
    return _getEpisodeDir(await getDefaultDownloadDirectory(), mediaId,
        pluginName, episodeNumber);
  }

  @override
  Future<void> enqueue(DownloadRequest request) async {
    final key = _taskKey(request.recordKey, request.episodeNumber);
    if (_activeTasks.containsKey(key)) return;

    final task = DownloadTask(
      recordKey: request.recordKey,
      episodeNumber: request.episodeNumber,
    );

    if (_runningCount < maxParallelEpisodes) {
      _runningCount++;
      _activeTasks[key] = task;
      _runEpisodeDownload(
        task: task,
        mediaId: request.mediaId,
        pluginName: request.pluginName,
        m3u8Url: request.m3u8Url,
        httpHeaders: request.httpHeaders,
        adBlockerEnabled: request.adBlockerEnabled,
        episode: request.episode,
      );
    } else {
      request.episode.status = DownloadStatus.pending;
      _queue.add(request);
      _activeTasks[key] = task;
    }
  }

  @override
  Future<void> enqueuePriority(DownloadRequest request) async {
    final key = _taskKey(request.recordKey, request.episodeNumber);

    _queue.removeWhere(
      (r) =>
          r.recordKey == request.recordKey &&
          r.episodeNumber == request.episodeNumber,
    );
    _activeTasks.remove(key);

    final task = DownloadTask(
      recordKey: request.recordKey,
      episodeNumber: request.episodeNumber,
    );

    // Start immediately, bypassing the parallel limit (priority download)
    _runningCount++;
    _activeTasks[key] = task;
    _runEpisodeDownload(
      task: task,
      mediaId: request.mediaId,
      pluginName: request.pluginName,
      m3u8Url: request.m3u8Url,
      httpHeaders: request.httpHeaders,
      adBlockerEnabled: request.adBlockerEnabled,
      episode: request.episode,
    );
  }

  @override
  void pause(String recordKey, int episodeNumber) {
    final key = _taskKey(recordKey, episodeNumber);
    final task = _activeTasks[key];
    if (task != null) {
      task.isPaused = true;
      task.cancelToken.cancel('paused');
    }
  }

  @override
  Future<void> resume(DownloadRequest request) async {
    final key = _taskKey(request.recordKey, request.episodeNumber);
    _activeTasks.remove(key);

    final task = DownloadTask(
      recordKey: request.recordKey,
      episodeNumber: request.episodeNumber,
    );
    _activeTasks[key] = task;

    if (_runningCount < maxParallelEpisodes) {
      _runningCount++;
      _runEpisodeDownload(
        task: task,
        mediaId: request.mediaId,
        pluginName: request.pluginName,
        m3u8Url: request.m3u8Url,
        httpHeaders: request.httpHeaders,
        adBlockerEnabled: request.adBlockerEnabled,
        episode: request.episode,
      );
    } else {
      _queue.add(request);
    }
  }

  @override
  void cancel(String recordKey, int episodeNumber) {
    final key = _taskKey(recordKey, episodeNumber);
    final task = _activeTasks[key];
    if (task != null) {
      task.cancelToken.cancel('cancelled');
      _activeTasks.remove(key);
      _queue.removeWhere(
        (r) => r.recordKey == recordKey && r.episodeNumber == episodeNumber,
      );
    }
  }

  void _processQueue() {
    while (_runningCount < maxParallelEpisodes && _queue.isNotEmpty) {
      final request = _queue.removeAt(0);
      final key = _taskKey(request.recordKey, request.episodeNumber);
      final existingTask = _activeTasks[key];
      if (existingTask == null ||
          existingTask.isPaused ||
          existingTask.cancelToken.isCancelled) {
        _activeTasks.remove(key);
        continue;
      }

      _runningCount++;
      _runEpisodeDownload(
        task: existingTask,
        mediaId: request.mediaId,
        pluginName: request.pluginName,
        m3u8Url: request.m3u8Url,
        httpHeaders: request.httpHeaders,
        adBlockerEnabled: request.adBlockerEnabled,
        episode: request.episode,
      );
    }
  }

  Future<void> _runEpisodeDownload({
    required DownloadTask task,
    required int mediaId,
    required String pluginName,
    required String m3u8Url,
    required Map<String, String> httpHeaders,
    required bool adBlockerEnabled,
    required DownloadEpisode episode,
  }) async {
    final key = _taskKey(task.recordKey, task.episodeNumber);
    try {
      final episodeDir = await _prepareEpisodeDir(
          episode, mediaId, pluginName, task.episodeNumber);

      episode.status = DownloadStatus.downloading;
      episode.networkM3u8Url = m3u8Url;
      _notifyProgress(task.recordKey, task.episodeNumber, episode);

      String m3u8Content;
      try {
        m3u8Content = await _fetchM3u8(m3u8Url, httpHeaders, task.cancelToken);
      } on _NotM3u8Exception {
        WywLogger().i(
          '${LogTag.download} URL 非 M3U8，回退直链下载 '
          'episode=${task.episodeNumber} url=$m3u8Url',
        );
        await _runDirectFileDownload(
          task: task,
          mediaId: mediaId,
          pluginName: pluginName,
          videoUrl: m3u8Url,
          httpHeaders: httpHeaders,
          episode: episode,
        );
        return;
      }

      final resolved = await _resolveMediaSegments(
        task: task,
        episode: episode,
        m3u8Content: m3u8Content,
        m3u8Url: m3u8Url,
        httpHeaders: httpHeaders,
        cancelToken: task.cancelToken,
        adBlockerEnabled: adBlockerEnabled,
      );
      if (resolved == null) return;
      final (segments, targetDuration) = resolved;

      final keys = M3u8Parser.extractUniqueKeys(
        M3u8MediaPlaylist(
          segments: segments,
          targetDuration: targetDuration,
          isVod: true,
        ),
      );
      final keyUriToLocal = <String, String>{};
      for (int i = 0; i < keys.length; i++) {
        final keyFile = 'key_$i.key';
        final keyPath = path.join(episodeDir, keyFile);
        await _downloadFile(
            keys[i].uri, keyPath, httpHeaders, task.cancelToken);
        keyUriToLocal[keys[i].uri] = keyFile;
      }

      episode.totalSegments = segments.length;
      episode.downloadedSegments = 0;
      _notifyProgress(task.recordKey, task.episodeNumber, episode);
      final episodeDirObj = Directory(episodeDir);
      if (await episodeDirObj.exists()) {
        await for (final entity in episodeDirObj.list()) {
          // 旧格式 .tmp 与协调器唯一后缀格式 seg_x.ts.tmp.<token> 都清理；
          // 但「播放即下载」代理可能正在并发写同一目录：正在写入中的
          // 临时文件（协调器登记的活跃路径）不能删，否则该分片落盘失败，
          // 出现「已播放的进度没有下载」。
          if (entity.path.endsWith('.tmp') || entity.path.contains('.tmp.')) {
            if (SegmentWriteCoordinator.instance
                .isActiveTempPath(entity.path)) {
              continue;
            }
            try {
              await entity.delete();
            } catch (_) {
              // 静默可接受：清理残留 .tmp 失败属常态（文件可能正被占用），高频 best-effort 路径
            }
          }
        }
      }

      final existingSegments = <int>{};
      var existingBytes = 0;
      for (int i = 0; i < segments.length; i++) {
        final segFile = File(
            path.join(episodeDir, 'seg_${i.toString().padLeft(5, '0')}.ts'));
        if (await segFile.exists()) {
          final segmentBytes = await segFile.length();
          if (segmentBytes <= 0) continue;
          existingSegments.add(i);
          episode.downloadedSegments++;
          existingBytes += segmentBytes;
        }
      }
      episode.totalBytes = existingBytes;
      episode.progressPercent = episode.totalSegments > 0
          ? episode.downloadedSegments / episode.totalSegments
          : 0.0;
      _notifyProgress(task.recordKey, task.episodeNumber, episode);

      final result = await _downloadSegmentsInParallel(
        key: key,
        task: task,
        episode: episode,
        segments: segments,
        existingSegments: existingSegments,
        existingBytes: existingBytes,
        episodeDir: episodeDir,
        httpHeaders: httpHeaders,
      );
      final sessionBytes = result.sessionBytes;
      final failedCount = result.failedCount;

      if (result.cancelled) {
        if (task.isPaused) {
          episode.status = DownloadStatus.paused;
        }
        _notifyProgress(task.recordKey, task.episodeNumber, episode);
        return;
      }

      if (failedCount > 0) {
        episode.status = DownloadStatus.failed;
        episode.errorMessage = '$failedCount 个分片下载失败';
        _notifyProgress(task.recordKey, task.episodeNumber, episode);
        return;
      }

      final finalTargetDuration = adBlockerEnabled
          ? M3u8AdFilter.calculateTargetDuration(segments)
          : targetDuration;
      final localM3u8 = M3u8Parser.buildLocalM3u8(
        segments,
        targetDuration: finalTargetDuration,
        keyUriToLocal: keyUriToLocal,
      );
      final m3u8Path = path.join(episodeDir, 'playlist.m3u8');
      await File(m3u8Path).writeAsString(localM3u8);
      final finalVideoBytes = await calculateM3u8VideoBytes(episodeDir);

      episode.status = DownloadStatus.completed;
      episode.localM3u8Path = m3u8Path;
      episode.progressPercent = 1.0;
      episode.completedAt = DateTime.now();
      episode.totalBytes =
          finalVideoBytes > 0 ? finalVideoBytes : existingBytes + sessionBytes;
      _notifyProgress(task.recordKey, task.episodeNumber, episode);

      WywLogger().i(
        '${LogTag.download} 分集下载完成 episode=${task.episodeNumber} '
        'segments=${segments.length} size=${(episode.totalBytes / 1024 / 1024).toStringAsFixed(1)}MB',
      );
    } on _InsufficientStorageException catch (e) {
      episode.status = DownloadStatus.failed;
      episode.errorMessage =
          '存储空间不足 (可用: ${fmt.formatBytes(e.availableBytes)})';
      _notifyProgress(task.recordKey, task.episodeNumber, episode);
      WywLogger().w('${LogTag.download} 存储空间不足 episode=${task.episodeNumber}',
          error: e);
    } on FileSystemException catch (e) {
      episode.status = DownloadStatus.failed;
      episode.errorMessage = _getStorageErrorMessage(e);
      _notifyProgress(task.recordKey, task.episodeNumber, episode);
      WywLogger().e('${LogTag.download} 文件系统错误 episode=${task.episodeNumber}',
          error: e);
    } on NetworkException catch (e) {
      if (e.type == NetworkExceptionType.cancel) {
        if (task.isPaused) {
          episode.status = DownloadStatus.paused;
        }
      } else {
        episode.status = DownloadStatus.failed;
        episode.errorMessage = e.message;
      }
      _notifyProgress(task.recordKey, task.episodeNumber, episode);
    } catch (e) {
      episode.status = DownloadStatus.failed;
      episode.errorMessage = e.toString();
      _notifyProgress(task.recordKey, task.episodeNumber, episode);
      WywLogger().e('${LogTag.download} 分集下载失败 episode=${task.episodeNumber}',
          error: e);
    } finally {
      _onTaskComplete(key);
    }
  }

  /// 解析 m3u8 内容为最终待下载分片（含 master 展开、嵌套展开、广告过滤）。
  ///
  /// 返回 `(segments, targetDuration)`；直播流或无分片时已把 [episode] 置为
  /// 失败并 notify，返回 null，调用方应直接结束该集下载。
  Future<(List<M3u8Segment>, double)?> _resolveMediaSegments({
    required DownloadTask task,
    required DownloadEpisode episode,
    required String m3u8Content,
    required String m3u8Url,
    required Map<String, String> httpHeaders,
    required CancelToken cancelToken,
    required bool adBlockerEnabled,
  }) async {
    final type = M3u8Parser.detectType(m3u8Content);
    String mediaM3u8Content = m3u8Content;
    String mediaM3u8Url = m3u8Url;

    if (type == M3u8Type.master) {
      final master = M3u8Parser.parseMasterPlaylist(m3u8Content, m3u8Url);
      final bestVariant = master.bestVariant;
      mediaM3u8Url = bestVariant.uri;
      mediaM3u8Content =
          await _fetchM3u8(mediaM3u8Url, httpHeaders, cancelToken);
    }

    final playlist =
        M3u8Parser.parseMediaPlaylist(mediaM3u8Content, mediaM3u8Url);

    // 展开嵌套 m3u8 片段（部分源将实际内容嵌套在 m3u8 引用中）
    final resolvedSegments = await M3u8Parser.resolveNestedSegments(
      playlist.segments,
      (url) => _fetchM3u8(url, httpHeaders, cancelToken),
    );
    final resolvedPlaylist = M3u8MediaPlaylist(
      segments: resolvedSegments,
      targetDuration: playlist.targetDuration,
      isVod: playlist.isVod,
    );

    if (!resolvedPlaylist.isVod) {
      episode.status = DownloadStatus.failed;
      episode.errorMessage = '不支持下载直播流 (无有效分片)';
      _notifyProgress(task.recordKey, episode.episodeNumber, episode);
      return null;
    }

    if (resolvedPlaylist.segments.isEmpty) {
      episode.status = DownloadStatus.failed;
      episode.errorMessage = 'M3U8 中未找到可下载的分片';
      _notifyProgress(task.recordKey, episode.episodeNumber, episode);
      return null;
    }

    List<M3u8Segment> segments = resolvedPlaylist.segments;
    if (adBlockerEnabled) {
      segments = M3u8AdFilter.filterAds(segments);
    }
    return (segments, resolvedPlaylist.targetDuration);
  }

  /// 并发下载未完成的分片，返回 `(sessionBytes, failedCount, cancelled)`。
  ///
  /// [cancelled] 表示下载期间任务被暂停或取消（调用方据此设置状态）。
  Future<({int sessionBytes, int failedCount, bool cancelled})>
      _downloadSegmentsInParallel({
    required String key,
    required DownloadTask task,
    required DownloadEpisode episode,
    required List<M3u8Segment> segments,
    required Set<int> existingSegments,
    required int existingBytes,
    required String episodeDir,
    required Map<String, String> httpHeaders,
  }) async {
    final pendingIndices = <int>[];
    for (int i = 0; i < segments.length; i++) {
      if (!existingSegments.contains(i)) {
        pendingIndices.add(i);
      }
    }

    var sessionBytes = 0;
    int failedCount = 0;
    if (pendingIndices.isEmpty) {
      return (sessionBytes: 0, failedCount: 0, cancelled: false);
    }

    final completer = Completer<void>();
    int completedCount = 0;
    final semaphore = _Semaphore(maxParallelSegments);

    _speedTrackers[key] = _SpeedTracker();

    for (final idx in pendingIndices) {
      if (task.isPaused || task.cancelToken.isCancelled) break;

      await semaphore.acquire();
      if (task.isPaused || task.cancelToken.isCancelled) {
        semaphore.release();
        break;
      }

      _downloadSegmentWithRetry(
        segments[idx].uri,
        path.join(episodeDir, 'seg_${idx.toString().padLeft(5, '0')}.ts'),
        httpHeaders,
        task.cancelToken,
      ).then((bytes) {
        sessionBytes += bytes.length;
        episode.downloadedSegments++;
        episode.totalBytes = existingBytes + sessionBytes;
        episode.progressPercent =
            episode.downloadedSegments / episode.totalSegments;
        _speedTrackers[key]?.update(sessionBytes);
        _notifyProgress(task.recordKey, task.episodeNumber, episode);
        completedCount++;
        semaphore.release();
        if (completedCount + failedCount == pendingIndices.length) {
          completer.complete();
        }
      }).catchError((e) {
        failedCount++;
        semaphore.release();
        if (completedCount + failedCount == pendingIndices.length) {
          completer.complete();
        }
      });
    }

    if (!task.isPaused &&
        !task.cancelToken.isCancelled &&
        pendingIndices.isNotEmpty) {
      await completer.future;
    }
    return (
      sessionBytes: sessionBytes,
      failedCount: failedCount,
      cancelled: task.isPaused || task.cancelToken.isCancelled,
    );
  }

  Future<void> _runDirectFileDownload({
    required DownloadTask task,
    required int mediaId,
    required String pluginName,
    required String videoUrl,
    required Map<String, String> httpHeaders,
    required DownloadEpisode episode,
  }) async {
    final key = _taskKey(task.recordKey, task.episodeNumber);
    try {
      final episodeDir = await _prepareEpisodeDir(
          episode, mediaId, pluginName, task.episodeNumber);

      final filePath = path.join(episodeDir, 'video.mp4');
      final tmpPath = '$filePath.tmp';

      int existingBytes = 0;
      final tmpFile = File(tmpPath);
      if (await tmpFile.exists()) {
        existingBytes = await tmpFile.length();
      }

      episode.totalSegments = 1;
      episode.downloadedSegments = 0;
      _notifyProgress(task.recordKey, task.episodeNumber, episode);

      final requestHeaders = Map<String, String>.from(httpHeaders);
      bool useRange = existingBytes > 0;
      if (useRange) {
        requestHeaders['Range'] = 'bytes=$existingBytes-';
      }

      Response<ResponseBody> response;
      try {
        response = await _http.getStream(
          videoUrl,
          headers: requestHeaders,
          receiveTimeout: const Duration(minutes: 30),
          cancelToken: task.cancelToken,
        );
      } on NetworkException catch (e) {
        if (e.statusCode == 416 && useRange) {
          WywLogger().w(
            '${LogTag.download} 收到 416 Range Not Satisfiable，删除 tmp 后重试 url=$videoUrl',
          );
          await tmpFile.delete();
          existingBytes = 0;
          requestHeaders.remove('Range');
          response = await _http.getStream(
            videoUrl,
            headers: requestHeaders,
            receiveTimeout: const Duration(minutes: 30),
            cancelToken: task.cancelToken,
          );
        } else {
          rethrow;
        }
      }

      final contentRange = response.headers.value('content-range');
      final contentLength = int.tryParse(
              response.headers.value(Headers.contentLengthHeader) ?? '') ??
          0;
      int totalSize;
      if (contentRange != null) {
        final totalMatch = RegExp(r'/(\d+)').firstMatch(contentRange);
        totalSize = totalMatch != null ? int.parse(totalMatch.group(1)!) : 0;
      } else {
        totalSize = existingBytes + contentLength;
      }

      final raf = await tmpFile.open(
          mode: existingBytes > 0 ? FileMode.append : FileMode.write);
      int received = existingBytes;

      _speedTrackers[key] = _SpeedTracker();

      try {
        await for (final chunk in response.data!.stream) {
          if (task.isPaused || task.cancelToken.isCancelled) break;
          await raf.writeFrom(chunk);
          received += chunk.length;
          episode.totalBytes = received;
          episode.progressPercent = totalSize > 0 ? received / totalSize : 0;
          // Update speed tracker
          _speedTrackers[key]?.update(received);
          _notifyProgress(task.recordKey, task.episodeNumber, episode);
        }
      } finally {
        await raf.close();
      }

      if (task.isPaused || task.cancelToken.isCancelled) {
        if (task.isPaused) {
          episode.status = DownloadStatus.paused;
        }
        _notifyProgress(task.recordKey, task.episodeNumber, episode);
        return;
      }

      await File(tmpPath).rename(filePath);

      episode.status = DownloadStatus.completed;
      episode.localM3u8Path = filePath;
      episode.downloadedSegments = 1;
      episode.progressPercent = 1.0;
      episode.completedAt = DateTime.now();
      episode.totalBytes = await File(filePath).length();
      _notifyProgress(task.recordKey, task.episodeNumber, episode);

      WywLogger().i(
        '${LogTag.download} 直链下载完成 episode=${task.episodeNumber} '
        'size=${(episode.totalBytes / 1024 / 1024).toStringAsFixed(1)}MB',
      );
    } on _InsufficientStorageException catch (e) {
      episode.status = DownloadStatus.failed;
      episode.errorMessage =
          '存储空间不足 (可用: ${fmt.formatBytes(e.availableBytes)})';
      _notifyProgress(task.recordKey, task.episodeNumber, episode);
      WywLogger().w('${LogTag.download} 存储空间不足 episode=${task.episodeNumber}',
          error: e);
    } on FileSystemException catch (e) {
      episode.status = DownloadStatus.failed;
      episode.errorMessage = _getStorageErrorMessage(e);
      _notifyProgress(task.recordKey, task.episodeNumber, episode);
      WywLogger().e('${LogTag.download} 文件系统错误 episode=${task.episodeNumber}',
          error: e);
    } on NetworkException catch (e) {
      if (e.type == NetworkExceptionType.cancel) {
        if (task.isPaused) {
          episode.status = DownloadStatus.paused;
        }
      } else {
        episode.status = DownloadStatus.failed;
        episode.errorMessage = e.message;
      }
      _notifyProgress(task.recordKey, task.episodeNumber, episode);
    } catch (e) {
      episode.status = DownloadStatus.failed;
      episode.errorMessage = e.toString();
      _notifyProgress(task.recordKey, task.episodeNumber, episode);
      WywLogger().e('${LogTag.download} 直链下载失败 episode=${task.episodeNumber}',
          error: e);
    }
  }

  void _onTaskComplete(String key) {
    _activeTasks.remove(key);
    _speedTrackers.remove(key);
    _runningCount--;
    _processQueue();
  }

  void _notifyProgress(
      String recordKey, int episodeNumber, DownloadEpisode episode) {
    final key = _taskKey(recordKey, episodeNumber);
    final speed = _speedTrackers[key]?.currentSpeed ?? 0.0;
    onProgress?.call(recordKey, episodeNumber, episode, speed);
  }

  Future<String> _fetchM3u8(
      String url, Map<String, String> headers, CancelToken cancelToken) async {
    final fetchToken = CancelToken();

    if (cancelToken.isCancelled) {
      throw NetworkException(
        type: NetworkExceptionType.cancel,
        message: '请求已被取消，请重新请求',
      );
    }

    try {
      final content = await _http.getPlain(
        url,
        headers: headers,
        receiveTimeout: const Duration(seconds: 15),
        cancelToken: fetchToken,
        onReceiveProgress: (received, total) {
          if (cancelToken.isCancelled) {
            fetchToken.cancel('task cancelled');
            return;
          }
          if (received > 2 * 1024 * 1024) {
            fetchToken.cancel('too large');
          }
        },
      );

      final trimmed = content.trimLeft();
      if (!trimmed.startsWith('#EXTM3U')) {
        throw _NotM3u8Exception('URL 不是 M3U8 播放列表');
      }

      return content;
    } on NetworkException catch (e) {
      if (cancelToken.isCancelled) rethrow;
      if (e.type == NetworkExceptionType.cancel) {
        throw _NotM3u8Exception('响应过大，非 M3U8 播放列表');
      }
      rethrow;
    }
  }

  /// 下载密钥（key_*.key）到最终路径并返回其字节。
  ///
  /// 与播放代理共享协调器：同一 key 同一时刻只从源站拉一次，
  /// 临时文件唯一、发布带重试，避免 Windows rename 冲突。
  Future<List<int>> _downloadFile(String url, String savePath,
      Map<String, String> headers, CancelToken cancelToken) {
    return SegmentWriteCoordinator.instance.runExclusive(savePath, () async {
      final tmpPath = SegmentWriteCoordinator.instance.uniqueTempPath(savePath);
      try {
        await _http.download(
          url,
          tmpPath,
          headers: headers,
          cancelToken: cancelToken,
        );
        await SegmentWriteCoordinator.instance
            .publish(tmpPath: tmpPath, savePath: savePath);
      } catch (e) {
        try {
          final tmp = File(tmpPath);
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {
          // 静默可接受：下载失败后清理临时 key 文件，主异常仍会 rethrow，删除失败属常态
        }
        SegmentWriteCoordinator.instance.releaseTempPath(tmpPath);
        rethrow;
      }
      return await File(savePath).readAsBytes();
    });
  }

  /// 下载单个分片并发布到最终路径，返回该分片字节。
  ///
  /// 与「播放即下载」代理共享协调器：同一分片（最终路径相同）只会从
  /// 源站拉取一次，临时文件唯一、发布带重试 —— 解决 Windows 下两个
  /// 写入者并发 rename 同一文件时报“另一个程序正在使用此文件”的问题。
  Future<List<int>> _downloadSegmentWithRetry(
    String url,
    String savePath,
    Map<String, String> headers,
    CancelToken cancelToken, {
    int maxRetries = 3,
  }) async {
    int retryCount = 0;
    while (true) {
      try {
        return await SegmentWriteCoordinator.instance.runExclusive(
          savePath,
          () => _downloadSegmentOnce(url, savePath, headers, cancelToken),
        );
      } catch (e) {
        if (cancelToken.isCancelled) rethrow;
        retryCount++;
        if (retryCount >= maxRetries) rethrow;
        final delay = Duration(seconds: [1, 3, 9][retryCount - 1]);
        await Future.delayed(delay);
      }
    }
  }

  /// 单次分片下载：下载到唯一临时文件 → 发布（rename 带重试/复用）。
  Future<List<int>> _downloadSegmentOnce(String url, String savePath,
      Map<String, String> headers, CancelToken cancelToken) async {
    final tmpPath = SegmentWriteCoordinator.instance.uniqueTempPath(savePath);
    try {
      await _http.download(
        url,
        tmpPath,
        headers: headers,
        cancelToken: cancelToken,
      );
      await SegmentWriteCoordinator.instance
          .publish(tmpPath: tmpPath, savePath: savePath);
      return await File(savePath).readAsBytes();
    } catch (e) {
      try {
        final tmpFile = File(tmpPath);
        if (await tmpFile.exists()) await tmpFile.delete();
      } catch (_) {
        // 静默可接受：分片下载失败后清理临时文件，主异常仍会 rethrow，删除失败属常态
      }
      SegmentWriteCoordinator.instance.releaseTempPath(tmpPath);
      rethrow;
    }
  }

  @override
  Future<void> deleteEpisodeFiles(
      int mediaId, String pluginName, int episodeNumber,
      {DownloadEpisode? episode}) async {
    final dir = Directory(await _episodeDirForDeletion(
        episode, mediaId, pluginName, episodeNumber));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  @override
  Future<void> deleteRecordFiles(int mediaId, String pluginName,
      {DownloadRecord? record}) async {
    if (record == null) {
      final dir = Directory(path.join(
          await getDefaultDownloadDirectory(), '${mediaId}_$pluginName'));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      return;
    }

    // Episodes may live under different base directories, so delete each
    // episode directory individually.
    final parentDirs = <String>{};
    for (final entry in record.episodes.entries) {
      final episodeDir = await _episodeDirForDeletion(
          entry.value, mediaId, pluginName, entry.key);
      final dir = Directory(episodeDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      parentDirs.add(path.dirname(episodeDir));
    }

    for (final parentDir in parentDirs) {
      try {
        await Directory(parentDir).delete();
      } on FileSystemException {
        // Parent is missing or still holds other files; leave it.
      }
    }
  }

  @override
  String? getLocalVideoPath(DownloadEpisode? episode) {
    if (episode == null) return null;
    if (episode.status != DownloadStatus.completed) return null;
    if (episode.localM3u8Path.isEmpty) return null;
    final file = File(episode.localM3u8Path);
    if (!file.existsSync()) return null;
    return episode.localM3u8Path;
  }
}

class _Semaphore {
  final int maxCount;
  int _currentCount = 0;
  final _waitQueue = <Completer<void>>[];

  _Semaphore(this.maxCount);

  Future<void> acquire() async {
    if (_currentCount < maxCount) {
      _currentCount++;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeAt(0);
      completer.complete();
    } else {
      _currentCount--;
    }
  }
}
