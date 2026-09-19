import 'package:flutter/material.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/pages/history/history_entry_launcher.dart';
import 'package:wyw/services/storage/history_entry.dart';
import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/history_type.dart';
import 'package:wyw/utils/date_time.dart';
import 'network_img_layer.dart';
import 'swipe_to_delete_card.dart';

/// 视频历史记录卡片（基于 HistoryEntry + VideoProgress）
class ProgressHistoryCardV extends StatefulWidget {
  const ProgressHistoryCardV({
    super.key,
    required this.historyItem,
    this.showDelete = false,
    this.onDeleted,
  });

  final HistoryEntry historyItem;
  final bool showDelete;
  final VoidCallback? onDeleted;

  @override
  State<ProgressHistoryCardV> createState() => _ProgressHistoryCardVState();
}

class _ProgressHistoryCardVState extends State<ProgressHistoryCardV> {
  Future<void> _onTap() async {
    if (widget.showDelete) {
      WywDialog.showToast(message: '编辑模式');
      return;
    }
    if (!mounted) return;
    await HistoryEntryLauncher(context, widget.historyItem).open();
  }

  /// 按类型构建进度信息行：
  /// - 漫画：第 X 话 · 共 Y 话 · 第 P 页（文本）
  /// - 视频：播放到 mm:ss / mm:ss + 进度条
  Widget? _buildProgressInfo(ThemeData theme, ColorScheme colorScheme) {
    final progress = widget.historyItem.parseProgress();
    switch (widget.historyItem.type) {
      case HistoryType.comic:
        if (progress is! ComicProgress) return null;
        final total = progress.chapters.length;
        final idx = HistoryEntryLauncher.comicChapterIndex(progress);
        final ep = total > 0 ? idx + 1 : null;
        final page = HistoryEntryLauncher.comicPageIndex(progress, idx);
        final parts = <String>[
          if (ep != null) '第 $ep 话',
          if (total > 0) '共 $total 话',
          // 规范单位是章内图片序号（与阅读模式无关），故用"张"
          if (page >= 1) '第 $page 张',
        ];
        if (parts.isEmpty) return null;
        return Row(
          children: [
            Icon(Icons.auto_stories_outlined,
                size: 14, color: colorScheme.primary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                parts.join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      case HistoryType.novel:
        if (progress is! ReadProgress) return null;
        final total = progress.chapters.length;
        final parts = <String>[
          if (progress.chapter >= 1) '第 ${progress.chapter} 章',
          if (total > 0) '共 $total 章',
        ];
        if (parts.isEmpty) return null;
        return Row(
          children: [
            Icon(Icons.menu_book_outlined,
                size: 14, color: colorScheme.primary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                parts.join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      case HistoryType.video:
        if (progress is! VideoPlaybackProgress) return null;
        final ep = progress.currentEpisode;
        if (ep == null) return null;
        if (ep.durationMs <= 0) return null;
        final ratio = (ep.positionMs / ep.durationMs).clamp(0.0, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.play_circle_outline,
                    size: 14, color: colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  '播放到 ${_formatDuration(ep.positionMs)} / '
                  '${_formatDuration(ep.durationMs)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 3,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: colorScheme.primary,
              ),
            ),
          ],
        );
      default:
        return null;
    }
  }

  /// 当前条目解析为视频进度（非视频类型返回 null）。
  VideoPlaybackProgress? _videoProgress() {
    if (widget.historyItem.type != HistoryType.video) return null;
    final p = widget.historyItem.parseProgress();
    return p is VideoPlaybackProgress ? p : null;
  }

  /// 当前条目解析为漫画进度（非漫画类型返回 null）。
  ComicProgress? _comicProgress() {
    if (widget.historyItem.type != HistoryType.comic) return null;
    final p = widget.historyItem.parseProgress();
    return p is ComicProgress ? p : null;
  }

  /// 紧凑型文本按钮样式（用于卡片右上/右下角的「选集」小按钮）。
  ButtonStyle _compactTextButtonStyle() {
    return TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: const Size(0, 28),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    );
  }

  /// 毫秒 → mm:ss。
  String _formatDuration(int ms) {
    final s = (ms / 1000).round();
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final double imageWidth = 80;
    final double imageHeight = 108;
    final String title = widget.historyItem.title;
    final String cover = widget.historyItem.cover;
    final Widget? progressInfo = _buildProgressInfo(theme, colorScheme);
    final VideoPlaybackProgress? videoProgress = _videoProgress();
    final ComicProgress? comicProgress = _comicProgress();

    return SwipeToDeleteCard(
      dismissKey: ValueKey(widget.historyItem.key),
      onTap: _onTap,
      onDeleted: widget.onDeleted,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cover != '')
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: NetworkImgLayer(
                  src: cover,
                  width: imageWidth,
                  height: imageHeight,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: imageHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.extension_outlined,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            widget.historyItem.type.value,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                    if (progressInfo != null) ...[
                      const SizedBox(height: 2),
                      progressInfo,
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            formatTimestampToRelativeTime(
                              widget.historyItem.lastWatchTime
                                      .millisecondsSinceEpoch ~/
                                  1000,
                            ),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                        ),
                        // 选集按钮（视频且有完整 sources 时显示）：点卡片续播上次集，
                        // 点此按钮弹选集面板自由选线路/集数。
                        if (!widget.showDelete &&
                            videoProgress != null &&
                            videoProgress.sources.isNotEmpty)
                          TextButton.icon(
                            style: _compactTextButtonStyle(),
                            onPressed: () {
                              if (!mounted) return;
                              HistoryEntryLauncher(context, widget.historyItem)
                                  .openEpisodePicker();
                            },
                            icon: Icon(
                              Icons.menu_open_outlined,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            label: Text(
                              '选集',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        // 选章按钮（漫画且有章节时显示）：点此按钮弹章节面板选章。
                        if (!widget.showDelete &&
                            comicProgress != null &&
                            comicProgress.chapters.isNotEmpty)
                          TextButton.icon(
                            style: _compactTextButtonStyle(),
                            onPressed: () {
                              if (!mounted) return;
                              HistoryEntryLauncher(context, widget.historyItem)
                                  .openChapterPicker();
                            },
                            icon: Icon(
                              Icons.menu_book_outlined,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            label: Text(
                              '选章',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.showDelete)
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: colorScheme.error,
                    ),
                    tooltip: '删除记录',
                    onPressed: () {
                      widget.onDeleted?.call();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
