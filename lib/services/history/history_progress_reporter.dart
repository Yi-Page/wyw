import 'dart:async';

import 'package:wyw/repositories/i_history_repository.dart';
import 'package:wyw/services/storage/history_type.dart';

import '../logging/log_tags.dart';
import '../logging/logger.dart';
import '../storage/history_entry.dart';

/// 播放器进度 → v2 History 的桥接器
///
/// 设计：
///   - 由 [VideoPageController] 在 init(stop) 时 registerSource(clearSource)
///   - 由 [PlayerController.syncPlaybackState] 在 currentPosition 变化时 reportProgress
///   - 内部 5 秒节流 + last-write-wins；stop 时强制 flush
///
/// 为什么不直接调 sendMessage：
///   Dart 端播放器不知道 pluginName（JS 全局变量），由本 reporter hold source 上下文，
///   repo 自身用 pluginNameResolver 注入。
class HistoryProgressReporter {
  HistoryProgressReporter._();

  static final HistoryProgressReporter _instance = HistoryProgressReporter._();

  factory HistoryProgressReporter() => _instance;

  /// 由 core_module 启动时注入（late — 必须先 configure 才能 report）
  late IHistoryRepository? Function() _repoResolver;

  void configure(IHistoryRepository? Function() resolver) {
    _repoResolver = resolver;
  }

  /// 结构化模式（VideoPage 带 VideoPageRouteArgs 进入）时置 true：
  /// 进度改由 VideoPageController.onProgressChanged 写 v3，reporter 不再写盘。
  bool _muted = false;

  /// muted 时的进度转发回调（position/duration 变化时由 player 侧触发）。
  void Function(int positionMs, int durationMs)? onMutedProgress;

  /// 进入/退出结构化模式。调用方（VideoPage）负责配对调用。
  void setMuted(bool value) {
    _muted = value;
  }

  /// 按 sourceId 查一条历史（不依赖当前正在播放的 source）
  /// 给 controller 在拿到 resolved videoUrl 后查续播进度用
  HistoryEntry? findEntry(
      {required HistoryType type, required String sourceId}) {
    final repo = _repoResolver();
    if (repo == null) return null;
    return repo.find(type: type, sourceId: sourceId);
  }

  /// 当前正在播放的 source 上下文（null 时 reportProgress 为 no-op）
  String? _currentSourceId;
  HistoryType _currentType = HistoryType.video;
  String? _videoTitle;
  String? _videoCover;

  /// 5 秒内最多写盘一次（throttle，不是 debounce；新 reportProgress 不重置窗口）
  int? _lastWritePositionMs;
  DateTime? _lastWriteAt;
  static const Duration _throttleInterval = Duration(seconds: 5);

  /// 由 VideoPageController.init(params) 调用
  void registerSource({
    required String sourceId,
    required HistoryType type,
    required String title,
    required String cover,
  }) {
    WywLogger().i(
        '${LogTag.history} 注册播放源 sourceId=$sourceId type=$type muted=$_muted');
    _currentSourceId = sourceId;
    _currentType = type;
    _videoTitle = title;
    _videoCover = cover;
    _lastWriteAt = null;
    _lastWritePositionMs = null;
  }

  /// 由 VideoPageController.stop() 调用
  Future<void> clearSource() async {
    final prev = _currentSourceId;
    WywLogger().i('${LogTag.history} 清除播放源 prev=$prev muted=$_muted');
    // 先 flush 确保最后一次进度落盘（结构化模式 muted 时 no-op）
    await flush();
    _currentSourceId = null;
    _currentType = HistoryType.video;
    _lastWriteAt = null;
    _lastWritePositionMs = null;
  }

  /// 由 PlayerController.syncPlaybackState 在 position 变化时调用
  ///
  /// 5s throttle：同一 source 在 5 秒内最多写盘一次。
  /// 退出时由 [clearSource]/[flush] 强制写最后一次。
  void reportProgress({
    required int positionMs,
    required int durationMs,
  }) {
    // 结构化模式：转发给 VideoPageController，不写盘（v3 由 onProgressChanged 写）
    if (_muted) {
      onMutedProgress?.call(positionMs, durationMs);
      return;
    }
    final sourceId = _currentSourceId;
    if (sourceId == null) return;
    final title = _videoTitle;
    if (title == null) return;
    final cover = _videoCover;
    if (cover == null) return;
    final now = DateTime.now();
    final sinceLast =
        _lastWriteAt == null ? null : now.difference(_lastWriteAt!);
    if (sinceLast != null && sinceLast < _throttleInterval) {
      // 还在 throttle 窗口内，跳过写盘
      return;
    }
    _lastWriteAt = now;
    _lastWritePositionMs = positionMs;
    final repo = _repoResolver();
    if (repo == null) return;
    repo.setProgress(
      type: _currentType,
      sourceId: sourceId,
      title: title,
      cover: cover,
      progress: {
        'videoUrl': sourceId,
        'positionMs': positionMs,
        'durationMs': durationMs,
      },
    );
    WywLogger().i('${LogTag.history} 写入播放进度 '
        'sourceId=$sourceId positionMs=$positionMs（5s 节流窗口外）');
  }

  /// 由 VideoPageController.stop() 调用，强制立即落盘最后一次
  Future<void> flush() async {
    if (_muted) return;
    final sourceId = _currentSourceId;
    if (sourceId == null) return;
    final repo = _repoResolver();
    if (repo == null) return;
    final title = _videoTitle;
    if (title == null) return;
    final cover = _videoCover;
    if (cover == null) return;
    await repo.flush(
        type: _currentType, sourceId: sourceId, title: title, cover: cover);
    WywLogger().i('${LogTag.history} 进度落盘完成 sourceId=$sourceId '
        'finalPos=$_lastWritePositionMs');
  }
}
