import 'package:flutter/material.dart';
import 'package:wyw/pages/history/history_entry_launcher.dart';
import 'package:wyw/services/storage/history_entry.dart';
import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/history_type.dart';

/// 进度历史的展示辅助（历史页与「已删除」弹窗共用）。
///
/// 从 `history_page.dart` 抽出来，避免同一套"第几集/话/章"逻辑在两处漂移。

/// 类型中文名（视频 / 漫画 / 小说 / 其它）。
String historyTypeLabel(HistoryType type) => switch (type) {
      HistoryType.video => '视频',
      HistoryType.comic => '漫画',
      HistoryType.novel => '小说',
      HistoryType.custom => '其它',
    };

/// 类型图标。
IconData historyTypeIcon(HistoryType type) => switch (type) {
      HistoryType.video => Icons.play_circle_outline_rounded,
      HistoryType.comic => Icons.auto_stories_rounded,
      HistoryType.novel => Icons.menu_book_rounded,
      HistoryType.custom => Icons.bookmark_border_rounded,
    };

/// 进度摘要（"第 3 集 · 12:34" / "第 5/20 话" / "第 7/30 章"）。
///
/// 无法解析出进度时返回 null（调用方自行决定是否展示）。
String? historyProgressSummary(HistoryEntry entry) {
  final progress = entry.parseProgress();
  switch (entry.type) {
    case HistoryType.video:
      if (progress is! VideoPlaybackProgress) return null;
      final episode = progress.currentEpisode;
      if (episode == null) return null;
      final label = '第 ${progress.lastEpisodeIndex + 1} 集';
      if (episode.durationMs > 0) {
        return '$label · ${formatHistoryPosition(episode.positionMs)}';
      }
      return label;
    case HistoryType.comic:
      if (progress is! ComicProgress) return null;
      if (progress.chapters.isEmpty) return null;
      final index = HistoryEntryLauncher.comicChapterIndex(progress);
      return '第 ${index + 1}/${progress.chapters.length} 话';
    case HistoryType.novel:
      if (progress is! ReadProgress) return null;
      if (progress.chapters.isEmpty) return null;
      return '第 ${progress.chapter}/${progress.chapters.length} 章';
    default:
      return null;
  }
}

/// 毫秒 → `m:ss`（播放位置展示）。
String formatHistoryPosition(int ms) {
  final seconds = (ms / 1000).round();
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}
